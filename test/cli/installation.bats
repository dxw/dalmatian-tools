#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  use_test_app_root
  login_sandbox
  # bin/dalmatian derives TMP_DIR from APP_ROOT, which use_test_app_root
  # points at the sandbox copy
  mkdir -p "$SANDBOX/app/tmp"
}

# Add a probe under both versions that prints the paths the dispatcher exported
add_env_probe() {
  local probe
  for probe in "$SANDBOX/app/bin/probe/v1/echo-env" "$SANDBOX/app/bin/probe/v2/echo-env"
  do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$DALMATIAN_INSTALLATION" "$CONFIG_SETUP_JSON_FILE" "$CONFIG_AWS_SSO_FILE" "${CONFIG_TFVARS_DIR-}" "${TMP_DIR-}"\n' > "$probe"
    chmod +x "$probe"
  done
}

@test "v1 follows the default installation" {
  add_env_probe
  unset DALMATIAN_INSTALLATION

  run "$TEST_DALMATIAN" probe echo-env
  assert_success
  assert_line 0 "example-project"
  assert_line 1 "$CONFIG_INSTALLATIONS_DIR/example-project/setup.json"
  assert_line 2 "$CONFIG_INSTALLATIONS_DIR/example-project/dalmatian-sso.config"
}

@test "v1 follows DALMATIAN_INSTALLATION over the default" {
  add_env_probe
  mkdir -p "$CONFIG_INSTALLATIONS_DIR/other"
  install_fixture setup.json "$CONFIG_INSTALLATIONS_DIR/other/setup.json"
  install_fixture dalmatian-sso.config "$CONFIG_INSTALLATIONS_DIR/other/dalmatian-sso.config"
  export DALMATIAN_INSTALLATION=other

  run "$TEST_DALMATIAN" probe echo-env
  assert_success
  assert_line 0 "other"
  assert_line 1 "$CONFIG_INSTALLATIONS_DIR/other/setup.json"
}

@test "v2 derives the cache and tmp paths from the installation" {
  add_env_probe
  run "$TEST_DALMATIAN" version -v 2 -s
  assert_success

  run "$TEST_DALMATIAN" probe echo-env
  assert_success
  assert_line 0 "example-project"
  assert_line 3 "$CONFIG_INSTALLATIONS_DIR/example-project/.cache/tfvars"
  assert_line 4 "$SANDBOX/app/tmp/example-project"
}

@test "v2 refuses to run with no installation configured" {
  unset DALMATIAN_INSTALLATION
  rm -f "$CONFIG_INSTALLATIONS_JSON_FILE"
  run "$TEST_DALMATIAN" version -v 2 -s
  assert_success

  run --separate-stderr "$TEST_DALMATIAN" probe echo-args
  assert_failure 1
  assert_stderr_contains "No Dalmatian installation is configured"
  assert_stderr_contains "dalmatian setup"
}

@test "v2 runs installation list with no installation configured" {
  unset DALMATIAN_INSTALLATION
  rm -rf "$CONFIG_INSTALLATIONS_DIR" "$CONFIG_INSTALLATIONS_JSON_FILE"
  run "$TEST_DALMATIAN" version -v 2 -s
  assert_success

  run "$TEST_DALMATIAN" installation list
  assert_success
}

@test "v2 reaches setup with no installation configured" {
  unset DALMATIAN_INSTALLATION
  rm -rf "$CONFIG_INSTALLATIONS_DIR" "$CONFIG_INSTALLATIONS_JSON_FILE"
  run "$TEST_DALMATIAN" version -v 2 -s
  assert_success

  run --separate-stderr "$TEST_DALMATIAN" setup -h
  assert_failure 1
  assert_stderr_contains "Usage: dalmatian setup"
}

@test "v1 with no installation falls through to its existing error" {
  unset DALMATIAN_INSTALLATION
  rm -f "$CONFIG_INSTALLATIONS_JSON_FILE"

  run --separate-stderr "$TEST_DALMATIAN" probe echo-args
  assert_failure 1
  assert_stderr_contains "No AWS SSO configuration was found"
}

@test "a missing selected installation is reported before anything runs" {
  export DALMATIAN_INSTALLATION=nope

  run --separate-stderr "$TEST_DALMATIAN" probe echo-args
  assert_failure 1
  assert_stderr_contains "Dalmatian installation 'nope' does not exist"
}

@test "the legacy layout is migrated on the first run" {
  unset DALMATIAN_INSTALLATION
  rm -rf "$CONFIG_INSTALLATIONS_DIR" "$CONFIG_INSTALLATIONS_JSON_FILE"
  legacy_config_sandbox
  mkdir -p "$SANDBOX/app/tmp/terraform-dxw-dalmatian-infrastructure"

  # bin/dalmatian sets QUIET_MODE=1 when stdout is not a terminal, which it
  # never is under `run`, so the migration message cannot be asserted on here;
  # test/lib/migrate_legacy_installation.bats covers it
  run "$TEST_DALMATIAN" probe echo-args alpha
  assert_success
  assert_output_contains "alpha"
  [ -f "$CONFIG_INSTALLATIONS_DIR/example-project/setup.json" ]
  [ -d "$SANDBOX/app/tmp/example-project/terraform-dxw-dalmatian-infrastructure" ]
  [ ! -e "$CONFIG_DIR/setup.json" ]
  run jq -r '.default' "$CONFIG_INSTALLATIONS_JSON_FILE"
  assert_output "example-project"
}

@test "dalmatian version works with no installation at all" {
  unset DALMATIAN_INSTALLATION
  rm -rf "$CONFIG_INSTALLATIONS_DIR" "$CONFIG_INSTALLATIONS_JSON_FILE"

  run "$TEST_DALMATIAN" version -s
  assert_success
  assert_output "v1"
}

@test "v2 still dispatches when DALMATIAN_INSTALLATION overrides the default" {
  mkdir -p "$CONFIG_INSTALLATIONS_DIR/other"
  install_fixture setup.json "$CONFIG_INSTALLATIONS_DIR/other/setup.json"
  install_fixture dalmatian-sso.config "$CONFIG_INSTALLATIONS_DIR/other/dalmatian-sso.config"
  run "$TEST_DALMATIAN" version -v 2 -s
  assert_success
  export DALMATIAN_INSTALLATION=other

  run "$TEST_DALMATIAN" probe echo-args alpha
  assert_success
  assert_output "alpha"
}
