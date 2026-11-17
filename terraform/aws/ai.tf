variable "ai_model_archive_path" {
  description = "Local models.zip for the pinned AMD64 embedding model. Null leaves model deployment disabled."
  type        = string
  default     = null
  validation {
    condition     = var.ai_model_archive_path == null ? true : fileexists(var.ai_model_archive_path)
    error_message = "ai_model_archive_path must name an existing local models.zip."
  }
}

variable "enable_ai_live" {
  description = "Call Qwen using QWEN_API_KEY from service_secret_parameters; requires the embedding model."
  type        = bool
  default     = false
  validation {
    condition = !var.enable_ai_live || (
      var.enable_ecs && var.ai_model_archive_path != null && contains(keys(var.service_secret_parameters), "QWEN_API_KEY")
    )
    error_message = "Live AI requires ECS, ai_model_archive_path, and a QWEN_API_KEY SSM SecureString ARN."
  }
}

locals {
  ai_model_enabled = var.ai_model_archive_path != null
  ai_model_sha256  = local.ai_model_enabled ? try(filesha256(var.ai_model_archive_path), "invalid") : ""
  ai_model_key     = "models/koen-e5-tiny-q8/${local.ai_model_sha256}.zip"
  ai_model_path    = "/opt/openstudy/models/${local.ai_model_sha256}/koen-e5-tiny-q8"
  ai_environment = merge(local.ai_model_enabled ? {
    DOMAINLENS_EMBEDDING_PROVIDER  = "onnx"
    DOMAINLENS_EMBEDDING_DIRECTORY = local.ai_model_path
    } : {}, var.enable_ai_live ? {
    OPENSTUDY_AI_MODEL_MODE = "live"
    DOMAINLENS_MODEL_MODE   = "live"
    QWEN_BASE_URL           = "https://token-plan.maas.qwencloudapi.com/compatible-mode/v1"
    QWEN_MODEL              = "qwen3.8-flash"
  } : {})
}

# Runs before S3 upload. No credentials or LLM calls are needed to verify the archive.
resource "terraform_data" "ai_model_validation" {
  count = local.ai_model_enabled ? 1 : 0
  triggers_replace = {
    archive_sha256   = local.ai_model_sha256
    installer_sha256 = filesha256("${path.module}/../../scripts/install-ai-model.py")
  }
  lifecycle {
    precondition {
      condition     = var.enable_ecs && var.enable_frontend && local.architecture == "x86_64"
      error_message = "The supplied embedding model requires ECS, the private artifact bucket, and an AMD64 host."
    }
  }
  provisioner "local-exec" {
    command = "python3 \"$AI_MODEL_INSTALLER\" --archive \"$AI_MODEL_ARCHIVE\" --verify-only"
    environment = {
      AI_MODEL_INSTALLER = abspath("${path.module}/../../scripts/install-ai-model.py")
      AI_MODEL_ARCHIVE   = abspath(var.ai_model_archive_path)
    }
  }
}

resource "aws_s3_object" "ai_model" {
  count                  = local.ai_model_enabled ? 1 : 0
  bucket                 = try(aws_s3_bucket.frontend_artifacts[0].bucket, "")
  key                    = local.ai_model_key
  source                 = var.ai_model_archive_path
  source_hash            = local.ai_model_sha256
  server_side_encryption = "AES256"
  content_type           = "application/zip"
  depends_on = [
    terraform_data.ai_model_validation,
    aws_s3_bucket_public_access_block.frontend_artifacts,
    aws_s3_bucket_server_side_encryption_configuration.frontend_artifacts,
    aws_s3_bucket_policy.frontend_artifacts,
  ]
}

resource "aws_iam_role_policy" "ai_model" {
  count = local.ai_model_enabled ? 1 : 0
  name  = "read-ai-model"
  role  = aws_iam_role.server.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "arn:aws:s3:::${aws_s3_object.ai_model[0].bucket}/${local.ai_model_key}"
    }]
  })
}

resource "aws_ssm_document" "ai_model" {
  count           = local.ai_model_enabled ? 1 : 0
  name            = "${var.name_prefix}-install-ai-model"
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Verify and atomically install the pinned AMD64 embedding model."
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "installModel"
      inputs = {
        timeoutSeconds = "600"
        runCommand = [
          "set -eu",
          "test \"$(uname -m)\" = x86_64",
          "model_tmp=$(mktemp -d)",
          "trap 'rm -rf \"$model_tmp\"' EXIT",
          "printf '%s' '${filebase64("${path.module}/../../scripts/install-ai-model.py")}' | base64 -d > \"$model_tmp/install.py\"",
          "aws s3 cp 's3://${aws_s3_object.ai_model[0].bucket}/${local.ai_model_key}' \"$model_tmp/models.zip\" --region '${var.aws_region}' --only-show-errors",
          "printf '%s  %s\\n' '${local.ai_model_sha256}' \"$model_tmp/models.zip\" | sha256sum -c -",
          "install -d -m 0755 /opt/openstudy/models '/opt/openstudy/models/${local.ai_model_sha256}'",
          "python3 \"$model_tmp/install.py\" --archive \"$model_tmp/models.zip\" --destination '${local.ai_model_path}'",
        ]
      }
    }]
  })
}

resource "aws_ssm_association" "ai_model" {
  count                            = local.ai_model_enabled ? 1 : 0
  name                             = aws_ssm_document.ai_model[0].name
  association_name                 = "${var.name_prefix}-install-ai-model"
  document_version                 = aws_ssm_document.ai_model[0].latest_version
  wait_for_success_timeout_seconds = 600
  targets {
    key    = "InstanceIds"
    values = [aws_instance.server.id]
  }
  lifecycle {
    replace_triggered_by = [aws_ssm_document.ai_model[0].content, aws_instance.server.id]
  }
  depends_on = [aws_ssm_association.server, aws_iam_role_policy.ai_model, aws_iam_role_policy.server_configuration]
}
