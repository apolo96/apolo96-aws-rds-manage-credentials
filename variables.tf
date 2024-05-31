variable "db_master_user" {
  description = "AWS RDS Master Username"
  type        = string
  sensitive   = true
}

variable "db_admin_user" {
  description = "AWS RDS Admin Username"
  type        = string
  sensitive   = true
}

variable "secret_key_db_admin_credentials" {
  description = "Secret name for admin credentials"
  type        = string
  default     = "/db/admin/credentials"
}

variable "db_app_user" {
  description = "AWS RDS App Username"
  type        = string
  sensitive   = true
}

variable "secret_key_db_app_credentials" {
  description = "Secret name for app credentials"
  type        = string
  default     = "/db/app/credentials"
}

variable "db_name" {
  description = "database name"
  type        = string
  default     = "ares"
}

variable "organization" {
  description = "Org Name"
  type        = string
  default     = "umbrella"
}

variable "environment" {
  description = "Environment Name"
  type        = string
  default     = "lab"
}