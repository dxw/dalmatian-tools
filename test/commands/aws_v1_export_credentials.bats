#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

load ../test_helper

# These run the script by path, as the Dalmatian repository's scripts do,
# rather than through run_command: nothing is sourced or resolved for it, and
# APP_ROOT is left to the script to work out from its own location.
setup() {
  setup_sandbox
  use_stubs
  use_test_app_root
  EXPORT_CREDENTIALS="$SANDBOX/app/bin/aws/v1/export-credentials"
  INSTALLATIONS_DIR="$CONFIG_INSTALLATIONS_DIR"
}

# Drop everything bin/dalmatian would have exported. Fixtures are staged first,
# through the helpers that build their paths from these variables.
forget_dispatcher_env() {
  unset APP_ROOT DALMATIAN_INSTALLATION CONFIG_INSTALLATION_DIR \
        CONFIG_SETUP_JSON_FILE CONFIG_AWS_SSO_FILE \
        CONFIG_DIR CONFIG_INSTALLATIONS_DIR CONFIG_INSTALLATIONS_JSON_FILE
}

@test "export-credentials -h prints usage" {
  forget_dispatcher_env

  run --separate-stderr "$EXPORT_CREDENTIALS" -h
  assert_failure 1
  assert_stderr_contains "Print 'export' statements for the current Dalmatian AWS credentials"
  [ -z "$output" ] || fail "expected nothing on stdout, got: $output"
}

@test "export-credentials run by path resolves the default installation and signs in with AWS SSO" {
  # The real-world case: v2 is the active version, so this v1 command is only
  # reachable by path, and the dispatcher has exported none of the CONFIG_* paths
  login_sandbox
  run "$SANDBOX/app/bin/dalmatian" version -v 2 -s
  assert_success
  forget_dispatcher_env

  run --separate-stderr "$EXPORT_CREDENTIALS"
  assert_success
  assert_output_contains "export AWS_ACCESS_KEY_ID=AKIAEXAMPLE"
  assert_output_contains "export AWS_SESSION_TOKEN=exampletoken"
  assert_stub_called_with "configure export-credentials --profile dalmatian-main"
  [[ "$stderr" != *"deprecated IAM user"* ]] || fail "fell back to the IAM user: $stderr"
}

@test "export-credentials run by path follows DALMATIAN_INSTALLATION over the default" {
  login_sandbox
  # The default installation loses its AWS SSO configuration, so only the
  # override can take the AWS SSO path
  rm "$INSTALLATIONS_DIR/example-project/dalmatian-sso.config"
  mkdir -p "$INSTALLATIONS_DIR/other"
  install_fixture setup.json "$INSTALLATIONS_DIR/other/setup.json"
  install_fixture dalmatian-sso.config "$INSTALLATIONS_DIR/other/dalmatian-sso.config"
  forget_dispatcher_env
  export DALMATIAN_INSTALLATION=other

  run --separate-stderr "$EXPORT_CREDENTIALS"
  assert_success
  assert_output_contains "export AWS_ACCESS_KEY_ID=AKIAEXAMPLE"
  assert_stub_called_with "configure export-credentials --profile dalmatian-main"
  [[ "$stderr" != *"deprecated IAM user"* ]] || fail "fell back to the IAM user: $stderr"
}

@test "export-credentials run by path with no installation reports that AWS SSO is not configured" {
  forget_dispatcher_env

  run --separate-stderr "$EXPORT_CREDENTIALS"
  assert_failure 1
  assert_stderr_contains "No AWS SSO configuration was found"
  [ -z "$output" ] || fail "expected nothing on stdout, got: $output"
}
