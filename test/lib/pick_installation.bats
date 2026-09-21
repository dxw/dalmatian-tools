#!/usr/bin/env bats

# fzf-chosen, fzf-cancelled and the DALMATIAN_FZF_ENABLED=0 `select` fallback
# all need a real terminal on stdin to get past pick_installation's tty check,
# and bats' `run` gives stdin no tty (verified: `[ -t 0 ]` is false under
# `run`, with or without an explicit redirect). test/lib/pick_ec2_instance.bats
# does not exercise those paths either, for the same reason, so this file
# follows that precedent rather than inventing a pty-faking technique.

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
  rm -rf "$CONFIG_INSTALLATIONS_DIR"
}

make_installation() {
  local name=$1 project=${2-$1}
  mkdir -p "$CONFIG_INSTALLATIONS_DIR/$name"
  printf '{"project_name": "%s"}\n' "$project" > "$CONFIG_INSTALLATIONS_DIR/$name/setup.json"
}

@test "pick_installation fails when there is nothing to pick" {
  run --separate-stderr pick_installation
  assert_failure
  assert_stderr_contains "No installations to choose from"
  assert_stderr_contains "dalmatian setup"
}

@test "pick_installation returns the only installation without prompting" {
  make_installation example-project

  run --separate-stderr pick_installation
  assert_success
  assert_output "example-project"
  refute_stub_called_with fzf
}

@test "pick_installation refuses to prompt with no terminal" {
  make_installation example-project
  make_installation client-a

  run --separate-stderr pick_installation < /dev/null
  assert_failure
  assert_stderr_contains "there is no terminal to choose one with"
}

@test "pick_installation lists the candidates when it cannot prompt" {
  make_installation example-project
  make_installation client-a
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run --separate-stderr pick_installation < /dev/null
  assert_failure
  assert_stderr_contains "* example-project"
  assert_stderr_contains "client-a"
  assert_stderr_contains "Pass the installation name as an argument"
}
