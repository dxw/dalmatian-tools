#!/usr/bin/env bats
#
# shellcheck disable=SC2030,SC2031
# Each @test block is a shellcheck-visible function, so `export QUIET_MODE=0`
# inside one looks like a subshell-local change that could be "lost". bats
# runs each @test as its own invocation, so the export is read back within
# the same test that set it -- shellcheck just can't see that the boundary
# is a test, not a subshell escape.

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  # run_command sets APP_ROOT from DALMATIAN_TEST_APP_ROOT, so both must point
  # at the sandbox for the script and this file to agree on tmp/
  export DALMATIAN_TEST_APP_ROOT="$SANDBOX/app"
  export APP_ROOT="$SANDBOX/app"
  mkdir -p "$APP_ROOT/tmp"
  unset DALMATIAN_INSTALLATION
  rm -rf "$CONFIG_INSTALLATIONS_DIR"
}

make_installation() {
  local name=$1 project=${2-$1}
  mkdir -p "$CONFIG_INSTALLATIONS_DIR/$name" "$APP_ROOT/tmp/$name"
  printf '{"project_name": "%s"}\n' "$project" > "$CONFIG_INSTALLATIONS_DIR/$name/setup.json"
}

@test "installation prints usage with no action" {
  run --separate-stderr run_command bin/configure-commands/v2/installation
  assert_failure 1
  assert_stderr_contains "Usage: installation"
}

@test "installation -h prints usage" {
  run --separate-stderr run_command bin/configure-commands/v2/installation -h
  assert_failure 1
  assert_stderr_contains "Usage: installation"
  assert_output_contains "list"
  assert_output_contains "use [<name>]"
  assert_output_contains "remove [-y] [<name>]"
  assert_output_contains "Omit the name to choose interactively"
}

@test "installation rejects an unknown action" {
  run --separate-stderr run_command bin/configure-commands/v2/installation frobnicate
  assert_failure 1
  assert_stderr_contains "Usage: installation"
}

@test "installation list with no installations hints at setup" {
  export QUIET_MODE=0

  run run_command bin/configure-commands/v2/installation list
  assert_success
  assert_output_contains "dalmatian setup"
}

@test "installation list marks the default and shows project names" {
  make_installation example-project
  make_installation client-a client-a-platform
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run run_command bin/configure-commands/v2/installation list
  assert_success
  assert_output_contains "* example-project"
  assert_output_contains "  client-a"
  assert_output_contains "client-a-platform"
}

@test "installation list copes with an installation missing its setup.json" {
  make_installation example-project
  rm "$CONFIG_INSTALLATIONS_DIR/example-project/setup.json"

  run run_command bin/configure-commands/v2/installation list
  assert_success
  assert_output_contains "example-project"
  assert_output_contains "(no setup.json)"
}

@test "installation use records the default" {
  make_installation example-project
  make_installation client-a

  run run_command bin/configure-commands/v2/installation use client-a
  assert_success
  run jq -r '.default' "$CONFIG_INSTALLATIONS_JSON_FILE"
  assert_output "client-a"
}

@test "installation use refuses a missing installation" {
  make_installation example-project
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run --separate-stderr run_command bin/configure-commands/v2/installation use nope
  assert_failure 1
  assert_stderr_contains "Dalmatian installation 'nope' does not exist"
  assert_stderr_contains "dalmatian installation list"
  run jq -r '.default' "$CONFIG_INSTALLATIONS_JSON_FILE"
  assert_output "example-project"
}

@test "installation use refuses an invalid name" {
  run --separate-stderr run_command bin/configure-commands/v2/installation use "Bad Name"
  assert_failure 1
  assert_stderr_contains "'Bad Name' is not a valid installation name"
}

@test "installation use with no name and no installations fails with the setup hint" {
  export QUIET_MODE=0

  run --separate-stderr run_command bin/configure-commands/v2/installation use
  assert_failure 1
  assert_stderr_contains "No installations to choose from"
  assert_stderr_contains "dalmatian setup"
}

@test "installation use with no name and no terminal fails listing the candidates" {
  make_installation example-project
  make_installation client-a

  run --separate-stderr run_command bin/configure-commands/v2/installation use < /dev/null
  assert_failure 1
  assert_stderr_contains "there is no terminal to choose one with"
  assert_stderr_contains "example-project"
  assert_stderr_contains "client-a"
}

@test "installation remove -y deletes the config and tmp directories" {
  make_installation example-project
  make_installation client-a
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run run_command bin/configure-commands/v2/installation remove -y client-a
  assert_success
  [ ! -e "$CONFIG_INSTALLATIONS_DIR/client-a" ]
  [ ! -e "$APP_ROOT/tmp/client-a" ]
  [ -d "$CONFIG_INSTALLATIONS_DIR/example-project" ]
}

@test "installation remove prompts and honours a yes" {
  make_installation example-project
  make_installation client-a
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run run_command bin/configure-commands/v2/installation remove client-a <<< "y"
  assert_success
  [ ! -e "$CONFIG_INSTALLATIONS_DIR/client-a" ]
}

@test "installation remove prompts and honours a no" {
  make_installation example-project
  make_installation client-a
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run run_command bin/configure-commands/v2/installation remove client-a <<< "n"
  assert_success
  [ -d "$CONFIG_INSTALLATIONS_DIR/client-a" ]
}

@test "installation remove refuses the default installation" {
  make_installation example-project
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run --separate-stderr run_command bin/configure-commands/v2/installation remove -y example-project
  assert_failure 1
  assert_stderr_contains "'example-project' is the default installation"
  assert_stderr_contains "dalmatian installation use"
  [ -d "$CONFIG_INSTALLATIONS_DIR/example-project" ]
}

@test "installation remove refuses a missing installation" {
  run --separate-stderr run_command bin/configure-commands/v2/installation remove -y nope
  assert_failure 1
  assert_stderr_contains "Dalmatian installation 'nope' does not exist"
}

@test "installation remove copes with no tmp directory for the installation" {
  make_installation example-project
  make_installation client-a
  rm -rf "$APP_ROOT/tmp/client-a"
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run run_command bin/configure-commands/v2/installation remove -y client-a
  assert_success
  [ ! -e "$CONFIG_INSTALLATIONS_DIR/client-a" ]
}

@test "installation remove -y with no name and no terminal fails listing the candidates" {
  make_installation example-project
  make_installation client-a
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run --separate-stderr run_command bin/configure-commands/v2/installation remove -y < /dev/null
  assert_failure 1
  assert_stderr_contains "there is no terminal to choose one with"
  assert_stderr_contains "client-a"
  [ -d "$CONFIG_INSTALLATIONS_DIR/client-a" ]
}
