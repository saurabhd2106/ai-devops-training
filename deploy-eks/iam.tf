data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cluster" {
  name_prefix        = "${local.cluster_name}-cluster-"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json
  description        = "EKS cluster role for ${local.cluster_name}"
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "node" {
  name_prefix        = "${local.cluster_name}-node-"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json
  description        = "EKS managed node role for ${local.cluster_name}"
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryPullOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.node.name
}

# CI access entry: grant Jenkins/EC2 instance role cluster admin (API access mode)
resource "aws_eks_access_entry" "ci" {
  count = var.ci_principal_arn != null ? 1 : 0

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.ci_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "ci_admin" {
  count = var.ci_principal_arn != null ? 1 : 0

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.ci_principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.ci]
}

# CI deploy policy: attach to Jenkins/EC2 role via deploy-vm eks_deploy_policy_arn
data "aws_iam_policy_document" "ci_deploy" {
  statement {
    sid    = "EKSDescribeAndAccess"
    effect = "Allow"
    actions = [
      "eks:DescribeCluster",
      "eks:AccessKubernetesApi",
    ]
    resources = [aws_eks_cluster.main.arn]
  }

  statement {
    sid    = "EKSListClusters"
    effect = "Allow"
    actions = [
      "eks:ListClusters",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ci_deploy" {
  name        = "${local.cluster_name}-ci-deploy"
  description = "Allow CI (Jenkins) to describe and call the Kubernetes API on ${local.cluster_name}"
  policy      = data.aws_iam_policy_document.ci_deploy.json

  tags = {
    Name = "${local.cluster_name}-ci-deploy"
  }
}
