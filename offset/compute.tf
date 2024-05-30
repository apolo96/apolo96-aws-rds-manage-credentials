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

resource "aws_iam_policy" "lambda_secrets_manager" {
  name        = "SecretsManagerPolicy"
  description = "Policy to allow Lambda to manage secrets in Secrets Manager"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret",
          "secretsmanager:DeleteSecret"
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

data "aws_iam_policy_document" "allow_lambda_dragon_logging" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:aws:logs:*:*:*",
    ]
  }
}

resource "aws_iam_policy" "lambda_logging_policy" {
  name        = "AllowLambdaLoggingPolicy"
  description = "Policy for lambda cloudwatch logging"
  policy      = data.aws_iam_policy_document.allow_lambda_dragon_logging.json
}

resource "aws_iam_role_policy_attachment" "lambda_logging_policy_attachment" {
  role       = aws_iam_role.dragon.id
  policy_arn = aws_iam_policy.lambda_logging_policy.arn
}

resource "aws_security_group" "lambda_sg" {
  name = "lambda-dragon-security-group"
  vpc_id = aws_default_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "rds_ingress" {
  security_group_id = aws_security_group.lambda_sg.id
  from_port = 0
  to_port   = 0
  ip_protocol  = "-1"
  cidr_ipv4 = ["0.0.0.0/0"] 
}

resource "aws_vpc_security_group_egress_rule" "rds_egress" {
  security_group_id = aws_security_group.lambda_sg.id
  from_port = 0
  to_port   = 0
  ip_protocol  = "-1"
  cidr_ipv4 = ["0.0.0.0/0"] 
}

resource "null_resource" "function_binary" {
  provisioner "local-exec" {
    command = "GOOS=linux GOARCH=amd64 CGO_ENABLED=0 GOFLAGS=-trimpath go build -mod=readonly -ldflags='-s -w' -o ${local.binary_path} ${local.src_path}"
  }
}

data "archive_file" "function_archive" {
  depends_on = [null_resource.function_binary]
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

  runtime = "go1.x"

  vpc_config {
    subnet_ids         = ["subnet-2d8fa960"]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      SECRET_NAME_DB_USER = var.secret_name_db_user
      SECRET_NAME_DB_PASSWORD = var.secret_name_db_password
    }
  }
}

resource "aws_sns_topic_subscription" "dragon" {
  topic_arn = aws_sns_topic.dragon.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.rds_create_user.arn
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dragon.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.dragon.arn
}