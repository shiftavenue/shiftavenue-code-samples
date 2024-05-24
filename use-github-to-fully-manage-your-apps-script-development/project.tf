/*
 * Baseline project setup
 */

# Project can also be created via Terraform, in this example it has been created already
data "google_project" "main" {
  project_id = var.project_id
}

# All enabled GCP APIs
resource "google_project_service" "main" {
  for_each = var.gcp_project_services
  project  = var.project_id
  service  = each.value

  disable_dependent_services = true
}
