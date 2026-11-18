#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  load_all_functions
  RESULT_FILE="$SANDBOX/result"
}

@test "rds_task_outcome passes an exit status through" {
  printf 'exited 0\n' > "$RESULT_FILE"
  run rds_task_outcome "$RESULT_FILE"
  assert_success
  assert_output "exited 0"

  printf 'exited 10\n' > "$RESULT_FILE"
  run rds_task_outcome "$RESULT_FILE"
  assert_output "exited 10"
}

@test "rds_task_outcome passes never-ran through" {
  printf 'never-ran\n' > "$RESULT_FILE"
  run rds_task_outcome "$RESULT_FILE"
  assert_success
  assert_output "never-ran"
}

@test "rds_task_outcome treats a killed or terminated container as unknown" {
  for status in 137 143
  do
    printf 'exited %s\n' "$status" > "$RESULT_FILE"
    run rds_task_outcome "$RESULT_FILE"
    assert_success
    assert_output "unknown"
  done
}

@test "rds_task_outcome treats an empty, malformed or missing file as unknown" {
  : > "$RESULT_FILE"
  run rds_task_outcome "$RESULT_FILE"
  assert_output "unknown"

  printf 'exited x\n' > "$RESULT_FILE"
  run rds_task_outcome "$RESULT_FILE"
  assert_output "unknown"

  run rds_task_outcome "$SANDBOX/missing"
  assert_success
  assert_output "unknown"
}

@test "rds_task_outcome requires a file" {
  run --separate-stderr rds_task_outcome
  assert_failure 1
  assert_stderr_contains "Invalid \`rds_task_outcome\` function usage"
}
