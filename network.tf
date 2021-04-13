#VPC
resource "aws_vpc" "cks" {
  tags = {
    "Name" = "cks"
  }
  cidr_block = "10.0.0.0/16"
}

#gateway
resource "aws_internet_gateway" "cks" {
  vpc_id = aws_vpc.cks.id
}

#subnets
resource "aws_subnet" "cks-az-2a" {
  vpc_id            = aws_vpc.cks.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-2a"

  tags = {
    "Name" = "cks"
    "kind" = "public"
  }
}
resource "aws_subnet" "cks-az-2b" {
  vpc_id            = aws_vpc.cks.id
  availability_zone = "eu-west-2b"
  cidr_block        = "10.0.2.0/24"

  tags = {
    "Name" = "cks"
    "kind" = "private"
  }
}

#route teable
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.cks.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cks.id
  }

  tags = {
    Name = "cks"
  }
}

#route and subnet association
resource "aws_route_table_association" "a" {
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.cks-az-2a.id
}

#firewall
resource "aws_security_group" "egress" {
  description = "Allow all outgoing traffic to everywhere"
  vpc_id      = aws_vpc.cks.id
  tags = {
    Name = "cks"
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ingress_internal" {
  description = "Allow all incoming traffic from nodes and Pods in the cluster"
  vpc_id      = aws_vpc.cks.id
  tags = {
    Name = "cks"
  }

  ingress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    self        = true
    description = "Allow incoming traffic from cluster nodes"

  }

  ingress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = [aws_vpc.cks.cidr_block, "81.103.11.106/32"]
    description = "Allow incoming traffic from the Pods of the cluster"
  }
}

resource "aws_security_group" "ingress_k8s" {
  description = "Allow incoming Kubernetes API requests (TCP/6443) from outside the cluster"
  vpc_id      = aws_vpc.cks.id
  tags = {
    Name = "cks"
  }

  ingress {
    protocol    = "tcp"
    from_port   = 6443
    to_port     = 6443
    cidr_blocks = [aws_vpc.cks.cidr_block, "81.103.11.106/32"]
  }
}

resource "aws_security_group" "ingress_ssh" {
  description = "Allow incoming SSH traffic (TCP/22) from outside the cluster"
  vpc_id      = aws_vpc.cks.id
  tags = {
    Name = "cks"
  }
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = [aws_vpc.cks.cidr_block, "81.103.11.106/32"]
  }
}