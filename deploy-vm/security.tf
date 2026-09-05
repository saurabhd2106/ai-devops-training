resource "aws_security_group" "instance" {
  for_each = local.vms

  name_prefix = "${var.project_name}-${var.environment}-${each.key}-"
  description = "SSH and role ports for ${each.key}; all egress for updates and AWS APIs"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}-sg"
    Role = each.key
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = local.vms

  security_group_id = aws_security_group.instance[each.key].id
  description       = "SSH from allowed CIDR"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.allowed_ssh_cidr

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}-ssh"
    Role = each.key
  }
}

resource "aws_vpc_security_group_ingress_rule" "role_ports" {
  for_each = local.vm_ingress_ports

  security_group_id = aws_security_group.instance[each.value.name].id
  description       = "Port ${each.value.port} for ${each.value.name} from allowed CIDR"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = var.allowed_ssh_cidr

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}"
    Role = each.value.name
  }
}

resource "aws_vpc_security_group_egress_rule" "all" {
  for_each = local.vms

  security_group_id = aws_security_group.instance[each.key].id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}-egress"
    Role = each.key
  }
}

# Allow Jenkins to reach SonarQube on port 9000 within the VPC (CI scan stage).
resource "aws_vpc_security_group_ingress_rule" "sonarqube_from_jenkins" {
  count = contains(keys(local.vms), "sonarqube") && contains(keys(local.vms), "jenkins") ? 1 : 0

  security_group_id            = aws_security_group.instance["sonarqube"].id
  description                  = "SonarQube from Jenkins SG for CI scans"
  ip_protocol                  = "tcp"
  from_port                    = 9000
  to_port                      = 9000
  referenced_security_group_id = aws_security_group.instance["jenkins"].id

  tags = {
    Name = "${var.project_name}-${var.environment}-sonarqube-from-jenkins"
    Role = "sonarqube"
  }
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "instance" {
  name_prefix        = "${var.project_name}-${var.environment}-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "EC2 instance role for ${var.project_name} (${var.environment})"

  tags = {
    Name = "${var.project_name}-${var.environment}-instance-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name_prefix = "${var.project_name}-${var.environment}-"
  role        = aws_iam_role.instance.name

  tags = {
    Name = "${var.project_name}-${var.environment}-instance-profile"
  }
}
