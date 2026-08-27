#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-ssm-get_parameters rds-v1-ssm-get-parameters.json
  stub_response_file aws-rds-describe_db_clusters aurora-v1-describe-db-cluster-single.json
  stub_response_file aws-ec2-describe_instances rds-v1-ec2-describe-instances-single.json
}

@test "aurora export-dump prints usage with no arguments" {
  run --separate-stderr run_command bin/aurora/v1/export-dump
  assert_failure 1
  assert_stderr_contains "Usage: export-dump"
  assert_output_contains "-o <output_file_path>"
}

@test "aurora export-dump requires a database name" {
  run --separate-stderr run_command bin/aurora/v1/export-dump \
    -i "example-infra" -r "example-rds" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: export-dump"
}

@test "aurora export-dump -h prints usage" {
  run --separate-stderr run_command bin/aurora/v1/export-dump -h
  assert_failure 1
}

# Diverges from the rds twin: aurora reads the "-aurora/password" parameter
# and looks the cluster up with `describe-db-clusters
# --db-cluster-identifier`, not "-rds/password" and `describe-db-instances`.
@test "aurora export-dump dumps to the current directory and uses the infra+env transfer bucket when -o is omitted" {
  run run_command bin/aurora/v1/export-dump \
    -i "example-infra" -r "example-rds" -e "staging" -d "exampledb" -I "i-0fedcba987654321f"
  assert_success
  assert_stub_called_with "ssm get-parameters --names /example-infra/exampleinfraexamplerdsstaging-aurora/password"
  assert_stub_called_with "ssm start-session --target i-0fedcba987654321f --document-name exampleinfraexamplerdsstaging-aurora-sql-dump --parameters RootPassword=example-root-password,DatabaseName=exampledb"
  assert_stub_called_with "s3 cp s3://example-infra-ecs-staging-dalmatian-transfer/db_exports/exampledb-staging-sql-export.sql ."
  assert_stub_called_with "s3 rm s3://example-infra-ecs-staging-dalmatian-transfer/db_exports/exampledb-staging-sql-export.sql"
}

@test "aurora export-dump downloads to a given output path, resolved to an absolute path, when the file already exists" {
  local out_dir="$SANDBOX/downloads" resolved_out_dir
  mkdir -p "$out_dir"
  touch "$out_dir/exampledb.sql"
  resolved_out_dir="$(cd "$out_dir" && pwd -P)"
  run run_command bin/aurora/v1/export-dump \
    -i "example-infra" -r "example-rds" -e "staging" -d "exampledb" \
    -I "i-0fedcba987654321f" -o "$out_dir/exampledb.sql"
  assert_success
  assert_stub_called_with "s3 cp s3://example-infra-ecs-staging-dalmatian-transfer/db_exports/exampledb-staging-sql-export.sql $resolved_out_dir/exampledb.sql"
}

# Real divergence from the rds twin (not just identifier naming): rds's -o
# handling touches the output path first if it doesn't already exist, then
# realpath(1)s it -- so a not-yet-existing file under -o works. aurora's -o
# handling skips the touch and realpath(1)s the raw path directly. On this
# platform's realpath, a non-existent path is an error, so aurora's
# export-dump fails outright -- before any AWS call -- when given -o pointing
# at a file that doesn't exist yet, where the rds twin would succeed. Verified
# directly against both scripts and against realpath(1) on this host.
@test "aurora export-dump fails before any AWS call when -o points to a file that does not exist yet" {
  local out_dir="$SANDBOX/downloads"
  mkdir -p "$out_dir"

  # Whether the missing `touch` actually bites depends on the local realpath(1):
  # BSD/macOS realpath errors on a non-existent path, GNU realpath resolves it
  # happily. So the divergence from the rds twin is real either way, but only
  # observable here on a BSD realpath. Detected rather than assumed.
  if realpath "$SANDBOX/definitely-not-created" > /dev/null 2>&1
  then
    skip "GNU realpath resolves non-existent paths, so the missing touch is not observable here"
  fi

  run --separate-stderr run_command bin/aurora/v1/export-dump \
    -i "example-infra" -r "example-rds" -e "staging" -d "exampledb" \
    -I "i-0fedcba987654321f" -o "$out_dir/exampledb.sql"
  assert_failure
  refute_stub_called_with "ssm start-session"
  refute_stub_called_with "s3 cp"
}

@test "aurora export-dump fails and does not touch S3 when the session fails" {
  stub_exit aws-ssm-start_session 1
  run --separate-stderr run_command bin/aurora/v1/export-dump \
    -i "example-infra" -r "example-rds" -e "staging" -d "exampledb" -I "i-0fedcba987654321f"
  assert_failure
  refute_stub_called_with "s3 cp"
  refute_stub_called_with "s3 rm"
}

@test "aurora export-dump falls back to picking an ECS instance by infra+environment tag when -I is omitted" {
  run run_command bin/aurora/v1/export-dump \
    -i "example-infra" -r "example-rds" -e "staging" -d "exampledb"
  assert_success
  assert_stub_called_with "Name=tag:Name,Values=example-infra-staging*"
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0"
}
