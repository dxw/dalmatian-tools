#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  load_all_functions
  # Migration moves tmp/ under APP_ROOT, so point it at the sandbox rather
  # than the real checkout
  export APP_ROOT="$SANDBOX/app"
  mkdir -p "$APP_ROOT/tmp"
  # setup_sandbox pre-creates and selects an installation; migration tests
  # need neither to exist yet
  unset DALMATIAN_INSTALLATION
  rm -rf "$CONFIG_INSTALLATIONS_DIR"
}

@test "migrate_legacy_installation does nothing with no configuration" {
  run migrate_legacy_installation
  assert_success
  [ ! -e "$CONFIG_INSTALLATIONS_DIR" ]
  [ ! -e "$CONFIG_INSTALLATIONS_JSON_FILE" ]
}

@test "migrate_legacy_installation does nothing when installations.json exists and no legacy files do" {
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run migrate_legacy_installation
  assert_success
  run jq -r '.default' "$CONFIG_INSTALLATIONS_JSON_FILE"
  assert_output "example-project"
}

@test "migrate_legacy_installation moves the legacy layout under the project name" {
  legacy_config_sandbox

  run migrate_legacy_installation
  assert_success

  [ -f "$CONFIG_INSTALLATIONS_DIR/example-project/setup.json" ]
  [ -f "$CONFIG_INSTALLATIONS_DIR/example-project/dalmatian-sso.config" ]
  [ -f "$CONFIG_INSTALLATIONS_DIR/example-project/account-bootstrap-backend.vars" ]
  [ -f "$CONFIG_INSTALLATIONS_DIR/example-project/infrastructure-backend.vars" ]
  [ -f "$CONFIG_INSTALLATIONS_DIR/example-project/.cache/tfvars-paths.json" ]
  [ -d "$CONFIG_INSTALLATIONS_DIR/example-project/.cache/tfvars" ]

  [ ! -e "$CONFIG_DIR/setup.json" ]
  [ ! -e "$CONFIG_DIR/dalmatian-sso.config" ]
  [ ! -e "$CONFIG_DIR/account-bootstrap-backend.vars" ]
  [ ! -e "$CONFIG_DIR/infrastructure-backend.vars" ]
  [ ! -e "$CONFIG_DIR/.cache" ]
}

@test "migrate_legacy_installation records the migrated installation as the default" {
  legacy_config_sandbox

  run migrate_legacy_installation
  assert_success
  run jq -r '.default' "$CONFIG_INSTALLATIONS_JSON_FILE"
  assert_output "example-project"
}

@test "migrate_legacy_installation logs the installation it created" {
  legacy_config_sandbox

  run migrate_legacy_installation
  assert_success
  assert_output_contains "installation 'example-project'"
}

@test "migrate_legacy_installation is silent in quiet mode" {
  legacy_config_sandbox
  export QUIET_MODE=1

  run migrate_legacy_installation
  assert_success
  assert_output ""
}

@test "migrate_legacy_installation leaves machine-wide files at the root" {
  legacy_config_sandbox
  printf '%s\n' '{"version": "v2"}' > "$CONFIG_DIR/version.json"
  printf '%s\n' '{"complete_status": "1"}' > "$CONFIG_DIR/update-check.json"
  printf 'x\n' > "$CONFIG_DIR/credentials.json.enc"

  run migrate_legacy_installation
  assert_success
  [ -f "$CONFIG_DIR/version.json" ]
  [ -f "$CONFIG_DIR/update-check.json" ]
  [ -f "$CONFIG_DIR/credentials.json.enc" ]
}

@test "migrate_legacy_installation moves the terraform working copies into tmp/<name>" {
  legacy_config_sandbox
  mkdir -p "$APP_ROOT/tmp/terraform-dxw-dalmatian-account-bootstrap/.terraform"
  mkdir -p "$APP_ROOT/tmp/terraform-dxw-dalmatian-infrastructure/.terraform"
  mkdir -p "$APP_ROOT/tmp/service-environment-files"
  printf 'x\n' > "$APP_ROOT/tmp/service-environment-files/example.env"

  run migrate_legacy_installation
  assert_success
  [ -d "$APP_ROOT/tmp/example-project/terraform-dxw-dalmatian-account-bootstrap/.terraform" ]
  [ -d "$APP_ROOT/tmp/example-project/terraform-dxw-dalmatian-infrastructure/.terraform" ]
  [ -f "$APP_ROOT/tmp/example-project/service-environment-files/example.env" ]
  [ ! -e "$APP_ROOT/tmp/terraform-dxw-dalmatian-account-bootstrap" ]
  [ ! -e "$APP_ROOT/tmp/terraform-dxw-dalmatian-infrastructure" ]
  [ ! -e "$APP_ROOT/tmp/service-environment-files" ]
}

