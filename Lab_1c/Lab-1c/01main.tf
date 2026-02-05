############################################
# Locals (naming convention: satellite-*)
############################################
locals {
  name_prefix = var.project_name
  ports_http  = 80
  ports_ssh   = 22
  ports_https = 443
  # ports_dns = 53
  db_port        = 3306
  tcp_protocol   = "tcp"
  udp_protocol   = "udp"
  all_ip_address = "0.0.0.0/0"
  # For AWS SG rules, "all protocols" is represented by ip_protocol = "-1".
  # When ip_protocol = "-1", AWS expects from_port/to_port to be 0.
  all_ports    = 0
  all_protocol = "-1"
  interface_endpoint_services = toset([
    "ssm",
    "ec2messages",
    "ssmmessages",
    "logs",
    "secretsmanager",
    "kms"
  ])
}

############################################
# VPC + Internet Gateway
############################################

resource "aws_vpc" "chrisbarm_vpc01" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc01"
  }
}

resource "aws_internet_gateway" "chrisbarm_igw01" {
  vpc_id = aws_vpc.chrisbarm_vpc01.id

  tags = {
    Name = "${local.name_prefix}-igw01"
  }
}

############################################
# Subnets
############################################

resource "aws_subnet" "chrisbarm_public_subnets" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.chrisbarm_vpc01.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${count.index + 1}"
  }
}

resource "aws_subnet" "chrisbarm_private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.chrisbarm_vpc01.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${local.name_prefix}-private-${count.index + 1}"
  }
}

############################################
# Routing
############################################

# Public route table: Internet access for the EC2 app host (reachable over HTTP)
resource "aws_route_table" "chrisbarm_public_rt01" {
  vpc_id = aws_vpc.chrisbarm_vpc01.id

  tags = {
    Name = "${local.name_prefix}-public-rt01"
  }
}

resource "aws_route" "chrisbarm_public_default_route" {
  route_table_id         = aws_route_table.chrisbarm_public_rt01.id
  destination_cidr_block = local.all_ip_address
  gateway_id             = aws_internet_gateway.chrisbarm_igw01.id
}

resource "aws_route_table_association" "chrisbarm_public_rta" {
  count          = length(aws_subnet.chrisbarm_public_subnets)
  subnet_id      = aws_subnet.chrisbarm_public_subnets[count.index].id
  route_table_id = aws_route_table.chrisbarm_public_rt01.id
}

# Private route table: no internet route (RDS stays private)
resource "aws_route_table" "chrisbarm_private_rt01" {
  vpc_id = aws_vpc.chrisbarm_vpc01.id

  tags = {
    Name = "${local.name_prefix}-private-rt01"
  }
}

resource "aws_route_table_association" "chrisbarm_private_rta" {
  count          = length(aws_subnet.chrisbarm_private_subnets)
  subnet_id      = aws_subnet.chrisbarm_private_subnets[count.index].id
  route_table_id = aws_route_table.chrisbarm_private_rt01.id
}

############################################
# NAT Gateway (Optional for package installs)
############################################

resource "aws_eip" "chrisbarm_nat_eip01" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip01"
  }
}

resource "aws_nat_gateway" "chrisbarm_nat01" {
  allocation_id = aws_eip.chrisbarm_nat_eip01.id
  subnet_id     = aws_subnet.chrisbarm_public_subnets[0].id

  tags = {
    Name = "${local.name_prefix}-nat01"
  }

  depends_on = [aws_internet_gateway.chrisbarm_igw01]
}

resource "aws_route" "chrisbarm_private_default_route" {
  route_table_id         = aws_route_table.chrisbarm_private_rt01.id
  destination_cidr_block = local.all_ip_address
  nat_gateway_id         = aws_nat_gateway.chrisbarm_nat01.id
}

############################################
# Security Groups (EC2 + RDS)
############################################

# EC2 SG: allow inbound HTTP, allow egress (so the app can reach RDS + AWS APIs)
resource "aws_security_group" "chrisbarm_ec2_sg01" {
  name        = "chrisbarm-ec2-lab"
  description = "EC2 app security group (HTTP)"
  vpc_id      = aws_vpc.chrisbarm_vpc01.id

  tags = {
    Name = "chrisbarm-ec2-lab"
  }
}

resource "aws_vpc_security_group_ingress_rule" "chrisbarm_ec2_sg_ingress_http" {
  ip_protocol       = local.tcp_protocol
  security_group_id = aws_security_group.chrisbarm_ec2_sg01.id
  from_port         = local.ports_http
  to_port           = local.ports_http
  cidr_ipv4         = local.all_ip_address
}

resource "aws_vpc_security_group_egress_rule" "chrisbarm_ec2_sg_egress_all" {
  ip_protocol       = local.all_protocol
  security_group_id = aws_security_group.chrisbarm_ec2_sg01.id
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = local.all_ip_address
}

