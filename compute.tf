#### Lambda
data "aws_iam_policy_document" "assume_lambda_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dragon" {
  name               = "AssumeLambdaRoleDragon"
  description        = "Role for lambda to assume lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda_role.json
}


resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.dragon.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.dragon.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_sqs" {
  name        = "SQSPolicy"
  description = "Policy to allow Lambda to pull events in SQS"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ],
        Effect   = "Allow",
        Resource = aws_sqs_queue.dragon_db_ops.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_sqs" {
  role       = aws_iam_role.dragon.id
  policy_arn = aws_iam_policy.lambda_sqs.arn
}

resource "aws_iam_policy" "lambda_secrets_manager" {
  name        = "SecretsManagerPolicy"
  description = "Policy to allow Lambda to manage secrets in Secrets Manager"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:ListSecrets"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_secrets_manager" {
  role       = aws_iam_role.dragon.id
  policy_arn = aws_iam_policy.lambda_secrets_manager.arn
}

resource "aws_security_group" "lambda_sg" {
  name   = "lambda-dragon-security-group"
  vpc_id = aws_default_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "lambda_ingress" {
  security_group_id = aws_security_group.lambda_sg.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "lambda_egress" {
  security_group_id = aws_security_group.lambda_sg.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "null_resource" "function_binary" {
  triggers = {
    source_code = filesha256("${local.src_path}/main.go")
  }
  provisioner "local-exec" {
    command = "GOOS=linux GOARCH=amd64 CGO_ENABLED=0 GOFLAGS=-trimpath go build -C ${local.src_path} -mod=readonly -ldflags='-s -w' -o ./bin/${local.binary_name}"
  }
}

data "archive_file" "function_archive" {
  depends_on  = [null_resource.function_binary]
  type        = "zip"
  source_file = local.binary_path
  output_path = local.archive_path
}

resource "aws_lambda_function" "dragon" {
  function_name = "rds-create-user"
  description   = "Create an user with auto-generate credentials"
  role          = aws_iam_role.dragon.arn
  handler       = local.binary_name
  memory_size   = 128

  filename         = local.archive_path
  source_code_hash = data.archive_file.function_archive.output_base64sha256

  runtime = "provided.al2023"

  vpc_config {
    subnet_ids         = ["subnet-2d8fa960"]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      AWS_ACCOUNT         = data.aws_caller_identity.current.account_id
      DB_ID               = aws_db_instance.dragon.identifier
      DB_ADMIN_SECRET_KEY = var.secret_key_db_admin_credentials
      DB_APP_SECRET_KEY   = var.secret_key_db_app_credentials
      DB_HOST             = aws_db_instance.dragon.endpoint
      DB_NAME             = var.db_name
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.dragon_db_ops.arn
  function_name    = aws_lambda_function.dragon.arn
  enabled          = true
  batch_size       = 1
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.dragon.function_name}"
  retention_in_days = 3
}