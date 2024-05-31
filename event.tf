resource "aws_iam_role" "sns_log_topic" {
  name = "SNSFeedbackLogging"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "sns.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}
resource "aws_iam_policy" "sns_log_topic" {
  name        = "SNSFeedbackLogging"
  description = "SNSFeedbackLogging for topic logging"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:PutMetricFilter",
          "logs:PutRetentionPolicy"
        ],
        "Resource" : [
          "*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sns_log_topic" {
  role       = aws_iam_role.sns_log_topic.name
  policy_arn = aws_iam_policy.sns_log_topic.arn
}


resource "aws_sns_topic" "dragon_db_ops" {
  name                             = "dragon-db-ops"
  sqs_success_feedback_sample_rate = 100
  sqs_failure_feedback_role_arn    = aws_iam_role.sns_log_topic.arn
  sqs_success_feedback_role_arn    = aws_iam_role.sns_log_topic.arn
}

resource "aws_sqs_queue" "dragon_db_ops" {
  name                      = "dragon-db-ops"
  delay_seconds             = 10
  max_message_size          = 2048
  message_retention_seconds = 86400
  receive_wait_time_seconds = 10
}

resource "aws_sqs_queue_policy" "dragon_db_ops" {
  queue_url = aws_sqs_queue.dragon_db_ops.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.dragon_db_ops.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.dragon_db_ops.arn
          }
        }
      }
    ]
  })
}


resource "aws_sns_topic_subscription" "dragon_db_ops" {
  topic_arn = aws_sns_topic.dragon_db_ops.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.dragon_db_ops.arn
}