# SubImage Helm Charts

Public Helm charts for SubImage products.

## Available Charts

| Chart | Description |
|-------|-------------|
| [subimage-outpost](./charts/subimage-outpost) | Deploy SubImage Outpost with Tailscale in Kubernetes |

## Usage

### Add the Helm Repository

```bash
helm repo add subimage https://subimagesec.github.io/helm-charts/
helm repo update
```

### Install a Chart

```bash
helm install my-outpost subimage/subimage-outpost \
  --set outpost.tenantId="your-tenant-id" \
  --set outpost.authKey.value="tskey-client-xxxxx-xxxxxxxxxxxxxx"
```

See the [subimage-outpost README](./charts/subimage-outpost/README.md) for detailed configuration options.

## Development

This repository packages SubImage products as Helm charts. There is no application code or package
manager — the deliverable is the chart itself, developed with the Helm CLI.

### Prerequisites

- [`helm`](https://helm.sh/docs/intro/install/) (v3)
- [`kubectl`](https://kubernetes.io/docs/tasks/tools/) — only needed to deploy the chart to a cluster

### Lint and template (no cluster required)

These mirror what CI runs (see [`.github/workflows/lint-test.yml`](./.github/workflows/lint-test.yml))
and are the primary checks when changing a chart:

```bash
helm lint charts/subimage-outpost
helm template test-release charts/subimage-outpost -f charts/subimage-outpost/values-example.yaml
```

`helm lint` prints two `[INFO] Missing required value ...` lines for `values.yaml` (no
`tenantId` / `authKey`). This is expected — those values are supplied at install time — and lint
still reports `0 chart(s) failed`.

### Deploying the chart to a local cluster

Any Kubernetes cluster works. For a real kubelet-based local cluster,
[kind](https://kind.sigs.k8s.io/), [minikube](https://minikube.sigs.k8s.io/), or
[k3d](https://k3d.io/) are all fine:

```bash
kind create cluster
helm install my-outpost charts/subimage-outpost \
  --set outpost.tenantId=acme \
  --set outpost.name=eks-demo \
  --set outpost.authKey.value=tskey-client-xxxxx
kubectl get all -n subimage-outpost
```

#### Restricted / nested container environments

Some sandboxed environments (certain CI runners, dev containers, or nested Docker setups) do not
delegate the `memory` cgroup v2 controller to child cgroups. There, a real kubelet-based node
cannot boot — kind nodes exit with `Failed to create /init.scope control group: Structure needs
cleaning`, and k3s exits with `failed to find memory cgroup (v2)`.

In those cases, [`kwok`](https://kwok.sigs.k8s.io/) ("Kubernetes WithOut Kubelet") runs a real
control plane as plain host binaries (no Docker, no cgroups) and simulates pods, which is enough
to validate that the chart deploys and its resources render/apply correctly:

```bash
kwokctl create cluster --name dev --runtime binary --wait 120s
# add a schedulable fake Node (annotation kwok.x-k8s.io/node: fake, no NoSchedule taint), then:
helm install my-outpost charts/subimage-outpost \
  --set outpost.tenantId=acme \
  --set outpost.authKey.value=tskey-client-xxxxx
kubectl get all -n subimage-outpost   # pod becomes 1/1 Running
kwokctl delete cluster --name dev
```

A fully functional end-to-end run (the outpost tunneling via Tailscale to the SubImage backend)
additionally requires SubImage-issued credentials and the SubImage backend, which live outside this
repository.

## License

Apache License 2.0 - see [LICENSE](./LICENSE) for details.
