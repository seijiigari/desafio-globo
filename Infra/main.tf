resource "aws_vpc" "poc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.env}-vpc"
  }
}
# Subnets Publicas
resource "aws_subnet" "subnet_publica" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.poc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.env}-public-subnet-${count.index + 1}"
  }
}
# Subnets Privadas
resource "aws_subnet" "subnet_privada" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.poc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "${var.env}-private-subnet-${count.index + 1}"
  }
}
# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.poc.id
  tags = {
    Name = "${var.env}-igw"
  }
}
# Elastic IP do NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = {
    Name = "${var.env}-nat-eip"
  }
}
# NAT Gateway
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.subnet_publica[0].id
  tags = {
    Name = "${var.env}-nat-gw"
  }
}
# Route Table Publica
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.poc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.env}-public-rt"
  }
}
# Associação das Subnets publicas ao Route Table publica
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.subnet_publica[count.index].id
  route_table_id = aws_route_table.public.id
}
# Route Table Privada
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.poc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = {
    Name = "${var.env}-private-rt"
  }
}
# Associação das Subnets privadas ao Route Table privada
resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.subnet_privada[count.index].id
  route_table_id = aws_route_table.private.id
}
##############################################################

# Criação dos recursos para suportar as aplicações

# Redis ElastiCache para cache
resource "aws_elasticache_cluster" "app_cache" {
  cluster_id           = "cache-aplicacoes"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis6.x"
  engine_version       = "6.x"
  port                 = 6379
  security_group_ids   = [aws_security_group.sg_redis.id]
  subnet_group_name    = aws_elasticache_subnet_group.app_cache_subnet_group.name
}
resource "aws_elasticache_subnet_group" "app_cache_subnet_group" {
  name       = "app-cache-subnet-group"
  subnet_ids = aws_subnet.subnet_privada[*].id
}
resource "aws_security_group" "sg_redis" {
  name        = "sg_redis"
  description = "SG do ElastiCache"
  vpc_id      = aws_vpc.poc.id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    security_groups = [aws_security_group.sg_aplicacoes.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group" "sg_aplicacoes" {
  name        = "sg_aplicacoes"
  description = "HTTP, HTTPS e Redis"
  vpc_id      = aws_vpc.poc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Saida
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-aplicacoes"
  }
}

# criacao da funcao IAM
resource "aws_iam_role" "ssm_role" {
  name = "ssm-to-aplicacoes"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}
# Colocando a política do AWS Systems Manager na funcao
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Criar um perfil da EC2
resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "ssm-aplicacoes"
  role = aws_iam_role.ssm_role.name
}

#Criando IP fixo para as EC2
resource "aws_eip" "app_python_ip_fixo" {
  domain = "vpc"
  tags = {
    Name = "app-python-ip_fixo"
  }
}
# resource "aws_eip" "app_go_ip_fixo" {
#   domain = "vpc"
#   tags = {
#     Name = "app-go-ip_fixo"
#   }
# }

#Servidores
resource "aws_instance" "app_python" {
  ami = "ami-04b4f1a9cf54c11d0" # Ubuntu 20.04 LTS
  instance_type = "t3.micro"
  subnet_id = aws_subnet.subnet_publica[0].id
  security_groups = [aws_security_group.sg_aplicacoes.id]
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name
root_block_device {
    volume_size = 8
    volume_type = "gp2"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y python3 python3-pip
              mkdir -p /app/python-app
              mkdir -p /app/python-app/templates
              echo "${filebase64("${path.module}/../main.py")}" | base64 --decode > /app/python-app/main.py
              echo "${filebase64("${path.module}/../routes.py")}" | base64 --decode > /app/python-app/routes.py
              echo "${filebase64("${path.module}/../templates/datetime.html")}" | base64 --decode > /app/python-app/templates/datetime.html
              echo "${filebase64("${path.module}/../templates/index.html")}" | base64 --decode > /app/python-app/templates/index.html
              sed -i "s/endpoint-redis/${aws_elasticache_cluster.app_cache.cache_nodes[0].address}/g" /app/python-app/main.py
              sudo apt install python3-flask python3-flask-caching -y
              cd /app/python-app
              python3 main.py &
              EOF
  tags = {
    Name = "PythonApp"
  }
}

# resource "aws_instance" "app_go" {
#   ami = "ami-04b4f1a9cf54c11d0"
#   instance_type = "t3.micro"
#   subnet_id = aws_subnet.subnet_publica[0].id
#   security_groups = [aws_security_group.sg_aplicacoes.id]
# root_block_device {
#     volume_size = 8
#     volume_type = "gp2"
#   }
#   tags = {
#     Name = "GoApp"
#   }
# }

#Attachando IP fixo a EC2 python
resource "aws_eip_association" "app_python_eip_assoc" {
  instance_id   = aws_instance.app_python.id
  allocation_id = aws_eip.app_python_ip_fixo.id
}
# resource "aws_eip_association" "app_go_eip_assoc" {
#   instance_id   = aws_instance.app_go.id
#   allocation_id = aws_eip.app_go_ip_fixo.id
# }

