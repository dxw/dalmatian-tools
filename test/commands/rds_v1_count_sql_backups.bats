#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-s3api-list_objects_v2 rds-v1-s3-objects-keys.json
}

@test "rds count-sql-backups prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v1/count-sql-backups
  assert_failure 1
  assert_stderr_contains "Usage: count-sql-backups"
  assert_output_contains "-d <date>"
}

@test "rds count-sql-backups requires an environment" {
  run --separate-stderr run_command bin/rds/v1/count-sql-backups -i "example-infra" -r "example-rds"
  assert_failure 1
  assert_stderr_contains "Usage: count-sql-backups"
}

@test "rds count-sql-backups -h prints usage" {
  run --separate-stderr run_command bin/rds/v1/count-sql-backups -h
  assert_failure 1
}

@test "rds count-sql-backups queries the bucket named from infra+identifier and the given date" {
  run run_command bin/rds/v1/count-sql-backups -i "example-infra" -r "example-rds" -e "staging" -d "2026-08-27"
  assert_success
  assert_stub_called_with "s3api list-objects-v2 --bucket example-infra-exampleinfraexamplerdsstaging-sql-backup"
  assert_stub_called_with "contains(LastModified,\`2026-08-27\`)"
}

@test "rds count-sql-backups prints the number of matching backups" {
  run run_command bin/rds/v1/count-sql-backups -i "example-infra" -r "example-rds" -e "staging" -d "2026-08-27"
  assert_success
  assert_output "2"
}

@test "rds count-sql-backups prints 0 for an empty result set" {
  stub_response_file aws-s3api-list_objects_v2 rds-v1-s3-objects-empty.json
  run run_command bin/rds/v1/count-sql-backups -i "example-infra" -r "example-rds" -e "staging" -d "2026-08-27"
  assert_success
  assert_output "0"
}

@test "rds count-sql-backups defaults the date to today when -d is omitted" {
  today="$(date +%Y-%m-%d)"
  run run_command bin/rds/v1/count-sql-backups -i "example-infra" -r "example-rds" -e "staging"
  assert_success
  assert_stub_called_with "contains(LastModified,\`$today\`)"
}

@test "rds count-sql-backups fails when the S3 call fails" {
  stub_exit aws-s3api-list_objects_v2 1
  run --separate-stderr run_command bin/rds/v1/count-sql-backups -i "example-infra" -r "example-rds" -e "staging" -d "2026-08-27"
  assert_failure
}