# RDS SG: only allow inbound MySQL from the EC2 SG (no public access)
resource "aws_security_group" "chrisbarm_rds_sg01" {
  name        = "arm-sg-rds-lab"
  description = "RDS security group (MySQL from EC2 SG only)"
  vpc_id      = aws_vpc.chrisbarm_vpc01.id

  tags = {
    Name = "arm-sg-rds-lab"
  }
}

resource "aws_vpc_security_group_ingress_rule" "chrisbarm_rds_sg_ingress_mysql" {
  ip_protocol                  = local.tcp_protocol
  security_group_id            = aws_security_group.chrisbarm_rds_sg01.id
  from_port                    = local.db_port
  to_port                      = local.db_port
  referenced_security_group_id = aws_security_group.chrisbarm_ec2_sg01.id
}

resource "aws_vpc_security_group_egress_rule" "chrisbarm_rds_sg_egress_all" {
  ip_protocol       = local.all_protocol
  security_group_id = aws_security_group.chrisbarm_rds_sg01.id
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = local.all_ip_address
}

############################################
# VPC Endpoints (Bonus-A: SSM + Logs + Secrets + S3)
############################################

resource "aws_security_group" "chrisbarm_vpce_sg01" {
  name        = "${local.name_prefix}-vpce-sg01"
  description = "VPC Endpoint SG (HTTPS from EC2 only)"
  vpc_id      = aws_vpc.chrisbarm_vpc01.id

  tags = {
    Name = "${local.name_prefix}-vpce-sg01"
  }
}

resource "aws_vpc_security_group_ingress_rule" "chrisbarm_vpce_sg_ingress_https" {
  ip_protocol                  = local.tcp_protocol
  security_group_id            = aws_security_group.chrisbarm_vpce_sg01.id
  from_port                    = local.ports_https
  to_port                      = local.ports_https
  referenced_security_group_id = aws_security_group.chrisbarm_ec2_sg01.id
}

resource "aws_vpc_security_group_egress_rule" "chrisbarm_vpce_sg_egress_all" {
  ip_protocol       = local.all_protocol
  security_group_id = aws_security_group.chrisbarm_vpce_sg01.id
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = local.all_ip_address
}

resource "aws_vpc_endpoint" "chrisbarm_interface_endpoints" {
  for_each            = local.interface_endpoint_services
  vpc_id              = aws_vpc.chrisbarm_vpc01.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.chrisbarm_private_subnets[*].id
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.chrisbarm_vpce_sg01.id]

  tags = {
    Name = "${local.name_prefix}-vpce-${each.key}"
  }
}

resource "aws_vpc_endpoint" "chrisbarm_s3_gateway_endpoint" {
  vpc_id            = aws_vpc.chrisbarm_vpc01.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.chrisbarm_private_rt01.id]

  tags = {
    Name = "${local.name_prefix}-vpce-s3"
  }
}

############################################
# RDS Subnet Group + RDS Instance (MySQL)
############################################

resource "aws_db_subnet_group" "chrisbarm_rds_subnet_group01" {
  name       = "${local.name_prefix}-rds-subnet-group02" # changed to avoid conflict
  subnet_ids = aws_subnet.chrisbarm_private_subnets[*].id

  tags = {
    Name = "${local.name_prefix}-rds-subnet-group02"
  }
}

resource "aws_db_instance" "chrisbarm_rds01" {
  identifier               = "chrisbarm-mysql"
  engine                   = var.db_engine
  instance_class           = var.db_instance_class
  storage_type             = var.storage_type
  allocated_storage        = 20
  backup_retention_period  = 0
  db_name                  = var.db_name
  username                 = var.db_username
  password                 = var.db_password
  multi_az                 = false
  delete_automated_backups = false

  db_subnet_group_name   = aws_db_subnet_group.chrisbarm_rds_subnet_group01.name
  vpc_security_group_ids = [aws_security_group.chrisbarm_rds_sg01.id]

  publicly_accessible = false
  skip_final_snapshot = true

  tags = {
    Name = "lab-mysql"
  }

  depends_on = [aws_db_subnet_group.chrisbarm_rds_subnet_group01, aws_security_group.chrisbarm_rds_sg01]
}

############################################
# Secrets Manager (lab/rds/mysql)
############################################

resource "aws_secretsmanager_secret" "chrisbarm_db_secret01" {
  name                    = "lab1a/rds/mysql"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "chrisbarm_db_secret_version01" {
  secret_id = aws_secretsmanager_secret.chrisbarm_db_secret01.id

  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.chrisbarm_rds01.address
    port     = aws_db_instance.chrisbarm_rds01.port
    dbname   = var.db_name
  })

  depends_on = [aws_db_instance.chrisbarm_rds01]
}

############################################
# IAM Role + Instance Profile for EC2
############################################

