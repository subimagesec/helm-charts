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
  --set outpost.authKey="tskey-client-xxxxx-xxxxxxxxxxxxxx"
```

See the [subimage-outpost README](./charts/subimage-outpost/README.md) for detailed configuration options.

## License

Apache License 2.0 - see [LICENSE](./LICENSE) for details.
