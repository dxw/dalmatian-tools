#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  # bin/dalmatian exports these from the selected installation
  export TMP_DIR="$SANDBOX/app/tmp/$DALMATIAN_INSTALLATION"
  export TMP_ACCOUNT_BOOTSTRAP_TERRAFORM_DIR="$TMP_DIR/terraform-dxw-dalmatian-account-bootstrap"
  export TMP_INFRASTRUCTURE_TERRAFORM_DIR="$TMP_DIR/terraform-dxw-dalmatian-infrastructure"
  export CONFIG_ACCOUNT_BOOTSTRAP_BACKEND_VARS_FILE="$CONFIG_INSTALLATION_DIR/account-bootstrap-backend.vars"
  export CONFIG_INFRASTRUCTURE_BACKEND_VARS_FILE="$CONFIG_INSTALLATION_DIR/infrastructure-backend.vars"
}

@test "run-terraform-command runs terraform in the infrastructure working copy" {
  mkdir -p "$TMP_INFRASTRUCTURE_TERRAFORM_DIR"
  stub_response terraform-chdir "default"

  run run_command bin/terraform-dependencies/v2/run-terraform-command -c "workspace list" -i
  assert_success
  assert_stub_called_with "workspace list"
}

# A missing working copy used to fall through to grealpath, tfenv and
# `terraform -chdir=` in turn, each failing with its own unrelated message
@test "run-terraform-command -i fails clearly when the infrastructure working copy is missing" {
  run --separate-stderr run_command bin/terraform-dependencies/v2/run-terraform-command -c "workspace list" -i
  assert_failure 1
  assert_stderr_contains "$TMP_INFRASTRUCTURE_TERRAFORM_DIR"
  assert_stderr_contains "dalmatian terraform-dependencies clone"
  refute_stub_called_with "terraform"
}

@test "run-terraform-command -a fails clearly when the account bootstrap working copy is missing" {
  run --separate-stderr run_command bin/terraform-dependencies/v2/run-terraform-command -c "workspace list" -a
  assert_failure 1
  assert_stderr_contains "$TMP_ACCOUNT_BOOTSTRAP_TERRAFORM_DIR"
  assert_stderr_contains "dalmatian terraform-dependencies clone"
  refute_stub_called_with "terraform"
}

@test "account bootstrap creates a Terraform override for the original project's tfvars bucket" {
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  jq '.terraform_project_name = "different-resource-project"' "$CONFIG_SETUP_JSON_FILE" > "$SANDBOX/override.json"
  mv "$SANDBOX/override.json" "$CONFIG_SETUP_JSON_FILE"
  mkdir -p "$TMP_ACCOUNT_BOOTSTRAP_TERRAFORM_DIR"
  stub_response terraform-chdir "default"
  run run_command bin/terraform-dependencies/v2/run-terraform-command -c "workspace list" -a
  assert_success
  local expected_hash
  expected_hash="$(printf '%s' example-project | sha1sum | head -c 6)"
  run cat "$TMP_ACCOUNT_BOOTSTRAP_TERRAFORM_DIR/dalmatian_tfvars_override.tf"
  assert_output_contains 'module "aws_tfvars_s3"'
  assert_output_contains "project_name = \"$expected_hash\""
}
