/*
 * Workload Identity setup used for authenticating in GitHub Actions workflows
 */

module "gh_oidc" {
  source      = "terraform-google-modules/github-actions-runners/google//modules/gh-oidc"
  version     = "3.1.2"
  project_id  = data.google_project.main.number
  pool_id     = "gh-actions-wif-pool"
  provider_id = "github"
  sa_mapping = {
    "apps-script-auto" = {
      sa_name   = "projects/${var.project_id}/serviceAccounts/${google_service_account.main.email}"
      attribute = "attribute.repository/${var.github_repository}"
    }
  }
}