resource "aws_iam_role" "chrisbarm_ec2_role01" {
  name = "${local.name_prefix}-ec2-role01"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "chrisbarm_secrets_policy" {
  name        = "${local.name_prefix}-secrets-read-lab-rds-mysql"
  description = "Least-privilege Secrets Manager read access for lab secret only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadLabSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.chrisbarm_db_secret01.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "chrisbarm_ec2_secrets_attach" {
  role       = aws_iam_role.chrisbarm_ec2_role01.name
  policy_arn = aws_iam_policy.chrisbarm_secrets_policy.arn
}

resource "aws_iam_role_policy_attachment" "chrisbarm_ec2_ssm_attach" {
  role       = aws_iam_role.chrisbarm_ec2_role01.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "chrisbarm_instance_profile01" {
  name = "${local.name_prefix}-instance-profile01"
  role = aws_iam_role.chrisbarm_ec2_role01.name
}

############################################
# EC2 Instance (App Host)
############################################

locals {
  # Simple Flask app that uses Secrets Manager for DB credentials and reads/writes to RDS.
  # Endpoints:
  #   /init
  #   /add?note=...
  #   /list
  app_user_data = <<-EOT
    #!/bin/bash
    set -euo pipefail

    dnf update -y
    dnf install -y python3 python3-pip mysql

    mkdir -p /opt/labapp
    cat > /opt/labapp/app.py <<'PY'
    import json
    import os
    from datetime import datetime

    import boto3
    import pymysql
    from flask import Flask, request

    REGION = os.environ.get("AWS_REGION", "us-east-1")
    SECRET_ID = os.environ.get("SECRET_ID", "lab/rds/mysql")

    app = Flask(__name__)

    def get_secret():
      client = boto3.client("secretsmanager", region_name=REGION)
      resp = client.get_secret_value(SecretId=SECRET_ID)
      return json.loads(resp["SecretString"])

    def get_conn():
      s = get_secret()
      return pymysql.connect(
        host=s["host"],
        user=s["username"],
        password=s["password"],
        database=s["dbname"],
        port=int(s["port"]),
        connect_timeout=5,
        autocommit=True,
      )

    @app.get("/")
    def home():
      return (
        "EC2 → RDS Integration Lab\\n"
        "Try:\\n"
        "  /init\\n"
        "  /add?note=cloud_labs_are_real\\n"
        "  /list\\n"
      ), 200, {"Content-Type": "text/plain; charset=utf-8"}

    @app.get("/init")
    def init_db():
      with get_conn() as conn:
        with conn.cursor() as cur:
          cur.execute(
            "CREATE TABLE IF NOT EXISTS notes ("
            " id INT AUTO_INCREMENT PRIMARY KEY,"
            " note VARCHAR(255) NOT NULL,"
            " created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
            ")"
          )
      return "OK: initialized", 200, {"Content-Type": "text/plain; charset=utf-8"}

    @app.get("/add")
    def add_note():
      note = request.args.get("note", "").strip()
      if not note:
        return "ERROR: provide ?note=...", 400, {"Content-Type": "text/plain; charset=utf-8"}
      with get_conn() as conn:
        with conn.cursor() as cur:
          cur.execute("INSERT INTO notes(note) VALUES (%s)", (note,))
      return f"OK: inserted '{note}'", 200, {"Content-Type": "text/plain; charset=utf-8"}

    @app.get("/list")
    def list_notes():
      with get_conn() as conn:
        with conn.cursor() as cur:
          cur.execute("SELECT id, note, created_at FROM notes ORDER BY id DESC LIMIT 50")
          rows = cur.fetchall()
      out = ["id\\tnote\\tcreated_at"]
      for r in rows:
        out.append(f"{r[0]}\\t{r[1]}\\t{r[2]}")
      return "\\n".join(out) + "\\n", 200, {"Content-Type": "text/plain; charset=utf-8"}

    if __name__ == "__main__":
      app.run(host="0.0.0.0", port=80)
    PY

    pip3 install --no-cache-dir flask pymysql boto3

    cat > /etc/systemd/system/labapp.service <<'UNIT'
    [Unit]
    Description=EC2 RDS Integration Lab App (Flask)
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=simple
    Environment=AWS_REGION=${var.aws_region}
    Environment=SECRET_ID=lab/rds/mysql
    ExecStart=/usr/bin/python3 /opt/labapp/app.py
    Restart=always
    RestartSec=2

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable --now labapp
  EOT
}

resource "aws_instance" "chrisbarm_ec2_01" {
  ami                         = "ami-0030e4319cbf4dbf2"  # Ubuntu 22.04 LTS in us-east-1
  instance_type               = var.ec2_instance_type
  subnet_id                   = aws_subnet.chrisbarm_private_subnets[0].id
  vpc_security_group_ids      = [aws_security_group.chrisbarm_ec2_sg01.id]
  iam_instance_profile        = aws_iam_instance_profile.chrisbarm_instance_profile01.name
  user_data_replace_on_change = true
  associate_public_ip_address = false
  
  # TODO: student supplies user_data to install app + CW agent + configure log shipping
  user_data  = file("${path.module}/1a_user_data.sh")
  depends_on = [aws_db_instance.chrisbarm_rds01]

  tags = {
    Name = "${local.name_prefix}-ec2_01"
  }
}