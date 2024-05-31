resource "aws_secretsmanager_secret" "db_app_credentials" {
  name        = var.secret_key_db_app_credentials
  description = "database app credentials"
}

resource "aws_secretsmanager_secret_version" "db_app_credentials" {
  secret_id = aws_secretsmanager_secret.db_app_credentials.id

  secret_string = jsonencode({
    username = var.db_app_user
    password = random_password.app_password.result
  })
}

resource "random_password" "app_password" {
  length  = 16
  special = true
}

resource "aws_secretsmanager_secret" "db_admin_credentials" {
  name        = var.secret_key_db_admin_credentials
  description = "database admin credentials"
}

resource "aws_secretsmanager_secret_version" "db_admin_credentials" {
  secret_id = aws_secretsmanager_secret.db_admin_credentials.id

  secret_string = jsonencode({
    username = var.db_admin_user
    password = random_password.admin_password.result
  })
}

resource "random_password" "admin_password" {
  length  = 16
  special = true
}
