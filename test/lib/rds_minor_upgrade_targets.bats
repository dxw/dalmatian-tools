#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
}

@test "rds_minor_upgrade_targets lists minor targets in version order" {
  run rds_minor_upgrade_targets -j "$(fixture_json rds-describe-db-engine-versions-mysql.json)"
  assert_success
  assert_output "$(printf '8.4.4\n8.4.10')"
}

@test "rds_minor_upgrade_targets excludes major targets" {
  run rds_minor_upgrade_targets -j "$(fixture_json rds-describe-db-engine-versions-mysql.json)"
  assert_success
  [[ "$output" != *"9.0.1"* ]]
}

@test "rds_minor_upgrade_targets prints nothing when there are no targets" {
  run rds_minor_upgrade_targets -j '{"DBEngineVersions":[{"ValidUpgradeTarget":[]}]}'
  assert_success
  assert_output ""
}

@test "rds_minor_upgrade_targets rejects a missing -j" {
  run --separate-stderr rds_minor_upgrade_targets
  assert_failure
  assert_stderr_contains "Invalid \`rds_minor_upgrade_targets\` function usage"
}
