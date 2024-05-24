project_id = "my-gcp-project"
gcp_project_services = [
  "script.googleapis.com",
  "iamcredentials.googleapis.com",
  "iam.googleapis.com", # Will be auto-enabled when activating iamcredentials.googleapis.com, however let's specify it anyway
]
github_repository = "my-org/my-gh-repository"
