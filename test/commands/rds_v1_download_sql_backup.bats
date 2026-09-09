#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-s3api-list_objects_v2 rds-v1-s3-objects-keys.json
}

@test "rds download-sql-backup prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v1/download-sql-backup
  assert_failure 1
  assert_stderr_contains "Usage: download-sql-backup"
  assert_output_contains "-o <output_file_path>"
}

@test "rds download-sql-backup requires an environment" {
  run --separate-stderr run_command bin/rds/v1/download-sql-backup -i "example-infra" -r "example-rds"
  assert_failure 1
  assert_stderr_contains "Usage: download-sql-backup"
}

@test "rds download-sql-backup -h prints usage" {
  run --separate-stderr run_command bin/rds/v1/download-sql-backup -h
  assert_failure 1
}

# There is no terminal under bats, so `read -rp` never actually shows its
# prompt (bash only writes a `-p` prompt when stdin is a terminal); the
# numbered `cat -n` listing is what a script consumer under test actually
# sees. Piping "1" in as the answer selects the first matching key.
@test "rds download-sql-backup lists matching backups and downloads the chosen one to ~/Downloads by default" {
  run run_command bin/rds/v1/download-sql-backup -i "example-infra" -r "example-rds" -e "staging" -d "2026-08-27" <<< "1"
  assert_success
  assert_output_contains "1	example-infra/exampleinfraexamplerdsstaging-2026-08-27-1200.sql.gz"
  assert_stub_called_with "s3 cp s3://example-infra-exampleinfraexamplerdsstaging-sql-backup/example-infra/exampleinfraexamplerdsstaging-2026-08-27-1200.sql.gz $HOME/Downloads/example-infra/exampleinfraexamplerdsstaging-2026-08-27-1200.sql.gz"
}

@test "rds download-sql-backup downloads the second listed backup and honours -o" {
  run run_command bin/rds/v1/download-sql-backup -i "example-infra" -r "example-rds" -e "staging" -d "2026-08-27" -o "$SANDBOX/backup.sql.gz" <<< "2"
  assert_success
  assert_stub_called_with "s3 cp s3://example-infra-exampleinfraexamplerdsstaging-sql-backup/example-infra/exampleinfraexamplerdsstaging-2026-08-27-1300.sql.gz $SANDBOX/backup.sql.gz"
}

@test "rds download-sql-backup fails and does not download when nothing matches the date" {
  stub_response_file aws-s3api-list_objects_v2 rds-v1-s3-objects-empty.json
  run --separate-stderr run_command bin/rds/v1/download-sql-backup -i "example-infra" -r "example-rds" -e "staging" -d "2026-08-27" < /dev/null
  assert_failure 1
  assert_stderr_contains "Please specify a different date."
  refute_stub_called_with "s3 cp"
}

@test "rds download-sql-backup queries the bucket named from infra+identifier for the given date" {
  run run_command bin/rds/v1/download-sql-backup -i "example-infra" -r "example-rds" -e "staging" -d "2026-08-27" <<< "1"
  assert_success
  assert_stub_called_with "s3api list-objects-v2 --bucket example-infra-exampleinfraexamplerdsstaging-sql-backup --query Contents[?contains(LastModified,\`2026-08-27\`)].Key --output json"
}

@test "rds download-sql-backup defaults the date to today when -d is omitted" {
  today="$(date +%Y-%m-%d)"
  run run_command bin/rds/v1/download-sql-backup -i "example-infra" -r "example-rds" -e "staging" <<< "1"
  assert_success
  assert_stub_called_with "contains(LastModified,\`$today\`)"
}
