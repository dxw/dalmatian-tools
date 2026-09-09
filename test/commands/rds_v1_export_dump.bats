#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-ssm-get_parameters rds-v1-ssm-get-parameters.json
  stub_response_file aws-rds-describe_db_instances rds-v1-describe-db-instance-single.json
  stub_response_file aws-ec2-describe_instances rds-v1-ec2-describe-instances-single.json
}

@test "rds export-dump prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v1/export-dump
  assert_failure 1
  assert_stderr_contains "Usage: export-dump"
  assert_output_contains "-o <output_file_path>"
}

@test "rds export-dump requires a database name" {
  run --separate-stderr run_command bin/rds/v1/export-dump \
    -i "example-infra" -r "example-rds" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: export-dump"
}

@test "rds export-dump -h prints usage" {
  run --separate-stderr run_command bin/rds/v1/export-dump -h
  assert_failure 1
}

@test "rds export-dump dumps to the current directory and uses the infra+env transfer bucket when -o is omitted" {
  run run_command bin/rds/v1/export-dump \
    -i "example-infra" -r "example-rds" -e "staging" -d "exampledb" -I "i-0fedcba987654321f"
  assert_success
  assert_stub_called_with "ssm start-session --target i-0fedcba987654321f --document-name exampleinfraexamplerdsstaging-rds-sql-dump --parameters RootPassword=example-root-password,DatabaseName=exampledb"
  assert_stub_called_with "s3 cp s3://example-infra-ecs-staging-dalmatian-transfer/db_exports/exampledb-staging-sql-export.sql ."
  assert_stub_called_with "s3 rm s3://example-infra-ecs-staging-dalmatian-transfer/db_exports/exampledb-staging-sql-export.sql"
}

@test "rds export-dump downloads to a given output path, resolved to an absolute path" {
  local out_dir="$SANDBOX/downloads" resolved_out_dir
  mkdir -p "$out_dir"
  # The script realpath(1)s whatever -o gives it, which also resolves any
  # symlinks in the path (e.g. macOS's /var -> /private/var); match that here
  # rather than asserting against the pre-resolution path.
  resolved_out_dir="$(cd "$out_dir" && pwd -P)"
  run run_command bin/rds/v1/export-dump \
    -i "example-infra" -r "example-rds" -e "staging" -d "exampledb" \
    -I "i-0fedcba987654321f" -o "$out_dir/exampledb.sql"
  assert_success
  assert_stub_called_with "s3 cp s3://example-infra-ecs-staging-dalmatian-transfer/db_exports/exampledb-staging-sql-export.sql $resolved_out_dir/exampledb.sql"
  [ -f "$out_dir/exampledb.sql" ]
}

@test "rds export-dump fails and does not touch S3 when the session fails" {
  stub_exit aws-ssm-start_session 1
  run --separate-stderr run_command bin/rds/v1/export-dump \
    -i "example-infra" -r "example-rds" -e "staging" -d "exampledb" -I "i-0fedcba987654321f"
  assert_failure
  refute_stub_called_with "s3 cp"
  refute_stub_called_with "s3 rm"
}

@test "rds export-dump falls back to picking an ECS instance by infra+environment tag when -I is omitted" {
  run run_command bin/rds/v1/export-dump \
    -i "example-infra" -r "example-rds" -e "staging" -d "exampledb"
  assert_success
  assert_stub_called_with "Name=tag:Name,Values=example-infra-staging*"
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0"
}
