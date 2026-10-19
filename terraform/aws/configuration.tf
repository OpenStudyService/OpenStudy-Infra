resource "aws_ssm_document" "server" {
  name            = "${var.name_prefix}-configure-server"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Apply the OpenStudy server configuration managed by Terraform."
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "configureServer"
      inputs = {
        timeoutSeconds = "1800"
        runCommand = [
          "set -eu",
          # Wait for the first boot to finish, including the failed-bootstrap case.
          "cloud-init status --wait || true",
          "install -d -m 0700 /var/lib/openstudy-bootstrap",
          "cat > /var/lib/openstudy-bootstrap/apply.sh <<'OPENSTUDY_BOOTSTRAP'\n${local.user_data}\nOPENSTUDY_BOOTSTRAP",
          "chmod 0700 /var/lib/openstudy-bootstrap/apply.sh",
          "bash /var/lib/openstudy-bootstrap/apply.sh",
        ]
      }
    }]
  })
}

resource "aws_iam_role_policy" "server_configuration" {
  name = "server-configuration"
  role = aws_iam_role.server.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:DescribeAssociation",
          "ssm:ListAssociations",
          "ssm:ListInstanceAssociations",
          "ssm:UpdateAssociationStatus",
          "ssm:UpdateInstanceAssociationStatus",
          "ssm:PutComplianceItems",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetDocument", "ssm:DescribeDocument"]
        Resource = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:document/${aws_ssm_document.server.name}"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_ssm_association" "server" {
  name                             = aws_ssm_document.server.name
  association_name                 = "${var.name_prefix}-configure-server"
  document_version                 = aws_ssm_document.server.latest_version
  wait_for_success_timeout_seconds = 1800

  targets {
    key    = "InstanceIds"
    values = [aws_instance.server.id]
  }

  # This provider waits for success only on creation, so replace the association
  # for each document change. The EC2 instance is kept in place.
  lifecycle {
    replace_triggered_by = [aws_ssm_document.server.content]
  }

  depends_on = [aws_iam_role_policy.server_configuration]
}
