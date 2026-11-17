mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"] }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_resource "aws_ssm_document" {
    defaults = { latest_version = "1" }
  }
}

variables {
  aws_account_id            = "123456789012"
  free_tier_confirmed       = true
  instance_type             = "c7i-flex.large"
  root_volume_size_gib      = 30
  enable_frontend           = true
  frontend_api_mode         = "live"
  frontend_source_dir       = "../frontend/tests/fixtures/frontend"
  web_ingress_cidrs         = ["0.0.0.0/0"]
  enable_ecs                = true
  enable_database           = false
  enable_operating_schedule = false
  gateway_image             = "example.com/gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  service_image             = "example.com/service@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
}

run "ai_disabled_by_default" {
  command = plan
  assert {
    condition     = length(aws_s3_object.ai_model) == 0 && length(aws_ssm_association.ai_model) == 0 && length(aws_ecs_task_definition.apps[0].volume) == 0 && length(jsondecode(aws_ecs_task_definition.apps[0].container_definitions)[0].mountPoints) == 0
    error_message = "AI preparation must not change the default deployment."
  }
}

run "live_ai_uses_verified_read_only_model_and_ssm_secret" {
  command = plan
  variables {
    ai_model_archive_path     = "tests/fixtures/model-plan-placeholder.txt"
    enable_ai_live            = true
    service_secret_parameters = { QWEN_API_KEY = "arn:aws:ssm:ap-northeast-2:123456789012:parameter/openstudy-prod/apps/qwen-api-key" }
  }
  assert {
    condition = alltrue([
      for key, value in local.ai_environment :
      contains(jsondecode(aws_ecs_task_definition.apps[0].container_definitions)[0].environment, { name = key, value = value })
    ]) && local.ai_environment.OPENSTUDY_AI_MODEL_MODE == "live" && local.ai_environment.DOMAINLENS_MODEL_MODE == "live"
    error_message = "Both model paths must call live Qwen, with the verified ONNX directory."
  }
  assert {
    condition = jsondecode(aws_ecs_task_definition.apps[0].container_definitions)[0].mountPoints == [{
      sourceVolume = "ai-model", containerPath = local.ai_model_path, readOnly = true
    }] && one(aws_ecs_task_definition.apps[0].volume).host_path == local.ai_model_path
    error_message = "Mount the immutable verified host directory read-only in the Service container."
  }
  assert {
    condition = contains(jsondecode(aws_ecs_task_definition.apps[0].container_definitions)[0].secrets, {
      name = "QWEN_API_KEY", valueFrom = var.service_secret_parameters.QWEN_API_KEY
    }) && !contains([for entry in jsondecode(aws_ecs_task_definition.apps[0].container_definitions)[0].environment : entry.name], "QWEN_API_KEY")
    error_message = "Qwen credentials must be injected as an SSM reference only."
  }
  assert {
    condition     = aws_s3_object.ai_model[0].server_side_encryption == "AES256" && aws_s3_bucket_public_access_block.frontend_artifacts[0].block_public_policy && jsondecode(aws_iam_role_policy.ai_model[0].policy).Statement[0].Resource == "arn:aws:s3:::${aws_s3_object.ai_model[0].bucket}/${local.ai_model_key}"
    error_message = "Store the archive privately and grant host access to its exact object only."
  }
  assert {
    condition     = strcontains(aws_ssm_document.ai_model[0].content, local.ai_model_sha256) && strcontains(aws_ssm_document.ai_model[0].content, "sha256sum -c -") && strcontains(aws_ssm_document.ai_model[0].content, "--destination") && aws_ssm_association.ai_model[0].wait_for_success_timeout_seconds == 600
    error_message = "Verify the archive and model before publishing the directory and reporting SSM success."
  }
}

run "reject_arm_host_for_intel_model" {
  command = plan
  variables {
    instance_type         = "t4g.medium"
    ai_model_archive_path = "tests/fixtures/model-plan-placeholder.txt"
  }
  expect_failures = [terraform_data.ai_model_validation]
}

run "reject_live_without_key" {
  command = plan
  variables {
    ai_model_archive_path = "tests/fixtures/model-plan-placeholder.txt"
    enable_ai_live        = true
  }
  expect_failures = [var.enable_ai_live]
}

run "reject_live_without_model" {
  command = plan
  variables {
    enable_ai_live            = true
    service_secret_parameters = { QWEN_API_KEY = "arn:aws:ssm:ap-northeast-2:123456789012:parameter/openstudy-prod/apps/qwen-api-key" }
  }
  expect_failures = [var.enable_ai_live]
}

run "reject_plaintext_qwen_key" {
  command = plan
  variables {
    service_environment = { QWEN_API_KEY = "test-placeholder" }
  }
  expect_failures = [aws_ecs_cluster.apps]
}

run "reject_managed_embedding_directory_override" {
  command = plan
  variables {
    ai_model_archive_path = "tests/fixtures/model-plan-placeholder.txt"
    service_environment   = { DOMAINLENS_EMBEDDING_DIRECTORY = "/wrong-directory" }
  }
  expect_failures = [aws_ecs_cluster.apps]
}

run "reject_secret_playback_override" {
  command = plan
  variables {
    ai_model_archive_path = "tests/fixtures/model-plan-placeholder.txt"
    enable_ai_live        = true
    service_secret_parameters = {
      QWEN_API_KEY          = "arn:aws:ssm:ap-northeast-2:123456789012:parameter/openstudy-prod/apps/qwen-api-key"
      DOMAINLENS_MODEL_MODE = "arn:aws:ssm:ap-northeast-2:123456789012:parameter/openstudy-prod/apps/mode"
    }
  }
  expect_failures = [aws_ecs_cluster.apps]
}
