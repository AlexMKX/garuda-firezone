# firezone/kube

Deploys the Firezone application stack as one multi-container Kubernetes
Deployment with persistent state on a hostPath volume backed by the YC
data disk attached to the hub VM.

Admin UI is exposed via the k3s-bundled Traefik ingress through an
`IngressRoute` CRD, with TLS terminated by a cert-manager `Certificate`
that requests certs from the cluster issuer provided via
`tls_cluster_issuer` (typically Let's Encrypt with HTTP-01).

The Firezone-managed WireGuard endpoint is exposed as a `hostPort` on
UDP `var.wg_listen_port` (default 51620) on the hub node.

When `ospf` is set, an FRR sidecar runs in the same pod's network
namespace and speaks OSPF on the interfaces declared in `ospf.interfaces`
(typically `wg-firezone`, the kernel interface the Firezone server
creates inside the pod netns).

## Inputs

| Variable | Required | Description |
|---|---|---|
| `namespace` | yes | Existing namespace, typically `module.garuda_k8s_hub.namespace`. |
| `name` | no | Deployment name. Default `firezone`. |
| `firezone_dir` | yes | Absolute host path that backs Firezone runtime state via hostPath. |
| `firezone_image` | yes | Image reference for the firezone application container. |
| `postgres_image` | no | Default `postgres:15`. |
| `conntrack_log_image` | yes | Image for the conntrack-log sidecar. |
| `frr_image` | when `ospf != null` | Image for the optional frr-sidecar. |
| `server_fqdn` | yes | External FQDN; both `EXTERNAL_URL` and IngressRoute Host match. |
| `admin_email` | yes | Initial admin email (`DEFAULT_ADMIN_EMAIL`). |
| `admin_password` | yes (sensitive) | Initial admin password (`DEFAULT_ADMIN_PASSWORD`). |
| `client_subnet` | yes | CIDR for WireGuard clients (`WIREGUARD_IPV4_NETWORK`). |
| `wg_listen_port` | no | UDP port firezone WireGuard listens on. Default `51620`. |
| `tls_cluster_issuer` | yes | Name of cert-manager `ClusterIssuer` to issue the `firezone-tls` cert. |
| `nic_attach` | no | Default `["backbone", "border"]`. Becomes the Multus annotation. |
| `labels` | no | Extra metadata labels merged into pod/deployment labels. |
| `ospf` | no | Structured OSPF intent. When `null`, no FRR sidecar is rendered. |

### `ospf` object

| Field | Required | Description |
|---|---|---|
| `router_id` | yes | IPv4-formatted OSPF router-id. |
| `area` | no | Default `"0.0.0.0"`. |
| `interfaces` | yes | OSPF-participating interfaces. Typically `["wg-firezone"]`. |
| `passive_interfaces` | no | Marked `ip ospf passive`. |
| `default_originate` | no | Default `false`. |
| `redistribute` | no | Subset of `["connected", "kernel", "static"]`. |
| `extra_frr_conf` | no | Free-form FRR config appended verbatim. |

## Outputs

| Output | Description |
|---|---|
| `deployment_name` | Equals `var.name`. |
| `service_url` | `"https://${var.server_fqdn}"`. Consumed by `firezone_oidc`. |

## Providers

```hcl
module "firezone_kube" {
  source = "../../../modules/firezone/kube"

  providers = {
    helm       = helm.hub
    kubernetes = kubernetes.hub
  }

  namespace           = module.garuda_k8s_hub.namespace
  firezone_dir        = local.firezone_facts.directory
  firezone_image      = var.fz_firezone_image
  conntrack_log_image = var.fz_conntrack_log_image
  server_fqdn         = local.firezone_facts.server_name
  admin_email         = local.firezone_facts.default_admin_email
  admin_password      = local.firezone_facts.admin_password
  client_subnet       = local.firezone_facts.client_subnet
  tls_cluster_issuer  = module.cert_manager.cluster_issuer_name

  ospf = {
    router_id  = "198.51.100.22"
    interfaces = ["wg-firezone"]
  }
}
```

## What this module does NOT do

- It does not install cert-manager itself. See `modules/cert_manager` for
  the `ClusterIssuer` whose name is passed via `tls_cluster_issuer`.
- It does not run Caddy or any other ingress sidecar. TLS termination
  happens at the k3s-bundled Traefik ingress controller through the
  `IngressRoute` rendered by this chart.
- It does not run smtp4dev or autoheal. SMTP fan-out is not part of the
  k8s topology; pod liveness is owned by kubelet readiness/liveness
  probes.
- It does not provision the `firezone_oidc` REST API client. That stays
  in `modules/firezone/oidc`, which depends on this module by FQDN.
