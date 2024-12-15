variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "project_services" {
  description = "GCP project enabled services"
  type        = set(string)
}
