# Remote state lives in a Cloud Storage bucket. The bucket name and the
# per-environment prefix are passed at init time, so the same code serves
# every environment:
#
#   terraform init \
#     -backend-config="bucket=<state bucket>" \
#     -backend-config="prefix=gke-cloudsql/<environment>"
terraform {
  backend "gcs" {}
}
