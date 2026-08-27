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

@test "config list-services-by-buildspec prints usage and exits 1 with -h" {
  run --separate-stderr run_command bin/config/v1/list-services-by-buildspec -h
  assert_failure 1
  assert_stderr_contains "Usage: list-services-by-buildspec"
  assert_output_contains "List all services with a given buildspec"
}

@test "config list-services-by-buildspec requires -b" {
  run --separate-stderr run_command bin/config/v1/list-services-by-buildspec
  assert_failure 1
  assert_stderr_contains "Usage: list-services-by-buildspec"
}

@test "config list-services-by-buildspec returns only matching services across infrastructures" {
  run run_command bin/config/v1/list-services-by-buildspec -b example_buildspec_a
  assert_success
  [ "${#lines[@]}" -eq 2 ]
  assert_line 0 "example-infra web"
  assert_line 1 "other-infra api"
}

@test "config list-services-by-buildspec finds the other buildspec too" {
  run run_command bin/config/v1/list-services-by-buildspec -b example_buildspec_b
  assert_success
  assert_output "example-infra worker"
}

@test "config list-services-by-buildspec scoped to one infrastructure" {
  run run_command bin/config/v1/list-services-by-buildspec -b example_buildspec_a -i other-infra
  assert_success
  assert_output "other-infra api"
}

@test "config list-services-by-buildspec scoped infra + buildspec combination with no match" {
  # other-infra's only service uses example_buildspec_a, not _b, so scoping
  # to other-infra while filtering on _b matches nothing. No error, no
  # output -- select() simply never matches, and there's no `set -e`.
  run run_command bin/config/v1/list-services-by-buildspec -b example_buildspec_b -i other-infra
  assert_success
  assert_output ""
}

@test "config list-services-by-buildspec with an infrastructure that does not exist" {
  # Unlike list-services/list-environments, this script iterates
  # `keys[] as $infra_name` over the whole document and filters with
  # `select($infra_name == $i)`, rather than indexing `.[$i]` directly. An
  # unknown $i just never matches -- no jq error, exit 0, empty output.
  run run_command bin/config/v1/list-services-by-buildspec -b example_buildspec_a -i does-not-exist
  assert_success
  assert_output ""
}

@test "config list-services-by-buildspec with a buildspec that matches nothing" {
  run run_command bin/config/v1/list-services-by-buildspec -b no_such_buildspec
  assert_success
  assert_output ""
}

@test "config list-services-by-buildspec refreshes the config before reading it" {
  run run_command bin/config/v1/list-services-by-buildspec -b example_buildspec_a
  assert_success
  assert_stub_called_with "dalmatian-refresh-config"
}

@test "config list-services-by-buildspec produces no output for a missing config file" {
  DALMATIAN_CONFIG_PATH="$SANDBOX/does-not-exist.yml"
  export DALMATIAN_CONFIG_PATH

  run --separate-stderr run_command bin/config/v1/list-services-by-buildspec -b example_buildspec_a
  assert_success
  assert_output ""
  assert_stderr_contains "no such file or directory"
}
