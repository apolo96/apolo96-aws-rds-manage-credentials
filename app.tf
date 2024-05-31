#### Lambda
resource "aws_iam_role" "app" {
  name               = "AssumeLambdaRoleapp"
  description        = "Role for lambda to assume lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda_role.json
}

resource "aws_iam_role_policy_attachment" "app_lambda_vpc" {
  role       = aws_iam_role.app.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "app_lambda_basic" {
  role       = aws_iam_role.app.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "app_lambda_secrets_manager" {
  name        = "SecretsManagerPolicyAppLambda"
  description = "Policy to allow Lambda to manage secrets in Secrets Manager"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:ListSecrets"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_lambda_secrets_manager" {
  role       = aws_iam_role.app.id
  policy_arn = aws_iam_policy.app_lambda_secrets_manager.arn
}

resource "null_resource" "app_function_binary" {
  triggers = {
    source_code = filesha256("${local.app_src_path}/main.go")
  }
  provisioner "local-exec" {
    command = "GOOS=linux GOARCH=amd64 CGO_ENABLED=0 GOFLAGS=-trimpath go build -C ${local.app_src_path} -mod=readonly -ldflags='-s -w' -o ./bin/${local.binary_name}"
  }
}

data "archive_file" "app_function_archive" {  
  type        = "zip"
  source_file = local.app_binary_path
  output_path = local.app_archive_path
  depends_on  = [null_resource.app_function_binary]
}

resource "aws_lambda_function" "app_dragon" {
  function_name = "app-dragon"
  description   = "Create Data in RDS DB"
  role          = aws_iam_role.app.arn
  handler       = local.binary_name
  memory_size   = 128

  filename         = local.app_archive_path
  source_code_hash = data.archive_file.app_function_archive.output_base64sha256

  runtime = "provided.al2023"

  vpc_config {
    subnet_ids         = ["subnet-2d8fa960"]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      DB_APP_SECRET_KEY = var.secret_key_db_app_credentials
      DB_HOST           = aws_db_instance.dragon.endpoint
      DB_NAME           = var.db_name
    }
  }
}

resource "aws_cloudwatch_log_group" "app_lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.app_dragon.function_name}"
  retention_in_days = 3
}