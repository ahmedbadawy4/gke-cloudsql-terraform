# GKE and Cloud SQL on Google Cloud with Terraform and Argo CD

A reference setup that runs a small TypeScript service on Google Kubernetes Engine (GKE) with a private connection to Cloud SQL for PostgreSQL. It has two environments, `development` and `production`.

- Terraform builds the network, the cluster, the database and the image registry.
- GitHub Actions checks the code, builds the image and pushes it to Artifact Registry.
- Argo CD pulls the Kubernetes manifests from this repository and keeps the cluster in sync.

This repository is a reference setup. It shows the structure and the decisions. It is not a ready production platform, and the [design limits](#design-limits) below say what is left out on purpose.

The Terraform code was first written with the Cloud Development Kit for Terraform (CDKTF). HashiCorp sunset CDKTF on 10 December 2025, so the code is now plain Terraform (HCL), which is the migration path HashiCorp documents.

## What Terraform creates

- A custom VPC network with one subnet. The subnet has secondary ranges for pods and services, and flow logs are on.
- Private services access (a VPC peering) so Cloud SQL gets a private address.
- Firewall rules: traffic inside the network, and SSH to nodes only from the Identity-Aware Proxy range.
- A GKE cluster, zonal in development and regional in production:
  - VPC-native, release channel `REGULAR`, Calico network policy enabled.
  - A separate autoscaling node pool with shielded nodes. The default node pool is removed.
  - A custom node service account with only the roles the nodes need, plus read access to the image repository.
  - Optional `master_authorized_cidrs` to limit who can reach the Kubernetes API.
- Cloud SQL for PostgreSQL 16:
  - Private IP only, no public address.
  - TLS with a client certificate required.
  - Backups with point-in-time recovery, and a fixed list of logging flags.
  - Deletion protection, off in development and on in production.
- An Artifact Registry Docker repository named `images`.

## Repository layout

```text
.
├── application/          Express service in TypeScript
├── Dockerfile            Multi-stage build, Node 24, runs as the node user
├── kubernetes/
│   ├── base/             Deployment, Service and NetworkPolicy
│   ├── overlays/         development and production (namespace, replicas, image tag)
│   └── tools/            sql-test-pod.yaml, applied by hand only
├── argocd/               One Argo CD Application per environment
├── terraform/            Network, GKE, Cloud SQL, IAM and Artifact Registry
│   └── environments/     development.tfvars and production.tfvars
└── .github/workflows/    ci.yaml, terraform-deploy.yaml, app-publish.yaml
```

## Environments and branches

| Environment | Git branch | Kubernetes namespace | Terraform state prefix |
| --- | --- | --- | --- |
| development | `dev` | `development` | `gke-cloudsql/development` |
| production | `main` | `production` | `gke-cloudsql/production` |

The setup assumes one Google Cloud project per environment. Repeat the one-time steps below in each project. The Argo CD application of an environment follows its branch, so a change on `dev` reaches development first and reaches production after you merge it into `main`.

## One-time setup per project

The commands use these shell variables. Set them for the project you are preparing.

```bash
export PROJECT_ID=<google-cloud-project-id>
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
export REGION=europe-west3
export STATE_BUCKET=<globally-unique-bucket-name>
export REPO=ahmedbadawy4/gke-cloudsql-terraform   # owner/name of this repository on GitHub
```

1. Enable the APIs that Terraform and the pipelines use:

   ```bash
   gcloud services enable --project "$PROJECT_ID" \
     compute.googleapis.com container.googleapis.com sqladmin.googleapis.com \
     servicenetworking.googleapis.com iam.googleapis.com iamcredentials.googleapis.com \
     sts.googleapis.com cloudresourcemanager.googleapis.com artifactregistry.googleapis.com
   ```

2. Create the bucket that holds the Terraform state, with versioning on:

   ```bash
   gcloud storage buckets create "gs://$STATE_BUCKET" --project "$PROJECT_ID" \
     --location "$REGION" --uniform-bucket-level-access
   gcloud storage buckets update "gs://$STATE_BUCKET" --versioning
   ```

3. Create the service account that Terraform runs as, and give it its roles:

   ```bash
   gcloud iam service-accounts create terraform-deployer --project "$PROJECT_ID"
   export TF_SA="terraform-deployer@$PROJECT_ID.iam.gserviceaccount.com"

   for role in compute.networkAdmin compute.securityAdmin container.admin cloudsql.admin \
     iam.serviceAccountAdmin iam.serviceAccountUser resourcemanager.projectIamAdmin \
     servicenetworking.networksAdmin artifactregistry.admin; do
     gcloud projects add-iam-policy-binding "$PROJECT_ID" \
       --member "serviceAccount:$TF_SA" --role "roles/$role" --condition=None
   done

   gcloud storage buckets add-iam-policy-binding "gs://$STATE_BUCKET" \
     --member "serviceAccount:$TF_SA" --role roles/storage.objectAdmin
   ```

4. Create the service account that publishes images. Its only role is writing to the image repository, which Terraform creates, so grant it after the first Terraform apply (see [Deploy the infrastructure](#deploy-the-infrastructure)):

   ```bash
   gcloud iam service-accounts create image-publisher --project "$PROJECT_ID"
   export PUBLISH_SA="image-publisher@$PROJECT_ID.iam.gserviceaccount.com"
   ```

5. Let GitHub Actions sign in without a key file, with Workload Identity Federation. The condition limits the provider to this repository:

   ```bash
   gcloud iam workload-identity-pools create github --project "$PROJECT_ID" \
     --location global --display-name "GitHub Actions"

   gcloud iam workload-identity-pools providers create-oidc github --project "$PROJECT_ID" \
     --location global --workload-identity-pool github \
     --issuer-uri "https://token.actions.githubusercontent.com" \
     --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository" \
     --attribute-condition "assertion.repository == '$REPO'"

   for sa in "$TF_SA" "$PUBLISH_SA"; do
     gcloud iam service-accounts add-iam-policy-binding "$sa" --project "$PROJECT_ID" \
       --role roles/iam.workloadIdentityUser \
       --member "principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github/attribute.repository/$REPO"
   done
   ```

6. In the GitHub repository, create the Environments `development` and `production` (Settings, Environments). Add these variables to each one, with the values of its own project. For `production`, add required reviewers so a person approves every run.

   | Variable | Value |
   | --- | --- |
   | `GCP_PROJECT_ID` | The project ID |
   | `GCP_REGION` | The region, `europe-west3` by default |
   | `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github/providers/github` |
   | `TF_SERVICE_ACCOUNT` | The value of `$TF_SA` |
   | `PUBLISH_SERVICE_ACCOUNT` | The value of `$PUBLISH_SA` |
   | `TF_STATE_BUCKET` | The state bucket name |

   The region default is set in `terraform/variables.tf` and in the two `.tfvars` files. If you change it, change `GCP_REGION` and the registry host in `kubernetes/overlays/*/kustomization.yaml` to match.

## Deploy the infrastructure

Run the workflow `Terraform deploy` from the Actions tab. Choose the environment and leave `apply` off to see the plan. Run it again with `apply` on to create the resources.

To run Terraform from your own machine instead:

```bash
cd terraform
terraform init \
  -backend-config="bucket=$STATE_BUCKET" \
  -backend-config="prefix=gke-cloudsql/development"
terraform plan -var-file=environments/development.tfvars -var="project_id=$PROJECT_ID"
terraform apply -var-file=environments/development.tfvars -var="project_id=$PROJECT_ID"
```

After the first `init`, commit the generated `terraform/.terraform.lock.hcl` so every run uses the same provider versions.

When the apply has finished, allow the publisher to push images:

```bash
gcloud artifacts repositories add-iam-policy-binding images \
  --project "$PROJECT_ID" --location "$REGION" \
  --member "serviceAccount:$PUBLISH_SA" --role roles/artifactregistry.writer
```

## Install Argo CD and the application

Connect to the cluster. The name and location come from the Terraform outputs:

```bash
gcloud container clusters get-credentials "$(terraform -chdir=terraform output -raw cluster_name)" \
  --project "$PROJECT_ID" --location "$(terraform -chdir=terraform output -raw cluster_location)"
```

Install Argo CD, then create the Application of the environment:

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.6.2/manifests/install.yaml
kubectl apply -f argocd/development.yaml     # or argocd/production.yaml
```

The Application reads this repository over HTTPS, so the repository must be public or Argo CD must have credentials for it.

## Publish an image

The workflow `Publish image` runs on every push to `dev` or `main` that changes `application/` or the `Dockerfile`. It can also be started by hand. It does these steps:

1. Picks the environment from the branch (`dev` is development, `main` is production). If the variables from [One-time setup per project](#one-time-setup-per-project) are not set in that environment, the run ends with a notice and publishes nothing.
2. Signs in to Google Cloud with Workload Identity Federation.
3. Builds the image and pushes it to Artifact Registry, tagged with the commit SHA.
4. Writes the new image name and tag into `kubernetes/overlays/<environment>/kustomization.yaml` and commits that change to the same branch.

Argo CD sees the commit and rolls out the new image. The overlay starts with the tag `unset`, so the first sync waits for the first published image.

The commit in step 4 changes only the overlay file, which is not in the workflow's path filter, so it does not start another publish run.

## Connect to Cloud SQL

Cloud SQL has no public address and requires a client certificate. To check that the cluster can reach it, use the throwaway pod:

```bash
kubectl apply -f kubernetes/tools/sql-test-pod.yaml
kubectl exec sql-test-pod -- pg_isready -h "$(terraform -chdir=terraform output -raw sql_private_ip)"
kubectl delete -f kubernetes/tools/sql-test-pod.yaml
```

`pg_isready` shows that the server is reachable. To run queries, connect through the Cloud SQL Auth Proxy (the connection name is the output `sql_connection_name`) or with a client certificate.

## Run the application locally

You need Node.js 24. Details are in [application/README.md](application/README.md).

```bash
cd application
npm ci
npm run start:dev
```

To build the image:

```bash
docker build --tag app .
docker run --rm -p 3000:3000 app
```

## Checks

Pull requests and pushes to `dev` and `main` run `ci.yaml`:

| Job | What it does |
| --- | --- |
| Pre-commit | Runs the hooks in `.pre-commit-config.yaml`: whitespace, YAML and JSON syntax, private-key detection, Hadolint and `terraform fmt`. |
| Application and image | `npm ci`, `npm run build` and `docker build`. |
| Terraform | `terraform fmt -check`, `init -backend=false` and `validate`, plus a Checkov scan that reports findings without failing the job. |
| Kubernetes manifests | Renders both overlays with Kustomize and validates them, and the Argo CD applications, with kubeconform. |

To run the hooks on your machine:

```bash
pip install pre-commit
pre-commit install
pre-commit run --all-files
```

## Design limits

These are choices a reference setup makes. A production platform would change them.

- **Database access:** Pods reach Cloud SQL through the node service account, which has `roles/cloudsql.client`. The next step is Workload Identity, so each workload gets its own identity. The cluster does not enable it yet.
- **Nodes:** Nodes have public IP addresses. The next step is a private cluster with Cloud NAT.
- **API endpoint:** With the default empty `master_authorized_cidrs`, the Kubernetes API endpoint accepts connections from any address. Set the list to your own ranges.
- **Database contents:** Terraform creates the instance and one database. Database users and passwords are created separately.
- **Audit logging:** Cloud SQL for PostgreSQL does not accept the pgaudit flags, so only the logging flags in `terraform/sql.tf` are set.
- **Public service:** The Kubernetes Service is a public load balancer on port 80.
- **Promotion:** Each environment builds its own image from its own branch. There is no step that promotes the same image from development to production.
- **Application:** The service does not use the database. It exists to show the deployment path.
- **Image bump commit:** The publish workflow pushes a commit to the branch. A protected `main` branch needs a pull request flow or an exception for the workflow.
- **Cloud SQL names:** Google keeps the name of a deleted Cloud SQL instance reserved for about a week. Recreating an environment right after destroying it needs a different `name_prefix`.
- **Node counts:** `node_min_count` and `node_max_count` apply per zone, so the regional production cluster runs up to three times that number of nodes.

## License

MIT. See [LICENSE](LICENSE).
