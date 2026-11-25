#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
}

@test "rds_next_maintenance_window: later the same day is upcoming" {
  run rds_next_maintenance_window -w mon:19:00-mon:19:30 -n 1795435200
  assert_success
  assert_output "2026-11-23T19:00:00Z 2026-11-23T19:30:00Z upcoming"
}

@test "rds_next_maintenance_window: inside the window is in progress" {
  run rds_next_maintenance_window -w mon:19:00-mon:19:30 -n 1795461000
  assert_success
  assert_output "2026-11-23T19:00:00Z 2026-11-23T19:30:00Z in-progress"
}

@test "rds_next_maintenance_window: after the window rolls to next week" {
  run rds_next_maintenance_window -w mon:19:00-mon:19:30 -n 1795464000
  assert_success
  assert_output "2026-11-30T19:00:00Z 2026-11-30T19:30:00Z upcoming"
}

@test "rds_next_maintenance_window: days are case-insensitive" {
  run rds_next_maintenance_window -w Mon:19:00-Mon:22:00 -n 1795435200
  assert_success
  assert_output "2026-11-23T19:00:00Z 2026-11-23T22:00:00Z upcoming"
}

@test "rds_next_maintenance_window: a window wrapping the week is in progress just after midnight Monday" {
  run rds_next_maintenance_window -w sun:23:30-mon:00:30 -n 1795392600
  assert_success
  assert_output "2026-11-22T23:30:00Z 2026-11-23T00:30:00Z in-progress"
}

@test "rds_next_maintenance_window: a window wrapping the week is upcoming on Sunday" {
  run rds_next_maintenance_window -w sun:23:30-mon:00:30 -n 1795348800
  assert_success
  assert_output "2026-11-22T23:30:00Z 2026-11-23T00:30:00Z upcoming"
}

@test "rds_next_maintenance_window: rejects a malformed window" {
  run --separate-stderr rds_next_maintenance_window -w funday:19:00 -n 1795435200
  assert_failure
  [[ "$stderr" == *"Unrecognised maintenance window"* ]]
}

@test "rds_next_maintenance_window: rejects missing arguments" {
  run --separate-stderr rds_next_maintenance_window
  assert_failure
  [[ "$stderr" == *"Invalid \`rds_next_maintenance_window\` function usage"* ]]
}
