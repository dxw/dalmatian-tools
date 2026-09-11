#!/usr/bin/env bats
#
# shellcheck disable=SC2030,SC2031
# Each @test block is a shellcheck-visible function, so `export FOO=bar`
# inside one looks like a subshell-local change that could be "lost" by the
# time a later @test reads it. bats runs each @test as its own process
# invocation anyway (via run_command's `bash -c`), so the exports here are
# read back within the same test that set them -- shellcheck just can't see
# that the boundary is a test, not a subshell escape.

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  stub_cli
  export QUIET_MODE=1
  export APP_ROOT="$DALMATIAN_TEST_APP_ROOT"
  mkdir -p "$APP_ROOT/tmp"
  unset DALMATIAN_INSTALLATION
  rm -rf "$CONFIG_INSTALLATIONS_DIR"
  # Nine prompts; a blank line accepts each default
  printf '\n\n\n\n\n\n\n\n\n' > "$SANDBOX/answers"
  # A complete setup file, as a teammate would hand over
  cat > "$SANDBOX/setup.json" <<'JSON'
{
  "project_name": "example-project",
  "default_region": "eu-west-2",
  "main_dalmatian_account_id": "123456789012",
  "aws_sso": {
    "start_url": "https://example.awsapps.com/start",
    "region": "eu-west-2",
    "registration_scopes": "sso:account:access",
    "default_admin_role_name": "AdministratorAccess"
  },
  "backend": {
    "s3": {
      "bucket_name": "example-tfstate",
      "bucket_region": "eu-west-2"
    }
  }
}
JSON
}

run_setup() {
  run run_command bin/configure-commands/v2/setup "$@" < "$SANDBOX/answers"
}

@test "setup -h prints usage including -n" {
  run --separate-stderr run_command bin/configure-commands/v2/setup -h
  assert_failure 1
  assert_stderr_contains "Usage: dalmatian setup"
  assert_output_contains "-n <installation_name>"
}

@test "setup -f names the installation after project_name" {
  run_setup -f "$SANDBOX/setup.json"
  assert_success
  [ -f "$CONFIG_INSTALLATIONS_DIR/example-project/setup.json" ]
  [ -f "$CONFIG_INSTALLATIONS_DIR/example-project/account-bootstrap-backend.vars" ]
  [ -f "$CONFIG_INSTALLATIONS_DIR/example-project/infrastructure-backend.vars" ]
  [ -d "$CONFIG_INSTALLATIONS_DIR/example-project/.cache" ]
  [ ! -e "$CONFIG_DIR/setup.json" ]
  run jq -r '.project_name' "$CONFIG_INSTALLATIONS_DIR/example-project/setup.json"
  assert_output "example-project"
}

@test "setup -n overrides the installation name" {
  run_setup -f "$SANDBOX/setup.json" -n client-a
  assert_success
  [ -f "$CONFIG_INSTALLATIONS_DIR/client-a/setup.json" ]
  [ ! -e "$CONFIG_INSTALLATIONS_DIR/example-project" ]
  run jq -r '.project_name' "$CONFIG_INSTALLATIONS_DIR/client-a/setup.json"
  assert_output "example-project"
}

@test "setup rejects an invalid -n before writing anything" {
  run --separate-stderr run_command bin/configure-commands/v2/setup -f "$SANDBOX/setup.json" -n "Bad Name" < "$SANDBOX/answers"
  assert_failure 1
  assert_stderr_contains "'Bad Name' is not a valid installation name"
  [ ! -e "$CONFIG_INSTALLATIONS_DIR" ]
}

@test "setup records the first installation as the default" {
  run_setup -f "$SANDBOX/setup.json"
  assert_success
  run jq -r '.default' "$CONFIG_INSTALLATIONS_JSON_FILE"
  assert_output "example-project"
}

@test "setup leaves an existing default alone and prints the use command" {
  mkdir -p "$CONFIG_INSTALLATIONS_DIR/existing"
  printf '%s\n' '{"default": "existing"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"
  export QUIET_MODE=0

  run_setup -f "$SANDBOX/setup.json"
  assert_success
  run jq -r '.default' "$CONFIG_INSTALLATIONS_JSON_FILE"
  assert_output "existing"
}

@test "setup prints the use command when it is not the default" {
  mkdir -p "$CONFIG_INSTALLATIONS_DIR/existing"
  printf '%s\n' '{"default": "existing"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"
  export QUIET_MODE=0

  run_setup -f "$SANDBOX/setup.json"
  assert_success
  assert_output_contains "dalmatian installation use example-project"
}

@test "setup runs its child commands against the new installation" {
  run_setup -f "$SANDBOX/setup.json" -n client-a
  assert_success
  assert_stub_called_with "dalmatian aws generate-config"
  assert_stub_called_with "dalmatian aws account-init -i 123456789012 -r eu-west-2 -n dalmatian-main"
  # The stub records its environment as well as its arguments
  run grep -c 'DALMATIAN_INSTALLATION=client-a' "$DALMATIAN_STUB_ENV_LOG"
  assert_success
}

@test "setup writes the backend vars for the installation's bucket" {
  run_setup -f "$SANDBOX/setup.json"
  assert_success
  run grep -c 'bucket               = "example-tfstate"' "$CONFIG_INSTALLATIONS_DIR/example-project/infrastructure-backend.vars"
  assert_output "1"
}

@test "setup with no -f, -u or -n updates the current installation in place" {
  mkdir -p "$CONFIG_INSTALLATIONS_DIR/client-a"
  cp "$SANDBOX/setup.json" "$CONFIG_INSTALLATIONS_DIR/client-a/setup.json"
  printf '%s\n' '{"default": "client-a"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"
  export DALMATIAN_INSTALLATION=client-a

  run_setup
  assert_success
  [ -f "$CONFIG_INSTALLATIONS_DIR/client-a/setup.json" ]
  [ ! -e "$CONFIG_INSTALLATIONS_DIR/example-project" ]
}

@test "setup with no file prompts for the project name and uses it" {
  printf 'prompted-name\n\n\n\n\n\n\n\n\n' > "$SANDBOX/answers"

  run_setup
  assert_success
  [ -f "$CONFIG_INSTALLATIONS_DIR/prompted-name/setup.json" ]
  run jq -r '.project_name' "$CONFIG_INSTALLATIONS_DIR/prompted-name/setup.json"
  assert_output "prompted-name"
}

@test "setup refuses when the project name is not a valid installation name and -n is absent" {
  printf 'Bad Name\n' > "$SANDBOX/answers"

  run --separate-stderr run_command bin/configure-commands/v2/setup < "$SANDBOX/answers"
  assert_failure 1
  assert_stderr_contains "is not a valid installation name"
  assert_stderr_contains "-n"
}

@test "setup refuses to replace an existing installation's setup.json with the blank template" {
  mkdir -p "$CONFIG_INSTALLATIONS_DIR/example-project"
  cp "$SANDBOX/setup.json" "$CONFIG_INSTALLATIONS_DIR/example-project/setup.json"
  printf 'example-project\n' > "$SANDBOX/answers"

  run --separate-stderr run_command bin/configure-commands/v2/setup < "$SANDBOX/answers"
  assert_failure 1
  assert_stderr_contains "Installation 'example-project' already exists"
  assert_stderr_contains "dalmatian setup -n example-project"
  run jq -r '.main_dalmatian_account_id' "$CONFIG_INSTALLATIONS_DIR/example-project/setup.json"
  assert_output "123456789012"
}
