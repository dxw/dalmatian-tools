#!/usr/bin/env bats

load ../test_helper

# ccb69c87 is the resource prefix hash for example-project / example-infra /
# staging, as pinned by test/lib/resource_prefix_hash.bats.
setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=0
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  stub_rds_not_found dalmatian-aws-run_command-p-example_account-rds-describe_db_clusters DBClusterNotFoundFault
  stub_response_file dalmatian-aws-run_command-p-example_account-rds-describe_db_instances v2-rds-describe-db-instances-postgres.json
  stub_response_file dalmatian-aws-run_command-p-example_account-secretsmanager-get_secret_value v2-secretsmanager-rds-master-secret.txt
}

@test "get-root-password prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v2/get-root-password
  assert_failure 1
  assert_stderr_contains "Usage: get-root-password"
}

@test "get-root-password requires an RDS name" {
  run --separate-stderr run_command bin/rds/v2/get-root-password -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: get-root-password"
  refute_stub_called_with "secretsmanager"
}

@test "get-root-password reads the RDS-managed master secret of the RDS" {
  run run_command bin/rds/v2/get-root-password -i "example-infra" -e "staging" -r "example-rds"
  assert_success
  assert_call_args dalmatian aws run-command -p example-account rds describe-db-instances --db-instance-identifier ccb69c87-example-rds
  assert_call_args dalmatian aws run-command -p example-account secretsmanager get-secret-value --secret-id 'arn:aws:secretsmanager:eu-west-2:123456789012:secret:rds!db-00000000-0000-0000-0000-000000000000-AbCdEf' --query SecretString --output text
  assert_output_contains "Root username: root"
  assert_output_contains "Root password: example-root-password"
}

@test "get-root-password prints only the password in quiet mode" {
  QUIET_MODE=1 run run_command bin/rds/v2/get-root-password -i "example-infra" -e "staging" -r "example-rds"
  assert_success
  assert_output "example-root-password"
}

@test "get-root-password fails when the RDS has no managed secret" {
  stub_response dalmatian-aws-run_command-p-example_account-rds-describe_db_instances '{"DBInstances": [{"Engine": "postgres", "Endpoint": {"Address": "example"}}]}'

  run --separate-stderr run_command bin/rds/v2/get-root-password -i "example-infra" -e "staging" -r "example-rds"
  assert_failure 1
  assert_stderr_contains "has no RDS-managed root password secret"
  refute_stub_called_with "secretsmanager"
}

@test "get-root-password fails when the RDS does not exist" {
  stub_rds_not_found dalmatian-aws-run_command-p-example_account-rds-describe_db_instances DBInstanceNotFound

  run --separate-stderr run_command bin/rds/v2/get-root-password -i "example-infra" -e "staging" -r "missing"
  assert_failure 1
  assert_stderr_contains "RDS ccb69c87-missing does not exist"
  refute_stub_called_with "secretsmanager"
}
