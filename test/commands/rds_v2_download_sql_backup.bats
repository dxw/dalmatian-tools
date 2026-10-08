#!/usr/bin/env bats

load ../test_helper

# ccb69c87 is the resource prefix hash for example-project / example-infra /
# staging, as pinned by test/lib/resource_prefix_hash.bats.
setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  stub_rds_not_found dalmatian-aws-run_command-p-example_account-rds-describe_db_clusters DBClusterNotFoundFault
  stub_response_file dalmatian-aws-run_command-p-example_account-rds-describe_db_instances v2-rds-describe-db-instances-postgres.json
  stub_response_file dalmatian-aws-run_command-p-example_account-s3api-list_objects_v2 v2-rds-s3-backup-keys.json
}

BACKUP_HOST="ccb69c87-example-rds.abcdefghijkl.eu-west-2.rds.amazonaws.com"

@test "download-sql-backup prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v2/download-sql-backup
  assert_failure 1
  assert_stderr_contains "Usage: download-sql-backup"
  assert_output_contains "-o <output_file_path>"
}

@test "download-sql-backup requires an RDS name" {
  run --separate-stderr run_command bin/rds/v2/download-sql-backup -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: download-sql-backup"
}

# There is no terminal under bats, so `read -rp` never shows its prompt; the
# numbered listing is what is visible, and "1" on stdin picks the first entry.
@test "download-sql-backup lists the backups without the host prefix and downloads the chosen one to ~/Downloads" {
  run run_command bin/rds/v2/download-sql-backup -i "example-infra" -e "staging" -r "example-rds" -d "2026-08-27" <<< "1"
  assert_success
  assert_output_contains "1	202608270000-app.sql"
  assert_output_contains "2	202608270000-postgres.sql"
  assert_call_args dalmatian aws run-command -p example-account s3 cp "s3://ccb69c87-infrastructure-rds-s3-backups/$BACKUP_HOST/202608270000-app.sql" "$HOME/Downloads/202608270000-app.sql"
}

@test "download-sql-backup honours -o" {
  run run_command bin/rds/v2/download-sql-backup -i "example-infra" -e "staging" -r "example-rds" -d "2026-08-27" -o "$SANDBOX/backup.sql" <<< "2"
  assert_success
  assert_call_args dalmatian aws run-command -p example-account s3 cp "s3://ccb69c87-infrastructure-rds-s3-backups/$BACKUP_HOST/202608270000-postgres.sql" "$SANDBOX/backup.sql"
}

@test "download-sql-backup re-prompts until it gets a listed number" {
  run run_command bin/rds/v2/download-sql-backup -i "example-infra" -e "staging" -r "example-rds" -d "2026-08-27" < <(printf 'x\n0\n3\n2\n')
  assert_success
  assert_stub_called_with "s3 cp s3://ccb69c87-infrastructure-rds-s3-backups/$BACKUP_HOST/202608270000-postgres.sql"
}

@test "download-sql-backup gives up rather than spinning when stdin closes" {
  run run_command bin/rds/v2/download-sql-backup -i "example-infra" -e "staging" -r "example-rds" -d "2026-08-27" < /dev/null
  assert_failure 1
  refute_stub_called_with "s3 cp"
}

@test "download-sql-backup fails and does not download when nothing matches the date" {
  stub_response dalmatian-aws-run_command-p-example_account-s3api-list_objects_v2 "null"

  run --separate-stderr run_command bin/rds/v2/download-sql-backup -i "example-infra" -e "staging" -r "example-rds" -d "2026-08-27" < /dev/null
  assert_failure 1
  assert_stderr_contains "No backups found"
  refute_stub_called_with "s3 cp"
}

@test "download-sql-backup picks with fzf when it is enabled" {
  export DALMATIAN_FZF_ENABLED=1
  stub_response fzf "202608270000-postgres.sql"

  run run_command bin/rds/v2/download-sql-backup -i "example-infra" -e "staging" -r "example-rds" -d "2026-08-27"
  assert_success
  assert_stub_called_with "s3 cp s3://ccb69c87-infrastructure-rds-s3-backups/$BACKUP_HOST/202608270000-postgres.sql"
}

@test "download-sql-backup rejects a date that is not a date" {
  run --separate-stderr run_command bin/rds/v2/download-sql-backup -i "example-infra" -e "staging" -r "example-rds" -d "today"
  assert_failure 1
  assert_stderr_contains "Date must be in the form"
  refute_stub_called_with "list-objects-v2"
}
