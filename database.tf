
resource "aws_security_group" "rds_sg" {
  name   = "rds-dragon-security-group"
  vpc_id = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "rds_ingress" {
  security_group_id            = aws_security_group.rds_sg.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lambda_sg.id
}

resource "aws_vpc_security_group_ingress_rule" "rds_bastion_ingress" {
  security_group_id            = aws_security_group.rds_sg.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.bastion.id
}

resource "aws_vpc_security_group_egress_rule" "rds_egress" {
  security_group_id = aws_security_group.rds_sg.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_db_subnet_group" "dragon" {
  name       = "subnet-group-dragon"
  subnet_ids = [aws_subnet.private1.id, aws_subnet.private2.id]

  tags = {
    Name = "Dragon DB subnet group"
  }
}

resource "aws_db_instance" "dragon" {
  identifier                  = "dragonfly"
  allocated_storage           = 10
  db_name                     = "dragon"
  engine                      = "mysql"
  engine_version              = "8.0"
  instance_class              = "db.t3.micro"
  username                    = var.db_master_user
  manage_master_user_password = true
  parameter_group_name        = "default.mysql8.0"
  db_subnet_group_name        = aws_db_subnet_group.dragon.name
  skip_final_snapshot         = true
  vpc_security_group_ids      = [aws_security_group.rds_sg.id]
}

resource "aws_db_event_subscription" "dragon_db_ops" {
  name      = "dragon-db-ops"
  sns_topic = aws_sns_topic.dragon_db_ops.arn

  source_type = "db-instance"
  source_ids  = [aws_db_instance.dragon.identifier]

  event_categories = [
    "creation",
  ]
}
