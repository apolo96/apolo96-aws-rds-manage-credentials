variable "rds_dragon_username" {
  description = "AWS RDS Dragon Username"
  type        = string
}

variable "secret_name_db_user" {
  description = "AWS RDS Dragon Username"
  type        = string
  default     = "DRAGON_RDS_DB_USERNAME"
}

variable "secret_name_db_password" {
  description = "AWS RDS Dragon Username"
  type        = string
  default     = "DRAGON_RDS_DB_PASSWORD"
}

variable "rds_db_identifier" {
  description = "AWS RDS Identifier"
  type        = string
  default     = "dragon"
}