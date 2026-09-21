#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  load_all_functions
}

@test "installation_name_valid accepts lower-case letters, digits, hyphen and underscore" {
  run installation_name_valid "example-project_2"
  assert_success
}

@test "installation_name_valid accepts a single character" {
  run installation_name_valid "a"
  assert_success
}

@test "installation_name_valid rejects an empty name" {
  run installation_name_valid ""
  assert_failure
}

@test "installation_name_valid rejects a missing argument" {
  run installation_name_valid
  assert_failure
}

@test "installation_name_valid rejects upper-case letters" {
  run installation_name_valid "Example"
  assert_failure
}

@test "installation_name_valid rejects a leading hyphen" {
  run installation_name_valid "-example"
  assert_failure
}

@test "installation_name_valid rejects path separators and dots" {
  run installation_name_valid "../example"
  assert_failure
  run installation_name_valid "ex.ample"
  assert_failure
}

@test "installation_name_valid rejects spaces" {
  run installation_name_valid "ex ample"
  assert_failure
}
