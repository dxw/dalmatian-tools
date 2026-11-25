#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
  CONFIG="$BATS_TEST_TMPDIR/dalmatian.yml"
  install_fixture dalmatian-rds-upgrade.yml "$CONFIG"
}

@test "rds_v1_config_engine_version reads an rds entry" {
  run rds_v1_config_engine_version -f "$CONFIG" -i example-infra -b rds -r examplerds
  assert_success
  assert_output "8.4.3"
}

@test "rds_v1_config_engine_version reads an aurora entry" {
  run rds_v1_config_engine_version -f "$CONFIG" -i example-infra -b aurora -r examplecluster
  assert_success
  assert_output "8.0"
}

@test "rds_v1_config_engine_version finds a dashed identifier by its dashless name" {
  run rds_v1_config_engine_version -f "$CONFIG" -i example-infra -b rds -r dasheddb
  assert_success
  assert_output "8.0.40"
}

@test "rds_v1_config_engine_version finds a dashed identifier by its dashed name" {
  run rds_v1_config_engine_version -f "$CONFIG" -i example-infra -b rds -r dashed-db
  assert_success
  assert_output "8.0.40"
}

@test "rds_v1_config_engine_version prints nothing for a missing entry" {
  run rds_v1_config_engine_version -f "$CONFIG" -i example-infra -b rds -r missing
  assert_success
  assert_output ""
}

@test "rds_v1_config_engine_version prints nothing for a missing file" {
  run rds_v1_config_engine_version -f "$BATS_TEST_TMPDIR/nope.yml" -i example-infra -b rds -r examplerds
  assert_success
  assert_output ""
}

@test "rds_v1_config_engine_version rejects an unknown block" {
  run --separate-stderr rds_v1_config_engine_version -f "$CONFIG" -i example-infra -b other -r examplerds
  assert_failure
  assert_stderr_contains "Invalid \`rds_v1_config_engine_version\` function usage"
}

@test "rds_v1_config_engine_version treats a quoted infrastructure name as data" {
  run rds_v1_config_engine_version -f "$CONFIG" -i 'ex"ample' -b rds -r examplerds
  assert_success
  assert_output ""
}
