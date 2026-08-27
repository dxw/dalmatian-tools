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

@test "config list-services prints usage and exits 1 with -h" {
  run --separate-stderr run_command bin/config/v1/list-services -h
  assert_failure 1
  assert_stderr_contains "Usage: list-services"
  assert_output_contains "List all services"
}

@test "config list-services lists every service across every infrastructure" {
  run run_command bin/config/v1/list-services
  assert_success
  [ "${#lines[@]}" -eq 3 ]
  assert_line 0 "example-infra: web"
  assert_line 1 "example-infra: worker"
  assert_line 2 "other-infra: api"
}

@test "config list-services scoped to one infrastructure lists only its services" {
  run run_command bin/config/v1/list-services example-infra
  assert_success
  [ "${#lines[@]}" -eq 2 ]
  assert_line 0 "example-infra: web"
  assert_line 1 "example-infra: worker"
}

@test "config list-services scoped to the other infrastructure" {
  run run_command bin/config/v1/list-services other-infra
  assert_success
  assert_output "other-infra: api"
}

@test "config list-services fails loudly for an infrastructure that does not exist" {
  # Same root cause as list-environments: `.[$i].services?[].name` indexes
  # directly by $i. `.[$i]` is null for an unknown name, and `.services?`
  # on null is null too, but then `null[]` (iterating it) is a hard jq error
  # -- "Cannot iterate over null (null)" -- not an empty result. That error
  # is on the last line of the script, so with no `set -e` the script's exit
  # status is still whatever jq returns: 5.
  run --separate-stderr run_command bin/config/v1/list-services does-not-exist
  assert_failure 5
  assert_output ""
  assert_stderr_contains "Cannot iterate over null"
}

@test "config list-services refreshes the config before reading it" {
  run run_command bin/config/v1/list-services
  assert_success
  assert_stub_called_with "dalmatian-refresh-config"
}

@test "config list-services produces no output for a missing config file" {
  DALMATIAN_CONFIG_PATH="$SANDBOX/does-not-exist.yml"
  export DALMATIAN_CONFIG_PATH

  run --separate-stderr run_command bin/config/v1/list-services
  assert_success
  assert_output ""
  assert_stderr_contains "no such file or directory"
}
