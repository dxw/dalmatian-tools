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

@test "rds list-databases prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v1/list-databases
  assert_failure 1
  assert_stderr_contains "Usage: list-databases"
  assert_output_contains "-r <rds_name>"
}

@test "rds list-databases requires an RDS name" {
  run --separate-stderr run_command bin/rds/v1/list-databases -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: list-databases"
}

@test "rds list-databases -h prints usage" {
  run --separate-stderr run_command bin/rds/v1/list-databases -h
  assert_failure 1
  assert_stderr_contains "Usage: list-databases"
}

@test "rds list-databases builds the RDS identifier from infra+rds+env with dashes stripped" {
  run run_command bin/rds/v1/list-databases -i "example-infra" -r "example-rds" -e "staging"
  assert_success
  assert_stub_called_with "ssm get-parameters --names /example-infra/exampleinfraexamplerdsstaging-rds/password --with-decryption"
  assert_stub_called_with "rds describe-db-instances --db-instance-identifier exampleinfraexamplerdsstaging"
}

@test "rds list-databases looks up the ECS instance in the RDS instance's own VPC and starts the db-list session" {
  run run_command bin/rds/v1/list-databases -i "example-infra" -r "example-rds" -e "staging"
  assert_success
  assert_stub_called_with "Name=vpc-id,Values=vpc-0123456789abcdef0"
  assert_stub_called_with "Name=tag:Name,Values=example-infra-staging*"
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0 --document-name exampleinfraexamplerdsstaging-rds-db-list --parameters RootPassword=example-root-password"
}

@test "rds list-databases fails when the RDS lookup fails" {
  stub_exit aws-rds-describe_db_instances 1
  run --separate-stderr run_command bin/rds/v1/list-databases -i "example-infra" -r "example-rds" -e "staging"
  assert_failure
  refute_stub_called_with "ssm start-session"
}

# The script never checks that a Parameter Store lookup actually returned a
# value: an empty Parameters array makes RDS_ROOT_PASSWORD the literal string
# "null" (jq -r on a missing index), which then gets sent on to the ECS
# session unchanged rather than the script erroring out. Existing behaviour of
# the script under test.
@test "rds list-databases passes through a literal 'null' password when Parameter Store has nothing" {
  stub_response_file aws-ssm-get_parameters rds-v1-ssm-get-parameters-empty.json
  run run_command bin/rds/v1/list-databases -i "example-infra" -r "example-rds" -e "staging"
  assert_success
  assert_stub_called_with "RootPassword=null"
}
