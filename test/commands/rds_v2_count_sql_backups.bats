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

@test "count-sql-backups prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v2/count-sql-backups
  assert_failure 1
  assert_stderr_contains "Usage: count-sql-backups"
}

@test "count-sql-backups requires an RDS name" {
  run --separate-stderr run_command bin/rds/v2/count-sql-backups -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: count-sql-backups"
}

@test "count-sql-backups counts the RDS's backups for the date in the infrastructure backup bucket" {
  run run_command bin/rds/v2/count-sql-backups -i "example-infra" -e "staging" -r "example-rds" -d "2026-08-27"
  assert_success
  assert_output "2"
  assert_call_args dalmatian aws run-command -p example-account s3api list-objects-v2 --bucket ccb69c87-infrastructure-rds-s3-backups --prefix ccb69c87-example-rds.abcdefghijkl.eu-west-2.rds.amazonaws.com/ --query "Contents[?starts_with(LastModified,\`2026-08-27\`)].Key" --output json
}

@test "count-sql-backups prefixes keys with a cluster's reader endpoint" {
  unstub dalmatian-aws-run_command-p-example_account-rds-describe_db_clusters
  stub_response_file dalmatian-aws-run_command-p-example_account-rds-describe_db_clusters v2-rds-describe-db-clusters-aurora-mysql-full.json

  run run_command bin/rds/v2/count-sql-backups -i "example-infra" -e "staging" -r "example-rds" -d "2026-08-27"
  assert_success
  assert_stub_called_with "--prefix ccb69c87-example-rds.cluster-ro-abcdefghijkl.eu-west-2.rds.amazonaws.com/"
}

@test "count-sql-backups prints 0 when nothing matches" {
  stub_response dalmatian-aws-run_command-p-example_account-s3api-list_objects_v2 "null"

  run run_command bin/rds/v2/count-sql-backups -i "example-infra" -e "staging" -r "example-rds" -d "2026-08-27"
  assert_success
  assert_output "0"
}

@test "count-sql-backups defaults the date to today" {
  today="$(date +%Y-%m-%d)"
  run run_command bin/rds/v2/count-sql-backups -i "example-infra" -e "staging" -r "example-rds"
  assert_success
  assert_stub_called_with "starts_with(LastModified,\`$today\`)"
}

@test "count-sql-backups rejects a date that is not a date" {
  run --separate-stderr run_command bin/rds/v2/count-sql-backups -i "example-infra" -e "staging" -r "example-rds" -d '2026`)]'
  assert_failure 1
  assert_stderr_contains "Date must be in the form"
  refute_stub_called_with "list-objects-v2"
}
