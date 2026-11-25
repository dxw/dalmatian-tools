#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
}

@test "rds_text_names_version finds a version in a sentence" {
  run rds_text_names_version -t "Upgrade to 3.10.3" -v 3.10.3
  assert_success
}

@test "rds_text_names_version finds a version at the start of the text" {
  run rds_text_names_version -t "3.10.3 is available" -v 3.10.3
  assert_success
}

@test "rds_text_names_version finds a later match after a longer version" {
  run rds_text_names_version -t "Upgrade 3.10.30 to 3.10.3 instead" -v 3.10.3
  assert_success
}

@test "rds_text_names_version does not find a version followed by a digit" {
  run rds_text_names_version -t "3.10.30" -v 3.10.3
  assert_failure 1
}

@test "rds_text_names_version does not find a version preceded by a digit" {
  run rds_text_names_version -t "13.10.3" -v 3.10.3
  assert_failure 1
}

@test "rds_text_names_version does not find a version followed by a dotted part" {
  run rds_text_names_version -t "3.10.3.1" -v 3.10.3
  assert_failure 1
}

@test "rds_text_names_version does not find 14.1 in 14.10" {
  run rds_text_names_version -t "14.10" -v 14.1
  assert_failure 1
}

@test "rds_text_names_version does not find a version in empty text" {
  run rds_text_names_version -t "" -v 14.1
  assert_failure 1
}

@test "rds_text_names_version rejects a missing -v" {
  run --separate-stderr rds_text_names_version -t "14.1"
  assert_failure
  assert_stderr_contains "Invalid \`rds_text_names_version\` function usage"
}
