# AGENTS.md

## Cursor Cloud specific instructions

This repository is a **Helm chart repository** for SubImage products (currently one chart:
`charts/subimage-outpost`). There is no compiled application or package manager here; the
"product" is the packaged Helm chart. Development is done with the Helm CLI, and CI only runs
`helm lint` + `helm template` (see `.github/workflows/lint-test.yml`).

### Tooling (installed by the update script)

- `helm`, `kubectl`, `kwok`, `kwokctl` are installed as binaries into `/usr/local/bin` by the
  startup update script. No project dependency manager exists.

### Lint / build-test (no cluster required)

These mirror CI and are the primary check surface:

```bash
helm lint charts/subimage-outpost
helm template test-release charts/subimage-outpost -f charts/subimage-outpost/values-example.yaml
```

Note: `helm lint` prints two `[INFO] Missing required value ...` lines for `values.yaml`
(no `tenantId`/`authKey`). That is expected — those values are only supplied at install time —
and the lint still reports `0 chart(s) failed`.

### Running the chart (deploying it) — use kwok, NOT kind/minikube/k3d

A real kubelet-based cluster (kind, k3d, minikube) **cannot boot in this sandbox**: the nested
Firecracker environment does not delegate the `memory` cgroup v2 controller to child cgroups
(`echo +memory > /sys/fs/cgroup/cgroup.subtree_control` fails with EIO, and moving processes
between cgroups fails with EOPNOTSUPP). Symptoms if you try anyway: kind nodes exit with
`Failed to create /init.scope control group: Structure needs cleaning`, and k3s exits with
`failed to find memory cgroup (v2)`. Docker itself installs/runs fine, but the node containers
will not start, so don't waste time on kind/k3d/minikube.

Instead use **`kwok`** (Kubernetes WithOut Kubelet), which runs a real `kube-apiserver` +
control plane as plain host binaries (no docker, no cgroups) and simulates pods to `Running`:

```bash
kwokctl create cluster --name subimage-dev --runtime binary --wait 120s
# add a schedulable fake node (apply a Node with annotation kwok.x-k8s.io/node: fake and no NoSchedule taint)
helm install my-outpost charts/subimage-outpost \
  --set outpost.tenantId=acme \
  --set outpost.name=eks-demo \
  --set outpost.authKey.value=tskey-client-demo-abc123
kubectl get all -n subimage-outpost   # pod becomes 1/1 Running
```

`kwokctl create cluster` sets/points the kubectl context automatically. Tear down with
`kwokctl delete cluster --name subimage-dev`.

### What cannot be tested here

A true functional end-to-end (the outpost actually tunneling via Tailscale to the SubImage SaaS
backend) requires external, SubImage-issued credentials (a real Tailscale OAuth client secret /
tenant) and the SubImage backend, none of which live in this repo. kwok validates that the chart
deploys and all resources (Deployment/Pod, ClusterRole/Binding, Secret, ServiceAccount,
NetworkPolicy, Namespace) render and apply correctly, and that values propagate into the pod spec.
