variable "project_id" {
  description = "Google Cloud project that holds the resources of this environment."
  type        = string
}

variable "region" {
  description = "Region for the network, the cluster, the database and the image repository."
  type        = string
  default     = "europe-west3"
}

variable "environment" {
  description = "Deployment environment. It is part of every resource name."
  type        = string

  validation {
    condition     = contains(["development", "production"], var.environment)
    error_message = "environment must be development or production."
  }
}

variable "name_prefix" {
  description = "Short prefix for resource names. Lowercase letters and digits, 2 to 8 characters."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,7}$", var.name_prefix))
    error_message = "name_prefix must start with a letter and have 2 to 8 lowercase letters or digits."
  }
}

variable "subnet_cidr" {
  description = "Primary range of the subnet. Cluster nodes get their addresses here."
  type        = string
  default     = "10.0.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary range for Kubernetes pods."
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "Secondary range for Kubernetes services."
  type        = string
  default     = "10.2.0.0/20"
}

variable "regional_cluster" {
  description = "Create a regional cluster (control plane and nodes in three zones) instead of a zonal one."
  type        = bool
  default     = false
}

variable "node_machine_type" {
  description = "Machine type of the cluster nodes."
  type        = string
  default     = "e2-medium"
}

variable "node_min_count" {
  description = "Minimum nodes per zone. A regional cluster runs this many nodes in each of its three zones."
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Maximum nodes per zone for the autoscaler."
  type        = number
  default     = 2
}

variable "sql_tier" {
  description = "Machine tier of the Cloud SQL instance. High availability needs a dedicated-core tier such as db-custom-1-3840."
  type        = string
  default     = "db-f1-micro"
}

variable "sql_availability_type" {
  description = "ZONAL for one instance, REGIONAL for a standby in a second zone."
  type        = string
  default     = "ZONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.sql_availability_type)
    error_message = "sql_availability_type must be ZONAL or REGIONAL."
  }
}

variable "database_name" {
  description = "Name of the database created on the Cloud SQL instance."
  type        = string
  default     = "app"
}

variable "deletion_protection" {
  description = "Protect the cluster and the database instance from deletion."
  type        = bool
  default     = true
}

variable "master_authorized_cidrs" {
  description = "Networks allowed to reach the cluster API endpoint. An empty list leaves the endpoint open to any address."
  type = list(object({
    name = string
    cidr = string
  }))
  default = []
}
