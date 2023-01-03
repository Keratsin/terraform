provider "aws" {
  region = var.primary_region
}
provider "aws" {
  alias  = "west"
  region = "us-west-1"
}
resource "aws_default_vpc" "main" {
  tags = {
    Name = "main_vpc"
  }
}
resource "aws_default_subnet" "private_subnet" {
  availability_zone = "us-east-1a"
}
resource "aws_eip" "eip_east" {
  instance = aws_instance.server_east["prod"].id
  vpc      = true
}
resource "aws_eip" "eip_west" {
  provider = aws.west
  instance = aws_instance.server_west[0].id
  vpc      = true
}
data "template_file" "user_data" {
  template = file("user-data.sh")
}
resource "aws_instance" "server_west" {
  count                  = 2
  provider               = aws.west
  vpc_security_group_ids = [aws_security_group.west-test-sg.id]
  #use ami_west1 if var.primary_region equals to us-east-1 otherwise use var.ami_east1
  ami           = var.primary_region == "us-east-1" ? var.ami_west1 : "us-east-2"
  instance_type = var.instance_type
  user_data     = data.template_file.user_data.rendered
  tags = {
    Name      = "Test-server${count.index + 1}"
    secondary = "west-test"
  }
  lifecycle {
    create_before_destroy = true
  }
  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ec2-user"
    private_key = file(var.key_path)
  }
}
resource "aws_instance" "server_east" {
  key_name                    = "key-pair-ssh"
  vpc_security_group_ids      = [aws_security_group.east-test-sg.id]
  subnet_id                   = aws_default_subnet.private_subnet.id
  associate_public_ip_address = true
  user_data = <<EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y httpd
              sudo systemctl start httpd
              sudo systemctl enable httpd
              echo "<h1>Hello world from $(hostname -f)</h1>" | sudo tee -a /var/www/html/index.html
              EOF
  provisioner "remote-exec" { #used to execute remotely commands
    inline = [
      "mkdir -p /var/www/html && touch var/www/html/index.html"
    ]
  }
  for_each = {
    dev  = "t1.micro"
    prod = "t2.micro"
  }
  instance_type = each.value
  ami           = lookup(var.ami_east, var.primary_region)
  tags = {
    Name = "Test-server${each.key}"
  }
  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ec2-user"
    private_key = file(var.key_path)
  }
}
locals {
  any_port      = 0
  any_protocol  = "-1"
  all_ips       = ["0.0.0.0/0"]
  http_port     = 80
  http_protocol = "tcp"
}
resource "aws_security_group" "east-test-sg" {
  name = "east-test"
  ingress {
    from_port   = local.http_port
    protocol    = local.http_protocol
    to_port     = local.http_port
    cidr_blocks = local.all_ips
  }
  egress {
    from_port   = local.http_port
    protocol    = local.http_protocol
    to_port     = local.http_port
    cidr_blocks = local.all_ips
  }
}
resource "aws_security_group_rule" "east-test-ssh-in" {
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.east-test-sg.id
  to_port           = 22
  cidr_blocks       = local.all_ips
  type              = "ingress"
}
resource "aws_security_group_rule" "east-test-ssh-out" {
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.east-test-sg.id
  to_port           = 22
  cidr_blocks       = local.all_ips
  type              = "egress"
}
resource "aws_security_group" "west-test-sg" {
  name     = "west-test"
  provider = aws.west
  ingress {
    from_port   = local.http_port
    protocol    = local.http_protocol
    to_port     = local.http_port
    cidr_blocks = local.all_ips
  }
  egress {
    from_port   = local.http_port
    protocol    = local.http_protocol
    to_port     = local.http_port
    cidr_blocks = local.all_ips
  }
}
resource "aws_security_group_rule" "west-test-ssh-in" {
  provider          = aws.west
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.west-test-sg.id
  to_port           = 22
  cidr_blocks       = local.all_ips
  type              = "ingress"
}
resource "aws_security_group_rule" "west-test-ssh-out" {
  provider          = aws.west
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.west-test-sg.id
  to_port           = 22
  cidr_blocks       = local.all_ips
  type              = "egress"
}
