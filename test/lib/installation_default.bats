#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  load_all_functions
}

@test "installation_default prints nothing when installations.json is missing" {
  run installation_default
  assert_success
  assert_output ""
}

@test "installation_default prints the recorded default" {
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run installation_default
  assert_success
  assert_output "example-project"
}

@test "installation_default prints nothing when default is not a string" {
  printf '%s\n' '{"default": 42}' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run installation_default
  assert_success
  assert_output ""
}

@test "installation_default prints nothing when default is absent" {
  printf '%s\n' '{}' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run installation_default
  assert_success
  assert_output ""
}

@test "installation_default prints nothing on unparseable json" {
  printf '%s\n' 'not json' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run installation_default
  assert_success
  assert_output ""
}

@test "installation_default prints nothing and no error when the file is unreadable" {
  if [ "$(id -u)" -eq 0 ]
  then
    skip "cannot make a file unreadable while running as root"
  fi
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"
  chmod 000 "$CONFIG_INSTALLATIONS_JSON_FILE"

  run --separate-stderr installation_default
  assert_success
  assert_output ""
  [ -z "$stderr" ]
}
