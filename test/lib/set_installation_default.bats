#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  load_all_functions
}

@test "set_installation_default writes installations.json" {
  run set_installation_default "example-project"
  assert_success
  run jq -r '.default' "$CONFIG_INSTALLATIONS_JSON_FILE"
  assert_output "example-project"
}

@test "set_installation_default creates the config directory if needed" {
  rm -rf "$CONFIG_DIR"

  run set_installation_default "example-project"
  assert_success
  [ -f "$CONFIG_INSTALLATIONS_JSON_FILE" ]
}

@test "set_installation_default replaces an existing default" {
  printf '%s\n' '{"default": "old"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run set_installation_default "new"
  assert_success
  run jq -r '.default' "$CONFIG_INSTALLATIONS_JSON_FILE"
  assert_output "new"
}

@test "set_installation_default rejects an invalid name and leaves the file alone" {
  printf '%s\n' '{"default": "old"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run --separate-stderr set_installation_default "Bad Name"
  assert_failure 1
  assert_stderr_contains "'Bad Name' is not a valid installation name"
  run jq -r '.default' "$CONFIG_INSTALLATIONS_JSON_FILE"
  assert_output "old"
}
