#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  load_all_functions
  rm -rf "$CONFIG_INSTALLATIONS_DIR"
}

make_installation() {
  local name=$1 project=${2-$1}
  mkdir -p "$CONFIG_INSTALLATIONS_DIR/$name"
  printf '{"project_name": "%s"}\n' "$project" > "$CONFIG_INSTALLATIONS_DIR/$name/setup.json"
}

@test "installation_rows prints nothing and exits 0 when the directory is missing" {
  run installation_rows
  assert_success
  assert_output ""
}

@test "installation_rows prints nothing and exits 0 when the directory is empty" {
  mkdir -p "$CONFIG_INSTALLATIONS_DIR"

  run installation_rows
  assert_success
  assert_output ""
}

@test "installation_rows marks the default and shows project names" {
  make_installation example-project
  make_installation client-a client-a-platform
  printf '%s\n' '{"default": "example-project"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"

  run installation_rows
  assert_success
  assert_output_contains "* example-project"
  assert_output_contains "  client-a"
  assert_output_contains "client-a-platform"
}

@test "installation_rows shows (no setup.json) for an installation missing it" {
  make_installation example-project
  rm "$CONFIG_INSTALLATIONS_DIR/example-project/setup.json"

  run installation_rows
  assert_success
  assert_output_contains "example-project"
  assert_output_contains "(no setup.json)"
}
