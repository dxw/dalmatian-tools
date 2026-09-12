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
  load_all_functions
  export QUIET_MODE=0
  unset DALMATIAN_INSTALLATION_ANNOUNCED
}

@test "announce_installation_override is silent when the installation is the default" {
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"
  export DALMATIAN_INSTALLATION=example-project

  run announce_installation_override
  assert_success
  assert_output ""
}

@test "announce_installation_override is silent when no installation is selected" {
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"
  export DALMATIAN_INSTALLATION=""

  run announce_installation_override
  assert_success
  assert_output ""
}

@test "announce_installation_override names both installations when the environment overrides the default" {
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"
  export DALMATIAN_INSTALLATION=other

  run announce_installation_override
  assert_success
  assert_output_contains "Using Dalmatian installation 'other'"
  assert_output_contains "overrides the default 'example-project'"
}

@test "announce_installation_override says so when no default is recorded" {
  rm -f "$CONFIG_INSTALLATIONS_JSON_FILE"
  export DALMATIAN_INSTALLATION=other

  run announce_installation_override
  assert_success
  assert_output_contains "Using Dalmatian installation 'other'"
  assert_output_contains "no default is recorded"
}

@test "announce_installation_override respects quiet mode" {
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"
  export DALMATIAN_INSTALLATION=other
  export QUIET_MODE=1

  run announce_installation_override
  assert_success
  assert_output ""
}

@test "announce_installation_override prints once per process tree" {
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"
  export DALMATIAN_INSTALLATION=other
  unset DALMATIAN_INSTALLATION_ANNOUNCED

  export -f announce_installation_override installation_default log_info

  run bash -c '
    announce_installation_override
    announce_installation_override
    bash -c "announce_installation_override"
  '
  assert_success
  [ "$(printf "%s\n" "$output" | grep -c "Using Dalmatian installation")" -eq 1 ]
}

@test "announce_installation_override is silent when a parent already announced" {
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"
  export DALMATIAN_INSTALLATION=other
  export DALMATIAN_INSTALLATION_ANNOUNCED=1

  run announce_installation_override
  assert_success
  assert_output ""
}
