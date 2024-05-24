variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "gcp_project_services" {
  description = "The services/APIs enabled in the GCP project"
  type        = set(string)
}

variable "github_repository" {
  description = "The GitHub repository containing the Apps Script code"
  type        = string
}
