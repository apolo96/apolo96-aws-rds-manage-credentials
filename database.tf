
resource "aws_security_group" "rds_sg" {
  name   = "rds-dragon-security-group"
  vpc_id = aws_default_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "rds_ingress" {
  security_group_id            = aws_security_group.rds_sg.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lambda_sg.id
}

resource "aws_vpc_security_group_egress_rule" "rds_egress" {
  security_group_id = aws_security_group.rds_sg.id
  from_port         = 0
  to_port           = 0
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_db_subnet_group" "dragon" {
  name       = "subnet-group-dragon"
  subnet_ids = ["subnet-f03de7c1", "subnet-fa54c7a5"]

  tags = {
    Name = "Dragon DB subnet group"
  }
}

resource "aws_db_instance" "dragon" {
  identifier                  = var.rds_db_identifier
  allocated_storage           = 10
  db_name                     = "dragon"
  engine                      = "mysql"
  engine_version              = "8.0"
  instance_class              = "db.t3.micro"
  username                    = var.rds_dragon_username
  manage_master_user_password = true
  parameter_group_name        = "default.mysql8.0"
  db_subnet_group_name        = aws_db_subnet_group.dragon.name
  skip_final_snapshot         = true
  vpc_security_group_ids      = [aws_security_group.rds_sg.id]
}

resource "aws_db_event_subscription" "dragon" {
  name      = "rds-event-sub"
  sns_topic = aws_sns_topic.dragon.arn

  source_type = "db-instance"
  source_ids  = [var.rds_db_identifier]

  event_categories = [
    "creation",
  ]
}
