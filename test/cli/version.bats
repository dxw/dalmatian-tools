#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
}

@test "dalmatian version defaults to v1 on a fresh configuration" {
  run "$DALMATIAN_ROOT/bin/dalmatian" version -s
  assert_success
  assert_output "v1"
}

@test "dalmatian version writes version.json on first run" {
  run "$DALMATIAN_ROOT/bin/dalmatian" version -s
  assert_success
  [ -f "$CONFIG_DIR/version.json" ]
  run jq -r '.version' "$CONFIG_DIR/version.json"
  assert_output "v1"
}

@test "dalmatian version -v 2 switches to v2 and persists it" {
  run "$DALMATIAN_ROOT/bin/dalmatian" version -v 2
  assert_success

  run "$DALMATIAN_ROOT/bin/dalmatian" version -s
  assert_success
  assert_output "v2"
}

@test "dalmatian version -v 1 switches back to v1" {
  run "$DALMATIAN_ROOT/bin/dalmatian" version -v 2
  assert_success
  run "$DALMATIAN_ROOT/bin/dalmatian" version -v 1
  assert_success

  run "$DALMATIAN_ROOT/bin/dalmatian" version -s
  assert_success
  assert_output "v1"
}
