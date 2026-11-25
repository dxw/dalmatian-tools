#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
  CONFIG="$BATS_TEST_TMPDIR/dalmatian.yml"
  install_fixture dalmatian-rds-upgrade.yml "$CONFIG"
}

@test "rds_v1_config_environments lists environment names sorted" {
  run rds_v1_config_environments -f "$CONFIG" -i example-infra
  assert_success
  assert_output "$(printf 'prod\nstaging')"
}

@test "rds_v1_config_environments prints nothing for an unknown infrastructure" {
  run rds_v1_config_environments -f "$CONFIG" -i unknown-infra
  assert_success
  assert_output ""
}
