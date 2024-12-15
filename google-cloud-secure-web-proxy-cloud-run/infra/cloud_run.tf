resource "google_cloud_run_v2_service" "main" {
  project             = var.project_id
  name                = "run-svc"
  location            = "europe-west3"
  deletion_protection = false

  template {
    containers {
      image = "nginx:alpine"
      name  = "main-nginx-srv"
      ports {
        container_port = "80"
      }
    }
    containers {
      image   = "alpine/curl:latest"
      name    = "sidecar-curler"
      command = ["/bin/sh", "-c", "while true; do sleep 10; curl -v https://www.oktoberfest.de; done"]
    }
    vpc_access {
      network_interfaces {
        network    = module.vpc_spoke.network_name
        subnetwork = module.vpc_spoke.subnets["europe-west3/sub-cloudrun-ew3"].name
        tags       = ["proxy-routed"]
      }
      egress = "ALL_TRAFFIC"
    }
  }
}
