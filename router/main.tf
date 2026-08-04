resource "opnsense_caddy_settings" "main" {
  enabled       = true
  http_port     = 80
  https_port    = 443
  acme_email    = var.acme_email
  run_as_user   = "root"
  http_versions = ["h1", "h2"]
  log_level     = var.caddy_log_level
}

module "edge_ingress" {
  source = "../modules/caddy-edge-ingress"

  interface          = var.ingress_interface
  destination        = var.ingress_destination
  source_network     = var.ingress_source_network
  http_port          = 80
  https_port         = 443
  sequence_base      = var.ingress_sequence_base
  log                = var.log_ingress
  description_prefix = "Caddy edge ingress"

  depends_on = [opnsense_caddy_settings.main]
}
