project_id = "<my-gcp-project>" # Insert your project ID here

project_services = [
  "compute.googleapis.com",
  "iam.googleapis.com",
  "monitoring.googleapis.com",
  "logging.googleapis.com",
  "networksecurity.googleapis.com", # Necessary to create Secure Web Proxy
  "networkservices.googleapis.com", # Necessary to create Secure Web Proxy
  "run.googleapis.com",
]
