module "vpc_egress" {
  source  = "terraform-google-modules/network/google"
  version = "~> 9.1"

  project_id   = var.project_id
  network_name = "net-central-egress"
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name           = "sub-swp"
      subnet_ip             = "10.1.0.0/24"
      subnet_region         = "europe-west3"
      subnet_private_access = false
    },
    {
      subnet_name   = "sub-swp-proxy-only"
      subnet_region = "europe-west3"
      subnet_ip     = "10.1.1.0/24"
      purpose       = "REGIONAL_MANAGED_PROXY"
      role          = "ACTIVE"
    },
  ]
}

module "vpc_spoke" {
  source  = "terraform-google-modules/network/google"
  version = "~> 9.1"

  project_id   = var.project_id
  network_name = "net-spoke"
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name           = "sub-cloudrun-ew3"
      subnet_ip             = "10.5.0.0/16"
      subnet_region         = "europe-west3"
      subnet_private_access = true
    },
  ]
}

# Peer both networks
resource "google_compute_network_peering" "spoke_to_egress" {
  name         = "spoke-to-egress"
  network      = module.vpc_spoke.network_self_link
  peer_network = module.vpc_egress.network_self_link
}

resource "google_compute_network_peering" "egress_to_spoke" {
  name         = "egress-to-spoke"
  network      = module.vpc_egress.network_self_link
  peer_network = module.vpc_spoke.network_self_link
}
