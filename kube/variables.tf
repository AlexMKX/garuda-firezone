variable "namespace" {
  description = "Existing Kubernetes namespace, sourced from module.garuda_k8s.namespace."
  type        = string
}

variable "name" {
  description = "Deployment name, default 'firezone'."
  type        = string
  default     = "firezone"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid DNS-1123 label."
  }
}

variable "firezone_dir" {
  description = <<EOT
Host path that backs Firezone runtime state on the hub node. Mounted via
`hostPath` with `type: DirectoryOrCreate`. Must be an absolute path. The
data disk attached to the hub VM is expected to be mounted here so the
state survives VM replacement.
EOT
  type        = string

  validation {
    condition     = can(regex("^/", var.firezone_dir))
    error_message = "firezone_dir must be an absolute path."
  }
}

variable "firezone_image" {
  description = "Image reference for the firezone Phoenix application container."
  type        = string
}

variable "postgres_image" {
  description = "Image reference for the postgres container. Defaults to upstream postgres:15."
  type        = string
  default     = "postgres:15"
}

variable "conntrack_log_image" {
  description = "Image reference for the conntrack-log sidecar container."
  type        = string
}

variable "frr_image" {
  description = "Image reference for the frr-sidecar container. Required when ospf != null; ignored otherwise."
  type        = string
  default     = ""
}

variable "server_fqdn" {
  description = <<EOT
External FQDN used for both the Firezone EXTERNAL_URL and the Traefik
IngressRoute host match. The chart renders `https://<server_fqdn>` as
EXTERNAL_URL and registers a cert-manager Certificate that writes its
result to the `firezone-tls` secret consumed by the IngressRoute.
EOT
  type        = string

  validation {
    condition     = length(var.server_fqdn) > 0
    error_message = "server_fqdn must be a non-empty FQDN."
  }
}

variable "admin_email" {
  description = "Initial admin email for first boot (DEFAULT_ADMIN_EMAIL)."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.admin_email))
    error_message = "admin_email must be a valid email-like string."
  }
}

variable "admin_password" {
  description = "Initial admin password (DEFAULT_ADMIN_PASSWORD)."
  type        = string
  sensitive   = true
}

variable "encryption_secrets" {
  description = <<-EOT
Optional override for firezone encryption keys. Each field is
base64-encoded random bytes; if null, generated via random_bytes and
persisted in terraform state. Provide via tfvars when restoring a
database whose rows were encrypted with prior keys.

Typical recovery flow:
    kubectl get secret <name>-env -n <ns> -o json \
      | jq '.data | map_values(@base64d)'
Place the resulting map under `encryption_secrets:` in
secrets.sops.yaml of the consuming stand.
EOT
  type = object({
    guardianSecretKey     = optional(string)
    secretKeyBase         = optional(string)
    liveViewSigningSalt   = optional(string)
    cookieSigningSalt     = optional(string)
    cookieEncryptionSalt  = optional(string)
    databaseEncryptionKey = optional(string)
    databasePassword      = optional(string)
  })
  default   = {}
  sensitive = true
}

variable "client_subnet" {
  description = "CIDR allocated to Firezone WireGuard clients (WIREGUARD_IPV4_NETWORK)."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.client_subnet))
    error_message = "client_subnet must be a valid IPv4 CIDR."
  }
}

variable "wg_listen_port" {
  description = "UDP port the Firezone WireGuard server listens on. Exposed via hostPort on the node."
  type        = number
  default     = 51620

  validation {
    condition     = var.wg_listen_port > 0 && var.wg_listen_port < 65536
    error_message = "wg_listen_port must be a valid UDP port."
  }
}

variable "wireguard_ipv4_masquerade" {
  description = "Whether Firezone should SNAT IPv4 client traffic. Garuda keeps this false so border routing owns masquerade."
  type        = bool
  default     = false
}

variable "wireguard_ipv6_masquerade" {
  description = "Whether Firezone should SNAT IPv6 client traffic. Mirrors the legacy Firezone role contract."
  type        = bool
  default     = false
}

variable "tls_cluster_issuer" {
  description = <<EOT
Name of the cert-manager `ClusterIssuer` resource used to provision the
Firezone TLS certificate. Typically the output of `module.cert_manager`.
EOT
  type        = string

  validation {
    condition     = length(var.tls_cluster_issuer) > 0
    error_message = "tls_cluster_issuer must be a non-empty ClusterIssuer name."
  }
}

variable "nic_attach" {
  description = "Secondary networks the pod attaches to via Multus. Becomes the k8s.v1.cni.cncf.io/networks annotation."
  type        = list(string)
  default     = ["backbone", "border"]
}

variable "labels" {
  description = "Extra metadata labels merged into the pod and deployment labels."
  type        = map(string)
  default     = {}
}

variable "ospf" {
  description = <<EOT
Structured OSPF intent. When null, no FRR sidecar is rendered. Interfaces
typically include the Firezone-managed `wg-firezone` kernel interface that
is created from inside the pod netns by the firezone server itself.
EOT
  type = object({
    router_id          = string
    interfaces         = list(string)
    passive_interfaces = optional(list(string), [])
    default_originate  = optional(bool, false)
    redistribute       = optional(list(string), [])
    transit_provider   = optional(bool, false)
  })
  default = null

  validation {
    condition     = var.ospf == null || can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", var.ospf.router_id))
    error_message = "ospf.router_id must be an IPv4-formatted string."
  }

  validation {
    condition     = var.ospf == null || length(var.ospf.interfaces) > 0
    error_message = "ospf.interfaces must be non-empty when ospf is set."
  }

  validation {
    condition = (
      var.ospf == null
      || alltrue([for r in var.ospf.redistribute : contains(["connected", "kernel", "static"], r)])
    )
    error_message = "ospf.redistribute values must be subset of ['connected', 'kernel', 'static']."
  }
}

variable "transit" {
  description = <<EOT
Transit-watcher inputs for the bundled FRR sidecar. When `interfaces`
is non-empty, the chart exports PBR_TRANSIT_TAG and PBR_TRANSIT_INTERFACES,
which the sidecar entrypoint uses to start transit_watcher.py — same wiring
as the docker-compose era frr_injector consumer
(roles/backbone_network/files/ospf_injector/frr_injector/consumer.py:221-223).
The OSPF tag is hardcoded to TRANSIT_TAG=201 in the chart helper to match
frr_injector/config.py without exposing extra surface here.
EOT
  type = object({
    interfaces = list(string)
  })
  default = {
    interfaces = []
  }
}
