data "aws_vpc" "selected" {
  id = var.vpc_id
}

resource "aws_security_group" "this" {
  count = var.create ? 1 : 0

  name        = var.default_security_group_name
  description = "Default Security Group for DocumentDB cluster."
  vpc_id      = var.vpc_id
  ingress {
    cidr_blocks = [data.aws_vpc.selected.vpc_cidr_block]
    description = "Allow inbound traffic from CIDR VPC Block."
    from_port   = var.db_port
    to_port     = var.db_port
    protocol    = "tcp"
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all egress traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  tags = var.tags
}

resource "aws_docdb_subnet_group" "this" {
  count = var.create ? 1 : 0

  name       = var.subnet_group_name
  subnet_ids = var.subnets_ids

  tags = var.tags
}

resource "aws_docdb_cluster_instance" "this" {
  count = var.create ? 1 : 0

  identifier         = var.instance_name
  instance_class     = var.instance_class
  cluster_identifier = aws_docdb_cluster.this[count.index].id

  tags = var.tags
}

resource "random_password" "docdb" {
  count   = var.master_password != "" ? 0 : 1
  length  = 16
  special = false
}

resource "aws_docdb_cluster" "this" {
  count = var.create ? 1 : 0

  cluster_identifier = var.name

  engine          = var.engine
  engine_version  = var.engine_version


  db_cluster_parameter_group_name = var.create_paramenter_group ? aws_docdb_cluster_parameter_group.this[0].name : null

  master_username = var.master_username
  master_password = var.master_password != "" ? var.master_password : random_password.docdb[0].result
  port            = var.db_port

  # Network Configuration
  vpc_security_group_ids = concat([aws_security_group.this[0].id], var.aditional_security_group_ids)
  db_subnet_group_name   = aws_docdb_subnet_group.this[0].name

  apply_immediately       = var.apply_immediately
  storage_encrypted       = var.storage_encrypted
  deletion_protection     = var.deletion_protection
  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = var.skip_final_snapshot
  snapshot_identifier     = var.snapshot_identifier
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  tags = var.tags
}

resource "aws_docdb_cluster_parameter_group" "this" {
  count = var.create && var.create_paramenter_group ? 1 : 0

  name        = var.parameter_group_name
  description = "${var.name} DocumentDB cluster parameter group"
  family      = var.parameter_group_family

  dynamic "parameter" {
    for_each = var.cluster_parameters
    content {
      apply_method = lookup(parameter.value, "apply_method", null)
      name         = parameter.value.name
      value        = parameter.value.value
    }
  }

  tags = var.tags
}

module "dns" {
  source  = "terraform-aws-modules/route53/aws//modules/records"
  version = "2.9.0"

  zone_name = var.dns_zone_name

  records = [
    {
      name    = local.master_dns_name
      type    = "CNAME"
      records = coalescelist(aws_docdb_cluster.this.*.endpoint, [""])
    },
    {
      name    = local.reader_dns_name
      type    = "CNAME"
      records = coalescelist(aws_docdb_cluster.this.*.reader_endpoint, [""])
    },
  ]

  depends_on = [aws_docdb_cluster.this]
}