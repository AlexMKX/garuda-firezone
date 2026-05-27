mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  namespace           = "garuda"
  name                = "firezone"
  firezone_dir        = "/opt/garuda/firezone"
  firezone_image      = "ghcr.io/firezone/firezone:latest"
  conntrack_log_image = "local/conntrack-log:latest"
  server_fqdn         = "hub.example.net"
  admin_email         = "admin@example.net"
  admin_password      = "fixture-password"
  client_subnet       = "198.51.100.128/25"
  tls_cluster_issuer  = "letsencrypt-prod"
  encryption_secrets = {
    guardianSecretKey     = "fixture-guardian"
    secretKeyBase         = "fixture-secret-key-base"
    liveViewSigningSalt   = "fixture-live-view"
    cookieSigningSalt     = "fixture-sign"
    cookieEncryptionSalt  = "fixture-encrypt"
    databaseEncryptionKey = "fixture-database-encryption"
    databasePassword      = "fixture-database-password"
  }
}

run "chart_path_resolves_to_bundled_chart" {
  command = plan

  assert {
    condition     = endswith(helm_release.firezone.chart, "/charts/firezone")
    error_message = "helm_release.firezone.chart must point at $${path.module}/charts/firezone"
  }
}

# OpenTofu's yamlencode emits quoted block-style YAML ("key": "value"),
# so substrings below match that form. See modules/garuda_k8s/tests for
# the precedent.
run "values_include_firezone_dir_and_server_fqdn" {
  command = plan

  assert {
    condition     = strcontains(helm_release.firezone.values[0], "\"firezoneDir\": \"/opt/garuda/firezone\"")
    error_message = "rendered values must include firezoneDir"
  }

  assert {
    condition     = strcontains(helm_release.firezone.values[0], "\"serverFqdn\": \"hub.example.net\"")
    error_message = "rendered values must include serverFqdn"
  }
}

run "values_include_tls_cluster_issuer_and_wg_port" {
  command = plan

  assert {
    condition     = strcontains(helm_release.firezone.values[0], "\"tlsClusterIssuer\": \"letsencrypt-prod\"")
    error_message = "rendered values must include tlsClusterIssuer"
  }

  assert {
    condition     = strcontains(helm_release.firezone.values[0], "\"wgListenPort\": 51620")
    error_message = "rendered values must include wgListenPort default 51620"
  }
}

run "values_include_admin_email_and_client_subnet" {
  command = plan

  assert {
    condition     = strcontains(helm_release.firezone.values[0], "\"adminEmail\": \"admin@example.net\"")
    error_message = "rendered values must include adminEmail"
  }

  assert {
    condition     = strcontains(helm_release.firezone.values[0], "\"clientSubnet\": \"198.51.100.128/25\"")
    error_message = "rendered values must include clientSubnet"
  }
}

run "values_include_conntrack_log_image" {
  command = plan

  assert {
    condition     = strcontains(helm_release.firezone.values[0], "\"conntrackLog\": \"local/conntrack-log:latest\"")
    error_message = "rendered values must include images.conntrackLog"
  }

  assert {
    condition     = strcontains(helm_release.firezone.values[0], "\"postgres\": \"postgres:15\"")
    error_message = "rendered values must include default postgres image"
  }
}

run "values_include_firezone_secret_contract" {
  command = plan

  assert {
    condition     = strcontains(helm_release.firezone.values[0], "\"wireguardIpv4Address\": \"198.51.100.129\"")
    error_message = "rendered values must include WIREGUARD_IPV4_ADDRESS as the first client subnet host"
  }

  assert {
    condition     = strcontains(helm_release.firezone.values[0], "\"wireguardIpv4Masquerade\": false")
    error_message = "rendered values must disable Firezone built-in IPv4 masquerade by default"
  }

  assert {
    condition     = strcontains(helm_release.firezone.values[0], "\"guardianSecretKey\":")
    error_message = "rendered values must include GUARDIAN_SECRET_KEY material"
  }
}

run "default_ospf_is_null" {
  command = plan

  assert {
    condition     = strcontains(helm_release.firezone.values[0], "\"ospf\": null")
    error_message = "with default var.ospf=null, rendered values must contain 'ospf: null'"
  }
}

run "ospf_set_propagates_router_id_and_interfaces" {
  command = plan

  variables {
    ospf = {
      router_id  = "198.51.100.22"
      interfaces = ["wg-firezone"]
    }
  }

  assert {
    condition     = strcontains(helm_release.firezone.values[0], "\"router_id\": \"198.51.100.22\"")
    error_message = "rendered values must contain ospf.router_id"
  }

  assert {
    condition     = strcontains(helm_release.firezone.values[0], "- \"wg-firezone\"")
    error_message = "rendered values must contain ospf.interfaces entry"
  }
}

run "nic_attach_default_is_backbone_and_border" {
  command = plan

  assert {
    condition     = strcontains(helm_release.firezone.values[0], "- \"backbone\"")
    error_message = "default nic_attach must include backbone"
  }

  assert {
    condition     = strcontains(helm_release.firezone.values[0], "- \"border\"")
    error_message = "default nic_attach must include border"
  }
}

run "outputs_match_inputs" {
  command = plan

  assert {
    condition     = output.deployment_name == "firezone"
    error_message = "output.deployment_name must equal var.name"
  }

  assert {
    condition     = output.service_url == "https://hub.example.net"
    error_message = "output.service_url must be https://${var.server_fqdn}"
  }
}

run "reject_relative_firezone_dir" {
  command = plan

  variables {
    firezone_dir = "relative/path"
  }

  expect_failures = [var.firezone_dir]
}

run "reject_invalid_admin_email" {
  command = plan

  variables {
    admin_email = "not-an-email"
  }

  expect_failures = [var.admin_email]
}

run "reject_invalid_client_subnet" {
  command = plan

  variables {
    client_subnet = "not-a-cidr"
  }

  expect_failures = [var.client_subnet]
}

run "reject_empty_tls_cluster_issuer" {
  command = plan

  variables {
    tls_cluster_issuer = ""
  }

  expect_failures = [var.tls_cluster_issuer]
}

run "reject_invalid_ospf_router_id" {
  command = plan

  variables {
    ospf = {
      router_id  = "not-an-ip"
      interfaces = ["wg-firezone"]
    }
  }

  expect_failures = [var.ospf]
}
