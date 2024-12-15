resource "google_network_security_gateway_security_policy" "swp_pol" {
  project  = var.project_id
  name     = "swp-pol"
  location = "europe-west3"
}

resource "google_network_security_gateway_security_policy_rule" "swp_rule_allow" {
  project                 = var.project_id
  name                    = "swp-rule-allow-domains"
  location                = "europe-west3"
  gateway_security_policy = google_network_security_gateway_security_policy.swp_pol.name
  description             = "Allow oktoberfest.de and google.com"
  enabled                 = true
  priority                = 1
  session_matcher         = "host().contains('oktoberfest.de') || host().contains('google.com')"
  basic_profile           = "ALLOW"
}

resource "google_network_services_gateway" "swp" {
  name                                 = "swp-test"
  project                              = var.project_id
  location                             = "europe-west3"
  addresses                            = ["10.1.0.10"]                                              # Set IP at which the proxy is accessible
  type                                 = "SECURE_WEB_GATEWAY"                                       # SECURE_WEB_GATEWAY represents the Secure Web Proxy instance
  routing_mode                         = "NEXT_HOP_ROUTING_MODE"                                    # Configure as transparent proxy to use as next hop
  ports                                = [80, 443]                                                  # Allow HTTP(S) ports
  gateway_security_policy              = google_network_security_gateway_security_policy.swp_pol.id # Attach policy
  network                              = module.vpc_egress.network_id
  subnetwork                           = module.vpc_egress.subnets["europe-west3/sub-swp"].id
  scope                                = "custom-swp-scope1"
  delete_swg_autogen_router_on_destroy = true
}

# Set proxy as next hop for all traffic
resource "google_compute_route" "proxy_transparent" {
  project      = var.project_id
  name         = "swp-transparent-route"
  dest_range   = "0.0.0.0/0"
  network      = module.vpc_spoke.network_name
  next_hop_ilb = "10.1.0.10"
  priority     = 100
  tags         = ["proxy-routed"]
}
