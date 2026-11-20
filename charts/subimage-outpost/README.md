# SubImage Outpost Helm Chart

Deploy SubImage Outpost with Tailscale in restrictive Kubernetes environments. This Helm chart is designed to work around common cluster restrictions while maintaining security best practices.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
  - [Before You Begin](#before-you-begin)
  - [Quick Start](#quick-start)
- [Configuration](#configuration)
  - [Required Values](#required-values)
  - [Common Configurations](#common-configurations)
  - [RBAC for Kubernetes API Access](#6-kubernetes-api-access-rbac)
- [Usage](#usage)
  - [Verify Deployment](#verify-deployment)
  - [Access via Tailscale](#access-via-tailscale)
  - [Testing Kubernetes API Access](#testing-kubernetes-api-access)
- [Troubleshooting](#troubleshooting)
- [Upgrading](#upgrading)
- [Uninstallation](#uninstallation)
- [Security Considerations](#security-considerations)
- [Limitations](#limitations)

## Overview

SubImage Outpost creates a secure proxy using Tailscale to access private Kubernetes clusters for security scanning. This chart handles:

- Pod Security Standards exemptions
- Service mesh injection (Istio, Linkerd) exclusion
- NetworkPolicy configuration for Tailscale connectivity
- Corporate proxy support
- Resource constraints and node placement

## Prerequisites

- Kubernetes 1.21+
- Helm 3.0+
- Tailscale OAuth client secret (provided by SubImage)

## Installation

### Before You Begin

**You will need:**
1. **Tailscale OAuth Client Secret** - Provided by SubImage
   - Format: `tskey-client-xxxxx-xxxxxxxxxxxxxx`
   - This is created by SubImage and scoped to your tenant
   - Contact SubImage support if you don't have this secret
   - **Note**: The chart automatically appends `?ephemeral=true` to ensure the Tailscale node is removed when the pod is deleted
2. **Tenant ID** - Your tenant identifier (provided by SubImage)
   - Example: `veriff`, `acme`, `customer-name`
   - Used for Tailscale hostname and ACL tags

### Quick Start

Create a values file with your configuration:

```bash
cat > my-values.yaml <<EOF
outpost:
  tenantId: "customer-name"
  authKey: "tskey-client-xxxxx-xxxxxxxxxxxxxx"
  proxyTarget: "https://kubernetes.default.svc"
  verifyTls: false
  # name: "subimage"  # Optional - only needed for multiple outposts
EOF

helm install my-outpost ./subimage-outpost -f my-values.yaml
```

> **Security Note**: Always use a values file (`-f`) for sensitive data like `authKey`. Avoid passing secrets via `--set` on the command line, as they are exposed in shell history and process listings.

**Important Notes:**
- The Tailscale hostname will be: `{tenantId}-{name}-outpost` (e.g., `veriff-subimage-outpost`)
- The default `name` is `subimage` - only override if deploying multiple outposts for the same tenant

## Configuration

### Required Values

These values must be provided:

```yaml
outpost:
  # REQUIRED
  tenantId: "customer-name"          # Your tenant ID (provided by SubImage)
  authKey: "tskey-client-xxxxx"      # Tailscale OAuth client secret (provided by SubImage)
  proxyTarget: "https://kubernetes.default.svc"  # Target URL to proxy
  verifyTls: false                    # Set to false for self-signed certificates
  
  # OPTIONAL
  name: "subimage"                   # Outpost name - only needed for multiple outposts
  proxyHost: ""                      # Override Host header (leave empty for default)
  connectTimeout: ""                 # Seconds to connect to proxyTarget (image default: 15)
  readTimeout: ""                    # Seconds to wait for a response (image default: 60)
```

**How the hostname is constructed:**
- Tailscale hostname: `{tenantId}-{name}-outpost`
- Example: `tenantId: "veriff"`, `name: "subimage"` → hostname `veriff-subimage-outpost`

**Multiple outposts for the same tenant:**
If you need to deploy multiple outposts (e.g., for different Kubernetes clusters), use different `name` values:
- `name: "eks"` → `veriff-eks-outpost`
- `name: "gke"` → `veriff-gke-outpost`
- `name: "rancher"` → `veriff-rancher-outpost`

### Common Configurations

#### 1. Corporate Proxy Environment

For clusters behind a corporate proxy:

```yaml
proxy:
  enabled: true
  httpProxy: "http://proxy.company.com:8080"
  httpsProxy: "http://proxy.company.com:8080"
  allProxy: "http://proxy.company.com:8080"
  noProxy: "localhost,127.0.0.1,.svc,.cluster.local"
```

#### 2. Pod Security Standards

The outpost pod meets the `restricted` Pod Security Standard with the default values. It runs as a non-root user (UID 10001), drops all Linux capabilities, blocks privilege escalation, and uses the `RuntimeDefault` seccomp profile. Tailscale runs in userspace networking mode, so the pod needs no `NET_ADMIN` capability and no host access.

When the chart creates the namespace, it enforces `baseline` and audits and warns at `restricted`. To enforce `restricted`:

```yaml
namespace:
  podSecurity:
    enforce: "restricted"
    audit: "restricted"
    warn: "restricted"
```

If you deploy into an existing namespace (`namespace.create: false`), that namespace's own Pod Security labels apply. The pod is admitted at any level, as long as no admission webhook injects a container or volume that the level rejects. See [Admission Webhooks and Pod Labels](#admission-webhooks-and-pod-labels).

The pod-level and container-level security contexts are `podSecurityContext` and `securityContext` in [values.yaml](values.yaml).

#### Admission Webhooks and Pod Labels

Mutating admission webhooks can inject sidecars or volumes into every pod. An injected `hostPath` volume or privileged container makes the pod fail the `baseline` and `restricted` levels, so the namespace rejects it and the install times out. Most webhooks let a pod opt out with a label. Set it with `podLabels`.

For example, on a cluster running Datadog's admission controller, which injects a `hostPath` volume:

```yaml
podLabels:
  admission.datadoghq.com/enabled: "false"
```

`podLabels` adds labels to the pod template only. The selector labels `app.kubernetes.io/name` and `app.kubernetes.io/instance` are reserved, and setting either one fails the render. For annotation-based opt-outs, use `podAnnotations`.

#### 3. Tainted Nodes

To schedule on specific nodes:

```yaml
nodeSelector:
  node.kubernetes.io/purpose: outpost

tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "outpost"
    effect: "NoSchedule"
```

#### 4. Service Mesh Environments

The chart automatically disables Istio and Linkerd injection via namespace labels. If you need additional exclusions:

```yaml
namespace:
  labels:
    istio-injection: disabled
    linkerd.io/inject: disabled
    custom-mesh.io/inject: disabled
```

#### 5. Network-Restricted Clusters

The chart creates an egress NetworkPolicy for the outpost pod. The default rules work in IPv4-only, IPv6-only, and dual-stack clusters without any cluster-specific addresses:

| Destination | Ports | Why |
|-------------|-------|-----|
| Any address | TCP 443 | Tailscale control plane, logging, and DERP relays; the Kubernetes API on managed clusters; `outpost.proxyTarget` |
| Any address | TCP 6443 | The Kubernetes API on self-managed clusters, where the `kubernetes` Service endpoints are node IPs |
| Any address | UDP 3478, UDP 41641 | STUN and direct WireGuard connections. Without them, Tailscale relays all traffic through DERP over TCP 443 |
| `kube-system` namespace | UDP 53, TCP 53 | Cluster DNS |

TCP 443 stays open to any address by default because Tailscale serves its control plane and DERP relays from addresses that change over time, and the chart cannot know where `outpost.proxyTarget` lives.

**Add a destination.** Use `networkPolicy.extraEgressRules` to append rules without copying the defaults. For example, if `outpost.proxyTarget` is an in-cluster Service whose pods listen on port 8443:

```yaml
networkPolicy:
  extraEgressRules:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: internal-api
      ports:
        - protocol: TCP
          port: 8443
```

NetworkPolicy matches the port the destination pod listens on, not the Service port.

**Run a strict policy.** Replace `networkPolicy.egressRules` to allow only the addresses the outpost needs:

1. Cluster DNS: UDP and TCP 53 to `kube-system`.
2. The Kubernetes API server endpoints. Find them with `kubectl get endpoints kubernetes -n default`.
3. Tailscale's API, control plane, and logging ranges, and the DERP relays your tailnet uses. At startup the outpost calls `api.tailscale.com` on TCP 443 to exchange its OAuth client secret for an auth key. Tailscale lists them in [What firewall ports should I open to use Tailscale?](https://tailscale.com/kb/1082/firewall-ports) and publishes the DERP relay addresses in its [DERP map](https://login.tailscale.com/derpmap/default).
4. UDP 3478 to the DERP relays and UDP 41641 to any address, unless you accept relayed connections only.
5. The address of `outpost.proxyTarget`, if it is not the Kubernetes API.

[`ci/restricted-values.yaml`](ci/restricted-values.yaml) shows the shape of a strict policy with placeholder addresses. Tailscale changes these addresses over time. When a strict policy falls out of date, the outpost cannot reach Tailscale and goes offline, so review it whenever Tailscale updates its list.

To manage egress yourself, set `networkPolicy.enabled: false`.

#### 6. Kubernetes API Access (RBAC)

**IMPORTANT:** If `proxyTarget` is the Kubernetes API server (`https://kubernetes.default.svc`), the outpost needs RBAC permissions to authenticate API requests.

The chart creates a ServiceAccount with a ClusterRole by default:

```yaml
rbac:
  create: true
```

**How Authentication Works:**

When `rbac.create: true`, the chart automatically:
1. Creates a ServiceAccount for the outpost pod
2. Mounts the ServiceAccount token at `/var/run/secrets/kubernetes.io/serviceaccount/token`
3. Sets `BEARER_TOKEN_PATH` environment variable to point to the token file
4. The proxy automatically injects `Authorization: Bearer <token>` headers to all Kubernetes API requests
5. Grants access to non-resource URLs (API discovery endpoints like `/`, `/api`, `/apis`, `/version`)

This means requests to the Kubernetes API will be authenticated as the ServiceAccount, allowing SubImage to scan your cluster with the configured RBAC permissions.

Today, the chart's default `ClusterRole` grants the read-only permissions needed
for SubImage's Kubernetes and EKS discovery:

- core resources:
  `namespaces`, `pods`, `services`, and `serviceaccounts` with `get` / `list`
- nodes:
  `nodes` with `list`
- persistent storage:
  `persistentvolumes`, `persistentvolumeclaims`,
  `storage.k8s.io/storageclasses`, and `storage.k8s.io/volumeattachments` with
  `list` so SubImage can map pod mounts to their backing volumes, storage
  classes, CSI drivers, and planned volume-to-node attachment state
- secrets:
  `secrets` with `list` (opt-out via `rbac.secrets: false` — see note below)
- EKS metadata:
  `configmaps` with `get` so the scanner can read `kube-system/aws-auth`
  (narrow it with `rbac.configMaps` — see note below)
- workload controllers:
  `apps/deployments`, `apps/replicasets`, `apps/statefulsets`,
  `apps/daemonsets`, `batch/jobs`, and `batch/cronjobs` with `list`
- networking:
  `networking.k8s.io/ingresses` with `get` / `list`
- Gateway API:
  `gateway.networking.k8s.io/gateways` and
  `gateway.networking.k8s.io/httproutes` with `list`. These permissions are
  only used when Gateway API CRDs are installed in the cluster.
- AWS Load Balancer Controller:
  `elbv2.k8s.aws/targetgroupbindings` with `list` so SubImage can link AWS
  load balancer target groups to the Services they route to. This permission is
  only used when the AWS Load Balancer Controller CRDs are installed in the
  cluster.
- RBAC objects:
  `roles`, `rolebindings`, `clusterroles`, and `clusterrolebindings` with `get` /
  `list`
- non-resource URLs:
  `/`, `/api`, `/apis`, `/version`, and `/healthz` with `get`

**Security Note:** Non-resource URL permissions allow discovering which API groups and versions exist, but do **not** grant access to the resources themselves. For example, access to `/apis/apps/v1` allows seeing that the "apps" API group exists, but listing `/apis/apps/v1/deployments` still requires explicit `resources: ["deployments"]` permissions.

**Secrets Note:** `list` on `secrets` returns full Secret data (values), not just metadata. The default `rbac.secrets: true` grants this cluster-wide. If the outpost does not need Secret contents, opt out:

```yaml
rbac:
  create: true
  secrets: false
```

**ConfigMaps Note:** The default `rbac.configMaps: all` grants `get`, never `list`, on ConfigMaps cluster-wide. SubImage reads `kube-system/aws-auth` to map IAM principals to Kubernetes users and groups on EKS, and the default lets new coverage that reads a ConfigMap work without a chart change. To narrow it:

```yaml
rbac:
  create: true
  # awsAuth: only kube-system/aws-auth, through a Role in kube-system
  # none:    no ConfigMap access, for clusters that are not EKS
  configMaps: awsAuth
```

**Important:** The chart does not currently expose `readAll`, `resourceGroups`, or
other granular RBAC values. If you need a different permission set, update the
rendered `ClusterRole` template before deploying.

**Understanding RBAC Permissions:**

Kubernetes RBAC has two separate permission systems:

| Permission Type | Controls Access To | Example Paths | Grants Resource Access? |
|----------------|-------------------|---------------|------------------------|
| **Non-Resource URLs** | API discovery, health checks, metadata | `/`, `/api`, `/apis`, `/version`, `/healthz` | ❌ No - metadata only |
| **Resources** | Actual Kubernetes objects | `pods`, `services`, `ingresses` | ✅ Yes - allows get/list/watch |

**Example:** With only `nonResourceURLs: ["/apis/*"]`:
- ✅ Can access `/apis/apps/v1` (see that the "apps" API group exists)
- ❌ Cannot access `/apis/apps/v1/deployments` (requires `resources: ["deployments"]`)

Both permissions are needed for a functional API client.

**To disable RBAC** (only if not accessing the Kubernetes API):

```yaml
rbac:
  create: false
```

#### 7. Custom Bearer Token Authentication

For proxying to services that require authentication beyond Kubernetes API (which is handled automatically via RBAC), you can provide custom bearer tokens:

**Option 1: Token from a Secret, as an environment variable**
```yaml
rbac:
  create: false

extraEnv:
  - name: BEARER_TOKEN
    valueFrom:
      secretKeyRef:
        name: target-api-token
        key: token
```

**Option 2: Token from a mounted file**

The outpost reads the file on each request, so a rotated Secret takes effect without a restart.

```yaml
rbac:
  create: false

extraVolumes:
  - name: target-api-token
    secret:
      secretName: target-api-token

extraVolumeMounts:
  - name: target-api-token
    mountPath: /etc/outpost/token
    readOnly: true

extraEnv:
  - name: BEARER_TOKEN_PATH
    value: /etc/outpost/token/token
```

**Note:** When `rbac.create: true`, `BEARER_TOKEN_PATH` is automatically set to the Kubernetes ServiceAccount token path. For custom services, set `rbac.create: false` and provide the token with one of the options above. `BEARER_TOKEN` takes precedence over `BEARER_TOKEN_PATH`.

#### 8. Extra Environment Variables and Volumes

`extraEnv`, `extraVolumes`, and `extraVolumeMounts` pass through to the outpost pod unchanged. For example, to verify a private target against your own CA:

```yaml
outpost:
  proxyTarget: "https://api.internal.example.com"
  verifyTls: true
  caBundle: /etc/outpost/ca/ca.crt

extraVolumes:
  - name: target-ca
    configMap:
      name: target-ca

extraVolumeMounts:
  - name: target-ca
    mountPath: /etc/outpost/ca
    readOnly: true
```

### All Configuration Options

See [values.yaml](values.yaml) for complete configuration options including:

- **RBAC permissions** for Kubernetes API access
- Resource requests and limits
- Liveness and readiness probes
- Security context
- Affinity rules
- Service account configuration
- Extra environment variables, volumes, and volume mounts

## Usage

### Verify Deployment

```bash
# Check pod status
kubectl get pods -n subimage-outpost

# View logs
kubectl logs -n subimage-outpost -l app.kubernetes.io/name=subimage-outpost

# Check Tailscale connection
kubectl exec -n subimage-outpost deployment/my-outpost-subimage-outpost -- \
  tailscale status
```

### Access via Tailscale

Once deployed, the outpost will be accessible via Tailscale at:
```
http://{customerName}-subimage-outpost.tail<network-id>.ts.net/
```

For example, if `customerName: "acme"`:
```
http://acme-subimage-outpost.tail788e86.ts.net/
```

### Testing Kubernetes API Access

If you're using the outpost to access the Kubernetes API, verify RBAC permissions:

```bash
# 1. Check ServiceAccount was created
kubectl get serviceaccount -n subimage-outpost

# 2. Verify ClusterRole exists and includes non-resource URLs
kubectl get clusterrole | grep subimage-outpost
kubectl describe clusterrole <release-name>-subimage-outpost
# Should show rules for both resources AND nonResourceURLs (/, /api, /apis, etc.)

# 3. Check ClusterRoleBinding
kubectl get clusterrolebinding | grep subimage-outpost

# 4. Test API discovery endpoint from within the pod
kubectl exec -n subimage-outpost deployment/my-outpost-subimage-outpost -- \
  curl -k -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  https://kubernetes.default.svc/

# 5. Test resource access (namespaces list)
kubectl exec -n subimage-outpost deployment/my-outpost-subimage-outpost -- \
  curl -k -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  https://kubernetes.default.svc/api/v1/namespaces

# Expected: JSON responses
# If you get 403 Forbidden, check RBAC configuration
```

**From Tailscale network**, test the proxy (bearer token is injected automatically):

```bash
# Test API discovery endpoint
curl http://acme-subimage-outpost.tail788e86.ts.net/

# List all namespaces
curl http://acme-subimage-outpost.tail788e86.ts.net/api/v1/namespaces

# List all pods in all namespaces
curl http://acme-subimage-outpost.tail788e86.ts.net/api/v1/pods

# List all NetworkPolicies in all namespaces
curl http://acme-subimage-outpost.tail788e86.ts.net/apis/networking.k8s.io/v1/networkpolicies

# Get specific namespace
curl http://acme-subimage-outpost.tail788e86.ts.net/api/v1/namespaces/default
```

## Troubleshooting

### Pod Stuck in Pending

**Symptom**: Pod remains in Pending state
**Possible causes**:
1. Insufficient node resources
2. Node selector/affinity not matching any nodes
3. Pod Security Standards blocking pod

**Solution**:
```bash
kubectl describe pod -n subimage-outpost -l app.kubernetes.io/name=subimage-outpost
```

### ImagePullBackOff

**Symptom**: Cannot pull image from ghcr.io
**Solution**: The image is public and should be accessible without authentication. Check network connectivity to ghcr.io and verify the image tag exists.

### No Logs Visible

**Symptom**: Pod running but no logs in `kubectl logs`
**Solution**: This was fixed in v0.0.4. Ensure you're using image tag `0.0.4` or later.

### Tailscale Connection Failed

**Symptom**: Logs show "ERROR: Tailscaled socket not found" or authentication errors
**Possible causes**:
1. Invalid OAuth client secret (check that it starts with `tskey-client-`)
2. OAuth client not enabled in Tailscale (requires Terraform apply)
3. Network policy blocking egress
4. Corporate proxy configuration needed

**Solution**:
```bash
# 1. Verify the secret contains the correct OAuth client secret
kubectl get secret -n subimage-outpost <release-name>-subimage-outpost-secrets -o yaml
# Should show TAILSCALE_AUTHKEY starting with "tskey-client-"

# 2. Check if NetworkPolicy is blocking
kubectl get networkpolicy -n subimage-outpost

# 3. Verify IPv4 and IPv6 egress is allowed to:
# - TCP 443 (Tailscale control plane, DERP relays and Kubernetes API service addresses)
# - TCP 6443 (Kubernetes API on self-managed clusters: kubeadm, RKE, most on-prem)
# - UDP 3478 (STUN)
# - UDP 41641 (direct WireGuard)
# - UDP 53 and TCP 53 (cluster DNS; TCP is the glibc fallback for truncated replies)
# With a strict networkPolicy.egressRules, also check that Tailscale has not
# changed the addresses it serves from.

# 3b. Confirm which port your API server endpoints actually use. If this shows
# 6443 and egress to 6443 is blocked, the SYN is dropped rather than refused,
# which surfaces as a connect timeout instead of a DNS or TLS error.
kubectl get endpoints kubernetes -n default

# 4. If using OAuth client, ensure it's enabled in Tailscale
# Contact SubImage support to verify Terraform was applied
```

### Service Mesh Interference

**Symptom**: Tailscale fails to connect with service mesh enabled
**Solution**: Verify namespace labels are excluding injection:
```bash
kubectl get namespace subimage-outpost -o yaml
# Should see: istio-injection: disabled
```

### API Access Returns 401/403 Errors

**Symptom**: Requests via Tailscale to Kubernetes API return `401 Unauthorized` or `403 Forbidden`

**Possible causes**:
1. ServiceAccount not created
2. ClusterRole/ClusterRoleBinding missing
3. Insufficient RBAC permissions
4. Bearer token not being injected (check `BEARER_TOKEN_PATH` environment variable)

**Solution**:
```bash
# 1. Verify ServiceAccount exists and is bound to the pod
kubectl get serviceaccount -n subimage-outpost
kubectl get pod -n subimage-outpost -o yaml | grep serviceAccountName

# 2. Check that BEARER_TOKEN_PATH is set (should point to ServiceAccount token)
kubectl exec -n subimage-outpost deployment/my-outpost-subimage-outpost -- \
  env | grep BEARER_TOKEN_PATH
# Expected: BEARER_TOKEN_PATH=/var/run/secrets/kubernetes.io/serviceaccount/token

# 3. Verify token file exists and is readable
kubectl exec -n subimage-outpost deployment/my-outpost-subimage-outpost -- \
  cat /var/run/secrets/kubernetes.io/serviceaccount/token

# 4. Check ClusterRole permissions
kubectl describe clusterrole <release-name>-subimage-outpost

# 5. Verify ClusterRoleBinding
kubectl describe clusterrolebinding <release-name>-subimage-outpost

# 6. Test API access from within the pod
kubectl exec -n subimage-outpost deployment/my-outpost-subimage-outpost -- \
  curl -k -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  https://kubernetes.default.svc/api/v1/namespaces

# 7. If using granular permissions, ensure required resources are allowed
# Check your values.yaml rbac.resourceGroups configuration
```

**If you get 403 Forbidden for specific resources:**
- Set `rbac.readAll: true` for full read access
- OR add missing resources to `rbac.resourceGroups`

**For non-Kubernetes API targets:**
If you're proxying to an internal service that requires authentication, you can provide a custom bearer token:

```yaml
# Option 1: Direct token (not recommended for production - use secrets)
outpost:
  extraEnv:
    - name: BEARER_TOKEN
      value: "your-api-token-here"

# Option 2: Token from a mounted secret file
outpost:
  extraEnv:
    - name: BEARER_TOKEN_PATH
      value: "/path/to/token/file"
```

## Upgrading

```bash
helm upgrade my-outpost ./subimage-outpost -f my-values.yaml
```

### Upgrading to 1.7.0

- The default egress rules no longer allow TCP 443 and 6443 to every pod in the cluster. If `outpost.proxyTarget` is an in-cluster Service, allow its pods with `networkPolicy.extraEgressRules`. Releases that set `networkPolicy.egressRules` themselves are unaffected.
- The pod now runs with `runAsNonRoot`, the `RuntimeDefault` seccomp profile, `allowPrivilegeEscalation: false`, and all capabilities dropped. If you set `securityContext`, Helm merges your keys over these defaults.
- A chart-created namespace now audits and warns at the `restricted` Pod Security level. Enforcement stays at `baseline`.

## Uninstallation

```bash
helm uninstall my-outpost

# If namespace was created by the chart:
kubectl delete namespace subimage-outpost
```

**Note**: The Tailscale node will be automatically removed from your tailnet when the pod is deleted because the chart uses ephemeral authentication (`?ephemeral=true` is automatically appended to the auth key).

## Security Considerations

1. **Ephemeral Nodes**: The chart automatically appends `?ephemeral=true` to auth keys, ensuring Tailscale nodes are removed when pods are deleted
2. **Secrets Management**: Consider using external secret managers (AWS Secrets Manager, HashiCorp Vault)
3. **Network Policies**: The chart creates NetworkPolicy by default - ensure your CNI supports it
4. **Pod Security**: The outpost pod meets the `restricted` Pod Security Standard. A chart-created namespace enforces `baseline` and warns at `restricted` by default
5. **Resource Limits**: Configure appropriate limits to prevent resource exhaustion

## Limitations

### Single Replica Only

The outpost **always runs as a single replica** (cannot be scaled). This is by design because:
- Tailscale ephemeral nodes use the same hostname
- Multiple pods would create conflicting Tailscale nodes (hostname-1, hostname-2, etc.)
- The deployment uses `strategy: Recreate` to ensure the old pod is fully terminated before starting a new one

### Air-gapped Clusters

This chart requires internet access to reach Tailscale's control plane and DERP servers. For truly air-gapped clusters without internet access, deploy the outpost externally instead:
- AWS ECS/Fargate
- Google Cloud Run
- EC2/VM with internet access

The outpost runs outside and proxies INTO the air-gapped cluster.
