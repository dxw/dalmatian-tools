#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
}

@test "dalmatian with no arguments prints usage and fails" {
  # Only the first line of usage() is redirected to stderr (1>&2); the rest
  # of the usage text is written to stdout. Assert on stdout accordingly.
  run --separate-stderr "$DALMATIAN_ROOT/bin/dalmatian"
  assert_failure 1
  assert_stderr_contains "Usage: dalmatian"
  assert_output_contains "SUBCOMMAND COMMAND"
}

@test "dalmatian -h prints usage and fails" {
  run --separate-stderr "$DALMATIAN_ROOT/bin/dalmatian" -h
  assert_failure 1
  assert_stderr_contains "Usage: dalmatian"
}

@test "dalmatian -l lists subcommands and their commands" {
  run "$DALMATIAN_ROOT/bin/dalmatian" -l
  assert_success
  assert_output_contains "Available commands:"
  assert_output_contains "ecs"
  assert_output_contains "version"
}

@test "dalmatian -l does not list internal directories" {
  run "$DALMATIAN_ROOT/bin/dalmatian" -l
  assert_success
  refute_output_line "  tmp"
  refute_output_line "  configure-commands"
}

@test "dalmatian -l lists v2 commands after switching version" {
  run "$DALMATIAN_ROOT/bin/dalmatian" version -v 2
  assert_success

  run "$DALMATIAN_ROOT/bin/dalmatian" -l
  assert_success
  assert_output_contains "deploy"
}
