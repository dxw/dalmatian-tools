#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  use_test_app_root
  login_sandbox
}

@test "dalmatian runs the command for the current version" {
  run "$TEST_DALMATIAN" probe echo-args alpha beta
  assert_success
  assert_output_contains "alpha"
  assert_output_contains "beta"
}

@test "dalmatian strips -q from the command arguments" {
  run "$TEST_DALMATIAN" probe echo-args -q alpha
  assert_success
  assert_output "alpha"
}

@test "dalmatian reports an unknown subcommand" {
  run --separate-stderr "$TEST_DALMATIAN" nonsense echo-args
  assert_failure 1
  assert_stderr_contains "\`nonsense\` is not a dalmatian subcommand"
}

@test "dalmatian points at the version switch for a v2-only subcommand" {
  run --separate-stderr "$TEST_DALMATIAN" only-v2 echo-args
  assert_failure 1
  assert_stderr_contains "\`only-v2\` is not available in v1"
  assert_stderr_contains "dalmatian version -v 2"
}

@test "dalmatian lists the available commands when the command is unknown" {
  run "$TEST_DALMATIAN" probe nonsense
  assert_failure 1
  assert_output_contains "dalmatian probe echo-args"
}

@test "dalmatian refuses to run with no configuration at all" {
  rm -f "$CONFIG_SETUP_JSON_FILE" "$CONFIG_AWS_SSO_FILE"

  run --separate-stderr "$TEST_DALMATIAN" probe echo-args
  assert_failure 1
  assert_stderr_contains "No AWS SSO configuration was found"
  assert_stderr_contains "dalmatian version -v 2 && dalmatian setup"
}

@test "dalmatian aws mfa is refused on the AWS SSO path" {
  run --separate-stderr "$TEST_DALMATIAN" aws mfa
  assert_failure 1
  assert_stderr_contains "does not apply when Dalmatian is signing in with AWS SSO"
  assert_stderr_contains "dalmatian aws login"
}

# bin/dalmatian sources every file in lib/bash-functions and exports each
# function it defines, so a command script can call log_info, err and the rest
# without sourcing anything itself. These pin that contract to the function
# list itself rather than to whichever helpers the probe happens to call.
@test "dalmatian exports every lib/bash-functions function to the command it runs" {
  printf '#!/usr/bin/env bash\ncompgen -A function\n' > "$SANDBOX/app/bin/probe/v1/list-functions"
  chmod +x "$SANDBOX/app/bin/probe/v1/list-functions"

  run "$TEST_DALMATIAN" probe list-functions
  assert_success

  local name
  while read -r _ name _
  do
    grep -qx "$name" <<< "$output" \
      || fail "$(printf 'expected %s to be exported to the command\nfunctions seen:\n%s' "$name" "$output")"
  done < <(grep -h '^function' "$DALMATIAN_ROOT"/lib/bash-functions/*.sh)
}

@test "dalmatian keeps its own usage function out of the command's environment" {
  printf '#!/usr/bin/env bash\ncompgen -A function\n' > "$SANDBOX/app/bin/probe/v1/list-functions"
  chmod +x "$SANDBOX/app/bin/probe/v1/list-functions"

  run "$TEST_DALMATIAN" probe list-functions
  assert_success
  if grep -qx "usage" <<< "$output"
  then
    fail "$(printf 'usage was exported to the command\nfunctions seen:\n%s' "$output")"
  fi
}

@test "dalmatian points at the version switch for the v2-only installation command" {
  run --separate-stderr "$TEST_DALMATIAN" installation list
  assert_failure 1
  assert_stderr_contains "\`installation\` is not available in v1"
  assert_stderr_contains "dalmatian version -v 2"
}