@test "migrate_legacy_installation copes with no tmp directory at all" {
  legacy_config_sandbox
  rm -rf "$APP_ROOT/tmp"

  run migrate_legacy_installation
  assert_success
  [ -f "$CONFIG_INSTALLATIONS_DIR/example-project/setup.json" ]
  [ ! -e "$APP_ROOT/tmp" ]
}

@test "migrate_legacy_installation falls back to 'default' when project_name is empty" {
  legacy_config_sandbox
  printf '%s\n' '{"project_name": "", "aws_sso": {"start_url": "https://example.awsapps.com/start"}}' > "$CONFIG_DIR/setup.json"

  run migrate_legacy_installation
  assert_success
  [ -f "$CONFIG_INSTALLATIONS_DIR/default/setup.json" ]
  run jq -r '.default' "$CONFIG_INSTALLATIONS_JSON_FILE"
  assert_output "default"
}

@test "migrate_legacy_installation falls back to 'default' when project_name is missing" {
  legacy_config_sandbox
  printf '%s\n' '{"aws_sso": {"start_url": "https://example.awsapps.com/start"}}' > "$CONFIG_DIR/setup.json"

  run migrate_legacy_installation
  assert_success
  [ -f "$CONFIG_INSTALLATIONS_DIR/default/setup.json" ]
}

@test "migrate_legacy_installation falls back to 'default' when project_name is not a safe name" {
  legacy_config_sandbox
  printf '%s\n' '{"project_name": "Example Project"}' > "$CONFIG_DIR/setup.json"

  run migrate_legacy_installation
  assert_success
  [ -f "$CONFIG_INSTALLATIONS_DIR/default/setup.json" ]
}

@test "migrate_legacy_installation falls back to 'default' on unparseable setup.json" {
  legacy_config_sandbox
  printf '%s\n' 'not json' > "$CONFIG_DIR/setup.json"

  run migrate_legacy_installation
  assert_success
  [ -f "$CONFIG_INSTALLATIONS_DIR/default/setup.json" ]
}

@test "migrate_legacy_installation skips legacy items that do not exist" {
  install_fixture setup.json "$CONFIG_DIR/setup.json"

  run migrate_legacy_installation
  assert_success
  [ -f "$CONFIG_INSTALLATIONS_DIR/example-project/setup.json" ]
  [ ! -e "$CONFIG_INSTALLATIONS_DIR/example-project/dalmatian-sso.config" ]
}

@test "migrate_legacy_installation resumes an interrupted migration" {
  legacy_config_sandbox
  # Simulate a run that moved the sso config and died before setup.json and
  # installations.json were written
  mkdir -p "$CONFIG_INSTALLATIONS_DIR/example-project"
  mv "$CONFIG_DIR/dalmatian-sso.config" "$CONFIG_INSTALLATIONS_DIR/example-project/dalmatian-sso.config"

  run migrate_legacy_installation
  assert_success
  [ -f "$CONFIG_INSTALLATIONS_DIR/example-project/setup.json" ]
  [ -f "$CONFIG_INSTALLATIONS_DIR/example-project/dalmatian-sso.config" ]
  run jq -r '.default' "$CONFIG_INSTALLATIONS_JSON_FILE"
  assert_output "example-project"
}

@test "migrate_legacy_installation refuses when installations.json already exists alongside legacy files" {
  legacy_config_sandbox
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run --separate-stderr migrate_legacy_installation
  assert_failure 1
  assert_stderr_contains "Found both a legacy Dalmatian configuration and $CONFIG_INSTALLATIONS_JSON_FILE"
  assert_stderr_contains "$CONFIG_DIR/setup.json"
  assert_stderr_contains "$CONFIG_DIR/dalmatian-sso.config"
  [ -f "$CONFIG_DIR/setup.json" ]
}

@test "migrate_legacy_installation refuses to overwrite an occupied destination" {
  legacy_config_sandbox
  mkdir -p "$CONFIG_INSTALLATIONS_DIR/example-project"
  printf 'keep\n' > "$CONFIG_INSTALLATIONS_DIR/example-project/dalmatian-sso.config"

  run --separate-stderr migrate_legacy_installation
  assert_failure 1
  assert_stderr_contains "already exists"
  run cat "$CONFIG_INSTALLATIONS_DIR/example-project/dalmatian-sso.config"
  assert_output "keep"
  [ -f "$CONFIG_DIR/dalmatian-sso.config" ]
}

@test "migrate_legacy_installation refuses to overwrite an occupied tmp destination and leaves the config untouched" {
  legacy_config_sandbox
  mkdir -p "$APP_ROOT/tmp/terraform-dxw-dalmatian-infrastructure"
  mkdir -p "$APP_ROOT/tmp/example-project/terraform-dxw-dalmatian-infrastructure"

  run --separate-stderr migrate_legacy_installation
  assert_failure 1
  assert_stderr_contains "already exists"
  [ -f "$CONFIG_DIR/setup.json" ]
  [ -f "$CONFIG_DIR/dalmatian-sso.config" ]
  [ ! -e "$CONFIG_INSTALLATIONS_JSON_FILE" ]
}
