locals {
  # The service user used for creating the Apps Script project
  # Will be impersonated in GitHub Actions workflows for script deployment
  service_user_name = "apps-script-auto-user"

  # The GCP service account used for Workload Identity Federation, make sure to configure domain-wide delegation for this account
  service_account_name = "apps-script-auto"
}

# Service Account used for automation scripts
resource "google_service_account" "main" {
  account_id   = local.service_account_name
  display_name = "Service account to be used to interact with Apps Script REST API"
}

# OAuth Config Editor role for service user automation account to be able to use GCP project as Apps Script backend project
resource "google_project_iam_member" "oauth_config_editor" {
  project = var.project_id
  role    = "roles/oauthconfig.editor"
  member  = "user:${local.service_user_name}@my-company.com"
}

# Service Account Token creator role needed for external identity (the GitHub repository)
# so that the impersonation in GitHub Actions workflows work
resource "google_service_account_iam_binding" "token_creator" {
  service_account_id = google_service_account.main.name
  role               = "roles/iam.serviceAccountTokenCreator"
  members = [
    "principalSet://iam.googleapis.com/${module.gh_oidc.pool_name}/attribute.repository/${var.github_repository}"
  ]
}
