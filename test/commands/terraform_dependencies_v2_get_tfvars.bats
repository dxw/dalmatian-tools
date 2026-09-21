#!/usr/bin/env bats

load ../test_helper

# get-tfvars downloads the shared tfvars files from the project's tfvars
# bucket. On a brand-new project that bucket does not exist yet (account
# bootstrap creates it), so the global files have to come from the templates
# under data/tfvars-templates instead. These tests cover that first-run path;
# the download path needs a long chain of stubbed S3 responses and is left to
# the real bucket.
setup() {
  setup_sandbox
  use_stubs
  stub_cli
  export QUIET_MODE=1
  export EDITOR=true
  export CONFIG_CACHE_DIR="$CONFIG_INSTALLATION_DIR/.cache"
  export CONFIG_TFVARS_DIR="$CONFIG_CACHE_DIR/tfvars"
  export CONFIG_TFVARS_PATHS_FILE="$CONFIG_CACHE_DIR/tfvars-paths.json"
  export CONFIG_GLOBAL_ACCOUNT_BOOSTRAP_TFVARS_FILE="000-global-account-bootstrap.tfvars"
  export CONFIG_GLOBAL_INFRASTRUCTURE_TFVARS_FILE="000-global-infrastructure.tfvars"
  cat > "$CONFIG_SETUP_JSON_FILE" <<'JSON'
{
  "project_name": "example-project",
  "default_region": "eu-west-2"
}
JSON
  # The tfvars bucket does not exist yet
  stub_exit aws-s3api-head_bucket 254
  stub_response aws-s3api-head_bucket "An error occurred (404) when calling the HeadBucket operation: Not Found"
}

@test "get-tfvars seeds the global tfvars from the templates when the bucket does not exist" {
  run run_command bin/terraform-dependencies/v2/get-tfvars
  assert_success
  [ -f "$CONFIG_TFVARS_DIR/000-global-account-bootstrap.tfvars" ]
  [ -f "$CONFIG_TFVARS_DIR/000-global-infrastructure.tfvars" ]
  cmp -s "$DALMATIAN_ROOT/data/tfvars-templates/account-bootstrap.tfvars" "$CONFIG_TFVARS_DIR/000-global-account-bootstrap.tfvars"
  cmp -s "$DALMATIAN_ROOT/data/tfvars-templates/infrastructure.tfvars" "$CONFIG_TFVARS_DIR/000-global-infrastructure.tfvars"
}

@test "get-tfvars writes the default tfvars from setup.json when the bucket does not exist" {
  run run_command bin/terraform-dependencies/v2/get-tfvars
  assert_success
  run cat "$CONFIG_TFVARS_DIR/000-terraform.tfvars"
  assert_line 0 'project_name="example-project"'
  assert_line 1 'aws_region="eu-west-2"'
}

@test "get-tfvars records the global files in tfvars-paths.json" {
  run run_command bin/terraform-dependencies/v2/get-tfvars
  assert_success
  run jq -r '."global-account-bootstrap".key, ."global-infrastructure".key, .terraform.key' "$CONFIG_TFVARS_PATHS_FILE"
  assert_line 0 "000-global-account-bootstrap.tfvars"
  assert_line 1 "000-global-infrastructure.tfvars"
  assert_line 2 "000-terraform.tfvars"
}

@test "get-tfvars never replaces an existing global tfvars file with a template" {
  mkdir -p "$CONFIG_TFVARS_DIR"
  printf 'edited = true\n' > "$CONFIG_TFVARS_DIR/000-global-account-bootstrap.tfvars"

  run run_command bin/terraform-dependencies/v2/get-tfvars
  assert_success
  run cat "$CONFIG_TFVARS_DIR/000-global-account-bootstrap.tfvars"
  assert_output "edited = true"
}

@test "get-tfvars stops when the bucket check fails for a reason other than a missing bucket" {
  mkdir -p "$CONFIG_TFVARS_DIR"
  printf 'edited = true\n' > "$CONFIG_TFVARS_DIR/000-global-infrastructure.tfvars"
  stub_response aws-s3api-head_bucket "The SSO session associated with this profile has expired or is otherwise invalid."

  run --separate-stderr run_command bin/terraform-dependencies/v2/get-tfvars
  assert_failure 1
  assert_stderr_contains "Could not check the tfvars bucket"
  assert_stderr_contains "SSO session"
  run cat "$CONFIG_TFVARS_DIR/000-global-infrastructure.tfvars"
  assert_output "edited = true"
}

@test "get-tfvars does not download anything when the bucket does not exist" {
  run run_command bin/terraform-dependencies/v2/get-tfvars
  assert_success
  refute_stub_called_with "aws s3 cp"
}
