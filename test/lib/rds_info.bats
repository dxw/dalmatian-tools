#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
  stub_dalmatian
}

@test "rds_info describes a cluster, giving its reader endpoint as the backup host" {
  stub_response_file dalmatian-aws-run_command-p-example_account-rds-describe_db_clusters v2-rds-describe-db-clusters-aurora-mysql-full.json

  run rds_info -p "example-account" -i "ccb69c87-example-rds"
  assert_success
  [ "$(echo "$output" | jq -r '.type')" == "cluster" ]
  [ "$(echo "$output" | jq -r '.engine')" == "aurora-mysql" ]
  [ "$(echo "$output" | jq -r '.endpoint')" == "ccb69c87-example-rds.cluster-abcdefghijkl.eu-west-2.rds.amazonaws.com" ]
  [ "$(echo "$output" | jq -r '.backup_host')" == "ccb69c87-example-rds.cluster-ro-abcdefghijkl.eu-west-2.rds.amazonaws.com" ]
  [ "$(echo "$output" | jq -r '.master_user_secret_arn')" == "arn:aws:secretsmanager:eu-west-2:123456789012:secret:rds!cluster-00000000-0000-0000-0000-000000000000-AbCdEf" ]
  assert_call_args dalmatian aws run-command -p example-account rds describe-db-clusters --db-cluster-identifier ccb69c87-example-rds
  refute_stub_called_with "describe-db-instances"
}

@test "rds_info falls back to a DB instance when no cluster has the identifier" {
  stub_rds_not_found dalmatian-aws-run_command-p-example_account-rds-describe_db_clusters DBClusterNotFoundFault
  stub_response_file dalmatian-aws-run_command-p-example_account-rds-describe_db_instances v2-rds-describe-db-instances-postgres.json

  run rds_info -p "example-account" -i "ccb69c87-example-rds"
  assert_success
  [ "$(echo "$output" | jq -r '.type')" == "instance" ]
  [ "$(echo "$output" | jq -r '.engine')" == "postgres" ]
  [ "$(echo "$output" | jq -r '.endpoint')" == "ccb69c87-example-rds.abcdefghijkl.eu-west-2.rds.amazonaws.com" ]
  [ "$(echo "$output" | jq -r '.backup_host')" == "ccb69c87-example-rds.abcdefghijkl.eu-west-2.rds.amazonaws.com" ]
  [ "$(echo "$output" | jq -r '.master_username')" == "root" ]
  assert_call_args dalmatian aws run-command -p example-account rds describe-db-instances --db-instance-identifier ccb69c87-example-rds
}

@test "rds_info fails when neither a cluster nor an instance exists" {
  stub_rds_not_found dalmatian-aws-run_command-p-example_account-rds-describe_db_clusters DBClusterNotFoundFault
  stub_rds_not_found dalmatian-aws-run_command-p-example_account-rds-describe_db_instances DBInstanceNotFound

  run --separate-stderr rds_info -p "example-account" -i "ccb69c87-missing"
  assert_failure 1
  assert_stderr_contains "RDS ccb69c87-missing does not exist"
  [ -z "$output" ]
}

@test "rds_info passes a cluster lookup failure through rather than calling the RDS missing" {
  stub_exit dalmatian-aws-run_command-p-example_account-rds-describe_db_clusters 254
  stub_stderr dalmatian-aws-run_command-p-example_account-rds-describe_db_clusters "An error occurred (ExpiredTokenException) when calling the DescribeDBClusters operation: The security token included in the request is expired"

  run --separate-stderr rds_info -p "example-account" -i "ccb69c87-example-rds"
  assert_failure 254
  assert_stderr_contains "ExpiredTokenException"
  case "$stderr" in
    *"does not exist"*) fail "an access failure was reported as a missing RDS" ;;
  esac
  refute_stub_called_with "describe-db-instances"
}

@test "rds_info passes an instance lookup failure through rather than calling the RDS missing" {
  stub_rds_not_found dalmatian-aws-run_command-p-example_account-rds-describe_db_clusters DBClusterNotFoundFault
  stub_exit dalmatian-aws-run_command-p-example_account-rds-describe_db_instances 254
  stub_stderr dalmatian-aws-run_command-p-example_account-rds-describe_db_instances "An error occurred (AccessDenied) when calling the DescribeDBInstances operation: not authorized"

  run --separate-stderr rds_info -p "example-account" -i "ccb69c87-example-rds"
  assert_failure 254
  assert_stderr_contains "AccessDenied"
  case "$stderr" in
    *"does not exist"*) fail "an access failure was reported as a missing RDS" ;;
  esac
}

@test "rds_info requires a profile and an identifier" {
  run --separate-stderr rds_info -p "example-account"
  assert_failure 1
  assert_stderr_contains "Invalid \`rds_info\` function usage"
}
