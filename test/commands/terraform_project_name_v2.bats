#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  stub_cli
  export QUIET_MODE=1
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  jq '.terraform_project_name = "resource-project"' "$CONFIG_SETUP_JSON_FILE" > "$SANDBOX/override.json"
  mv "$SANDBOX/override.json" "$CONFIG_SETUP_JSON_FILE"
  export CONFIG_TFVARS_DIR="$CONFIG_INSTALLATION_DIR/.cache/tfvars"
  export CONFIG_TFVARS_PATHS_FILE="$CONFIG_INSTALLATION_DIR/.cache/tfvars-paths.json"
  export CONFIG_GLOBAL_ACCOUNT_BOOSTRAP_TFVARS_FILE="000-global-account-bootstrap.tfvars"
  mkdir -p "$CONFIG_TFVARS_DIR"
  printf '{}\n' > "$CONFIG_TFVARS_PATHS_FILE"
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
}

@test "view-tfvars checks the original project's bucket" {
  stub_exit aws-s3api-head_object 1
  run run_command bin/terraform-dependencies/v2/view-tfvars -a example-account
  assert_success
  local expected_hash
  expected_hash="$(printf '%s' example-project | sha1sum | head -c 6)"
  assert_stub_called_with "head-object --bucket $expected_hash-tfvars --key 100-example-account.tfvars"
}

@test "set-tfvars checks the original project's bucket" {
  stub_exit aws-s3api-head_object 1
  printf 'n\nn\n' > "$SANDBOX/answers"
  run run_command bin/terraform-dependencies/v2/set-tfvars -a example-account < "$SANDBOX/answers"
  assert_success
  local expected_hash
  expected_hash="$(printf '%s' example-project | sha1sum | head -c 6)"
  assert_stub_called_with "head-object --bucket $expected_hash-tfvars --key 100-example-account.tfvars"
}

@test "set-global-tfvars checks the original project's bucket" {
  stub_exit aws-s3api-head_object 1
  run run_command bin/terraform-dependencies/v2/set-global-tfvars -a < /dev/null
  local expected_hash
  expected_hash="$(printf '%s' example-project | sha1sum | head -c 6)"
  assert_stub_called_with "head-object --bucket $expected_hash-tfvars --key 000-global-account-bootstrap.tfvars"
}

@test "run-scheduled-task searches the resource project's rules" {
  stub_response dalmatian-aws-run_command-p-example_account-events-list_rules '{"Rules":[]}'
  run run_command bin/service/v2/run-scheduled-task -i example-infra -e staging
  assert_failure 1
  assert_stub_called_with "events list-rules --name-prefix resource-project-example-infra-staging-"
}

@test "cloudtrail query targets the resource project's database and workgroup" {
  stub_exit dalmatian-aws-run_command 3
  run run_command bin/cloudtrail/v2/query -a 123456789012-eu-west-2-example-account -Q 'SELECT * FROM CLOUDTRAIL'
  assert_failure
  assert_stub_called_with "--query-string SELECT * FROM cloudtrail_logs_123456789012_resource_project_cloudtrail_cloudtrail --query-execution-context Database=resource_project_cloudtrail --work-group resource-project-cloudtrail"
}

@test "delete-default-resources invokes the resource project's Lambda" {
  stub_response dalmatian-terraform_dependencies-run_terraform_command "123456789012-eu-west-2-example-account"
  run run_command bin/deploy/v2/delete-default-resources -a 123456789012-eu-west-2-example-account
  assert_success
  assert_stub_called_with "lambda invoke --function-name resource-project-delete-default-resources"
}
