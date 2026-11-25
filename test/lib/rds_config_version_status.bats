#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
}

@test "rds_config_version_status is ok when config is a prefix of an Aurora target" {
  run rds_config_version_status -c 8.0 -t 8.0.mysql_aurora.3.10.3
  assert_success
  assert_output "ok"
}

@test "rds_config_version_status is ok when versions are equal" {
  run rds_config_version_status -c 8.4.10 -t 8.4.10
  assert_success
  assert_output "ok"
}

@test "rds_config_version_status is ok when config is a minor prefix" {
  run rds_config_version_status -c 8.4 -t 8.4.10
  assert_success
  assert_output "ok"
}

@test "rds_config_version_status does not treat 8.4 as a prefix of 8.40.1" {
  run rds_config_version_status -c 8.4 -t 8.40.1
  assert_success
  assert_output "update"
}

@test "rds_config_version_status reports update for an older full version" {
  run rds_config_version_status -c 8.4.3 -t 8.4.10
  assert_success
  assert_output "update"
}

@test "rds_config_version_status reports unknown for an empty config version" {
  run rds_config_version_status -c "" -t 8.4.10
  assert_success
  assert_output "unknown"
}

@test "rds_config_version_status rejects a missing -t" {
  run --separate-stderr rds_config_version_status -c 8.4
  assert_failure
  assert_stderr_contains "Invalid \`rds_config_version_status\` function usage"
}
