resource "google_project_service" "main" {
  for_each                   = var.project_services
  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = true
}

module "infra" {
  source     = "./infra"
  project_id = var.project_id

  depends_on = [google_project_service.main]
}
