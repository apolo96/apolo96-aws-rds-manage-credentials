resource "tls_private_key" "bastion_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "bastion_key_pair" {
  key_name   = "bastion_key"
  public_key = tls_private_key.bastion_key.public_key_openssh
}

resource "local_file" "tf_key" {
  content  = tls_private_key.bastion_key.private_key_pem
  filename = "bastion_key.pem"
  file_permission = "0400"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"]
}


resource "aws_security_group" "bastion" {
  name   = "bastion-dragon-security-group"
  vpc_id = aws_default_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "bastion" {
  security_group_id = aws_security_group.bastion.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = "201.185.198.7/32"
}

resource "aws_vpc_security_group_egress_rule" "bastion" {
  security_group_id = aws_security_group.bastion.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.bastion_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.bastion.id]
  subnet_id              = "subnet-1075e831"
  tags = {
    Name = "bastion-dragon"
  }
}


