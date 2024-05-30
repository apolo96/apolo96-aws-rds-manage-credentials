resource "aws_secretsmanager_secret" "lambda_db_username" {
  name        = var.secret_name_db_user
  description = "DB username to create other users in DB"
}

resource "aws_secretsmanager_secret" "lambda_db_userpassword" {
  name        = var.secret_name_db_password
  description = "DB user password to create other users in DB"
}

