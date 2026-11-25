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

@test "rds create-database prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v1/create-database
  assert_failure 1
  assert_stderr_contains "Usage: create-database"
  assert_output_contains "-u <user_name>"
}

@test "rds create-database requires a user password and does not start a session" {
  run --separate-stderr run_command bin/rds/v1/create-database \
    -i "example-infra" -r "example-rds" -e "staging" -d "exampledb" -u "exampleuser"
  assert_failure 1
  refute_stub_called_with "ssm start-session"
}

@test "rds create-database -h prints usage and does not start a session" {
  run --separate-stderr run_command bin/rds/v1/create-database -h
  assert_failure 1
  refute_stub_called_with "ssm start-session"
}

@test "rds create-database creates the db with an explicitly given ECS instance" {
  run run_command bin/rds/v1/create-database \
    -i "example-infra" -r "example-rds" -e "staging" \
    -d "exampledb" -u "exampleuser" -P "exampleuserpass" -I "i-0fedcba987654321f"
  assert_success
  assert_stub_called_with "ssm get-parameters --names /example-infra/exampleinfraexamplerdsstaging-rds/password"
  assert_stub_called_with "ssm start-session --target i-0fedcba987654321f --document-name exampleinfraexamplerdsstaging-rds-db-creation --parameters RootPassword=example-root-password,NewDbName=exampledb,NewUserName=exampleuser,NewUserPassword=exampleuserpass"
}

@test "rds create-database picks an ECS instance by infra+environment tag when -I is omitted" {
  run run_command bin/rds/v1/create-database \
    -i "example-infra" -r "example-rds" -e "staging" \
    -d "exampledb" -u "exampleuser" -P "exampleuserpass"
  assert_success
  assert_stub_called_with "Name=tag:Name,Values=example-infra-staging*"
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0"
}

@test "rds create-database tries the next ECS instance when starting the session fails" {
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-two.json
  stub_exit aws-ssm-start_session-target-i_0123456789abcdef0 1

  run --separate-stderr run_command bin/rds/v1/create-database \
    -i "example-infra" -r "example-rds" -e "staging" \
    -d "exampledb" -u "exampleuser" -P "exampleuserpass"
  assert_success
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0"
  assert_stub_called_with "ssm start-session --target i-0fedcba987654321f"
}

@test "rds create-database fails and does not start a session when the password lookup fails" {
  stub_exit aws-ssm-get_parameters 1
  run --separate-stderr run_command bin/rds/v1/create-database \
    -i "example-infra" -r "example-rds" -e "staging" \
    -d "exampledb" -u "exampleuser" -P "exampleuserpass"
  assert_failure
  refute_stub_called_with "ssm start-session"
}
