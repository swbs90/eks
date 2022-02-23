resource "aws_vpc" "example" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    "kubernetes.io/cluster/example" = "shared"
  }
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.10.0/24"
  availability_zone       = data.aws_availability_zones.available.names.0
  map_public_ip_on_launch = true
  tags = {
    "kubernetes.io/cluster/example" = "shared"
  }
}

resource "aws_subnet" "sub" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.20.0/24"
  availability_zone       = data.aws_availability_zones.available.names.1
  map_public_ip_on_launch = true
  tags = {
    "kubernetes.io/cluster/example" = "shared"
  }
}


resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id
}

resource "aws_eip" "example" {
  vpc = true
}

resource "aws_nat_gateway" "example" {
  allocation_id = aws_eip.example.id
  subnet_id     = aws_subnet.main.id
}

resource "aws_default_route_table" "example" {
  default_route_table_id = aws_vpc.example.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example.id
  }
}

resource "aws_route_table_association" "example" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_default_route_table.example.id
}

resource "aws_default_network_acl" "example" {
  default_network_acl_id = aws_vpc.example.default_network_acl_id

  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 65535
  }

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}


resource "aws_default_security_group" "example" {
  vpc_id = aws_vpc.example.id

  ingress {
    protocol    = "tcp"
    from_port   = 0
    to_port     = 65535
    cidr_blocks = [aws_vpc.example.cidr_block]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

locals {
  sg_tcp_ports = [22, 8200]
}

resource "aws_security_group" "example" {
  vpc_id = aws_vpc.example.id
  name   = "${var.prefix}-sg"

  dynamic "ingress" {
    for_each = local.sg_tcp_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_eks_cluster" "eks" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "eks" {
  name = module.eks.cluster_id
}

module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "17.24.0"

  cluster_version           = "1.21"
  cluster_name              = "${var.prefix}-cluster"
  vpc_id                    = aws_vpc.example.id
  subnets                   = [ aws_subnet.main.id, aws_subnet.sub.id]
  cluster_security_group_id = aws_security_group.example.id

  write_kubeconfig = false

  worker_groups = [
    {
      instance_type = "m5.large"
      asg_desired_capacity = 3
      asg_min_size = 3
      asg_max_size  = 3
      additional_security_group_ids = [aws_security_group.example.id]
      subnets = [ aws_subnet.main.id ]
    }
  ]
  // worker_security_group_id = aws_security_group.example.id

  // node_groups = [
  //   {
  //     instance_type = "m5.large"
  //     desired_capacity = 3
  //     min_capacity = 3
  //     max_capacity = 3
  //     source_security_group_ids = [aws_security_group.example.id]
  //     subnets                   = [aws_subnet.main.id, aws_subnet.k8s_1.id, aws_subnet.k8s_2.id]
  //   }
  // ]
}

resource "local_file" "kubeconfig" {
  content  = module.eks.kubeconfig
  filename = "./.kube/config"
}

##### Kubernetes
provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.eks.token
  }
}
