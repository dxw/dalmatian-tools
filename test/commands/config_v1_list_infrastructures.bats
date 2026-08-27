#!/usr/bin/env bats
#
# shellcheck disable=SC2030,SC2031
# Each @test block is a shellcheck-visible function, so reassigning
# DALMATIAN_CONFIG_PATH inside one looks like a subshell-local change that
# could be "lost" before it's read. bats runs each @test as its own
# invocation and the reassignment is read back within that same test --
# It just can't see that the boundary is a test, not a subshell.

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  stub_cli
  export QUIET_MODE=1
  DALMATIAN_CONFIG_PATH="$SANDBOX/dalmatian.yml"
  export DALMATIAN_CONFIG_PATH
  install_fixture dalmatian.yml "$DALMATIAN_CONFIG_PATH"
}

@test "config list-infrastructures prints usage and exits 1 with -h" {
  # Only the "Usage: ..." line is redirected to stderr; "List all
  # infrastructures" and the -h option line are plain `echo`, so they land on
  # stdout.
  run --separate-stderr run_command bin/config/v1/list-infrastructures -h
  assert_failure 1
  assert_stderr_contains "Usage: list-infrastructures"
  assert_output_contains "List all infrastructures"
}

@test "config list-infrastructures lists every infrastructure name" {
  run run_command bin/config/v1/list-infrastructures
  assert_success
  [ "${#lines[@]}" -eq 2 ]
  assert_line 0 "example-infra"
  assert_line 1 "other-infra"
}

@test "config list-infrastructures refreshes the config before reading it" {
  run run_command bin/config/v1/list-infrastructures
  assert_success
  assert_stub_called_with "dalmatian-refresh-config"
}

@test "config list-infrastructures produces no output for a missing config file" {
  # yq's "no such file" error goes to stderr; the script has no `set -e`, so
  # the pipeline continues into `sed` on empty input. sed succeeds on empty
  # input, so its exit status (0) becomes the whole pipeline's -- the missing
  # file is silently swallowed rather than reported as a failure.
  DALMATIAN_CONFIG_PATH="$SANDBOX/does-not-exist.yml"
  export DALMATIAN_CONFIG_PATH

  run --separate-stderr run_command bin/config/v1/list-infrastructures
  assert_success
  assert_output ""
  assert_stderr_contains "no such file or directory"
}

@test "config list-infrastructures produces no output for a malformed config file" {
  printf 'infrastructures: [this is not: valid: yaml\n' > "$DALMATIAN_CONFIG_PATH"

  run --separate-stderr run_command bin/config/v1/list-infrastructures
  assert_success
  assert_output ""
  assert_stderr_contains "Error"
}

@test "config list-infrastructures ignores trailing arguments" {
  run run_command bin/config/v1/list-infrastructures anything
  assert_success
  [ "${#lines[@]}" -eq 2 ]
}
