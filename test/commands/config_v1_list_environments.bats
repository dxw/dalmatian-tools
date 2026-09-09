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

@test "config list-environments prints usage and exits 1 with -h" {
  run --separate-stderr run_command bin/config/v1/list-environments -h
  assert_failure 1
  assert_stderr_contains "Usage: list-environments"
  assert_output_contains "List environment names"
}

@test "config list-environments lists array INDICES, not environment names" {
  # In the fixture, `environments` is a YAML sequence:
  #   environments:
  #     - staging
  #     - prod
  # The script does `.[$i].environments? | keys[]`, and jq's `keys` on an
  # array returns its numeric indices, not its values. So this command does
  # not actually print "staging"/"prod" -- it prints "0"/"1". This looks like
  # a genuine bug: `keys[]` only does what the name suggests for an object
  # (map), and would need `.[]` (or `.environments[]`) to list the actual
  # environment names.
  run run_command bin/config/v1/list-environments
  assert_success
  [ "${#lines[@]}" -eq 3 ]
  assert_line 0 "example-infra: 0"
  assert_line 1 "example-infra: 1"
  assert_line 2 "other-infra: 0"
  refute_output_line "example-infra: staging"
}

@test "config list-environments scoped to one infrastructure also returns indices" {
  run run_command bin/config/v1/list-environments example-infra
  assert_success
  [ "${#lines[@]}" -eq 2 ]
  assert_line 0 "example-infra: 0"
  assert_line 1 "example-infra: 1"
}

@test "config list-environments scoped to other-infra returns its single index" {
  run run_command bin/config/v1/list-environments other-infra
  assert_success
  assert_line 0 "other-infra: 0"
}

@test "config list-environments fails loudly for an infrastructure that does not exist" {
  # Unlike list-services-by-buildspec and services-to-tsv (which iterate
  # `keys[] as $infra_name` and `select()` against it), this script indexes
  # directly: `.[$i].environments`. When $i is not a key, `.[$i]` is null,
  # and `null | keys` raises a jq error ("null (null) has no keys") rather
  # than yielding nothing. Because that's the *last* command in the script
  # and there's no `set -e`, the script's own exit status becomes jq's: 5,
  # not 0. This is the one config/v1 command in this family where an unknown
  # infrastructure name is NOT silently swallowed.
  run --separate-stderr run_command bin/config/v1/list-environments does-not-exist
  assert_failure 5
  assert_output ""
  assert_stderr_contains "has no keys"
}

@test "config list-environments refreshes the config before reading it" {
  run run_command bin/config/v1/list-environments
  assert_success
  assert_stub_called_with "dalmatian-refresh-config"
}

@test "config list-environments produces no output for a missing config file" {
  DALMATIAN_CONFIG_PATH="$SANDBOX/does-not-exist.yml"
  export DALMATIAN_CONFIG_PATH

  run --separate-stderr run_command bin/config/v1/list-environments
  assert_success
  assert_output ""
  assert_stderr_contains "no such file or directory"
}
