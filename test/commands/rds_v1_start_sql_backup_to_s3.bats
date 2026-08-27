#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response aws-sts-get_caller_identity "123456789012"
}

@test "rds start-sql-backup-to-s3 prints usage with no arguments and does not run a task" {
  # usage() opens with two plain `echo` description lines (stdout), then a
  # `echo ... 1>&2` for the "Usage:" line itself, then more plain `echo`
  # option lines (stdout). Only the single "Usage:" line reaches stderr.
  run --separate-stderr run_command bin/rds/v1/start-sql-backup-to-s3
  assert_failure 1
  assert_stderr_contains "Usage: start-sql-backup-to-s3 [OPTIONS]"
  assert_output_contains "Starts a SQL backup to S3"
  assert_output_contains "-r <rds_name>"
  refute_stub_called_with "ecs run-task"
}

@test "rds start-sql-backup-to-s3 requires an environment and does not run a task" {
  run --separate-stderr run_command bin/rds/v1/start-sql-backup-to-s3 -i "example-infra" -r "example-rds"
  assert_failure 1
  refute_stub_called_with "ecs run-task"
}

@test "rds start-sql-backup-to-s3 -h prints usage and does not run a task" {
  run --separate-stderr run_command bin/rds/v1/start-sql-backup-to-s3 -h
  assert_failure 1
  refute_stub_called_with "ecs run-task"
}

@test "rds start-sql-backup-to-s3 runs the backup task named from infra+identifier in the infra-environment cluster" {
  run run_command bin/rds/v1/start-sql-backup-to-s3 -i "example-infra" -r "example-rds" -e "staging"
  assert_success
  assert_stub_called_with "ecs run-task --no-cli-pager --cluster example-infra-staging --task-definition arn:aws:ecs:eu-west-2:123456789012:task-definition/example-infra-exampleinfraexamplerdsstaging-sb-st"
}

@test "rds start-sql-backup-to-s3 fails and does not run a task when the account lookup fails" {
  stub_exit aws-sts-get_caller_identity 1
  run --separate-stderr run_command bin/rds/v1/start-sql-backup-to-s3 -i "example-infra" -r "example-rds" -e "staging"
  assert_failure
  refute_stub_called_with "ecs run-task"
}

@test "rds start-sql-backup-to-s3 fails when the run-task call itself fails" {
  stub_exit aws-ecs-run_task 1
  run --separate-stderr run_command bin/rds/v1/start-sql-backup-to-s3 -i "example-infra" -r "example-rds" -e "staging"
  assert_failure
}
