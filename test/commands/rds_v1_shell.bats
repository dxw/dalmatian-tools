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

@test "rds shell prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v1/shell
  assert_failure 1
  assert_stderr_contains "Usage: dalmatian v1 shell [OPTIONS]"
  assert_output_contains "-r <rds_name>"
}

@test "rds shell requires an RDS name" {
  run --separate-stderr run_command bin/rds/v1/shell -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: dalmatian v1 shell [OPTIONS]"
}

@test "rds shell -h prints usage" {
  run --separate-stderr run_command bin/rds/v1/shell -h
  assert_failure 1
  assert_stderr_contains "Usage: dalmatian v1 shell [OPTIONS]"
}

@test "rds shell -l lists ECS instances and exits without touching SSM or RDS" {
  run run_command bin/rds/v1/shell -i "example-infra" -r "example-rds" -e "staging" -l
  assert_success
  assert_stub_called_with "Name=tag:Name,Values=example-infra-staging*"
  assert_output_contains "i-0123456789abcdef0"
  refute_stub_called_with "ssm get-parameters"
  refute_stub_called_with "describe-db-instances"
  refute_stub_called_with "ssm start-session"
}

@test "rds shell builds the -rds identifiers and starts the session on an explicit -I instance" {
  run run_command bin/rds/v1/shell \
    -i "example-infra" -r "example-rds" -e "staging" -I "i-0fedcba987654321f"
  assert_success
  assert_stub_called_with "ssm get-parameters --names /example-infra/exampleinfraexamplerdsstaging-rds/password"
  assert_stub_called_with "rds describe-db-instances --db-instance-identifier exampleinfraexamplerdsstaging"
  assert_stub_called_with "ssm start-session --target i-0fedcba987654321f --document-name exampleinfraexamplerdsstaging-rds-shell --parameters RootPassword=example-root-password"
  refute_stub_called_with "describe-instances"
}

@test "rds shell does not fall back to other instances when explicit -I fails" {
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-two.json
  stub_exit aws-ssm-start_session 1

  run --separate-stderr run_command bin/rds/v1/shell \
    -i "example-infra" -r "example-rds" -e "staging" -I "i-0fedcba987654321f"
  assert_failure 1
  refute_stub_called_with "describe-instances"
  refute_stub_called_with "ssm start-session --target i-0123456789abcdef0"
}

@test "rds shell falls back to the next running ECS instance when starting the session fails" {
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-two.json
  stub_exit aws-ssm-start_session-target-i_0123456789abcdef0 1

  run --separate-stderr run_command bin/rds/v1/shell -i "example-infra" -r "example-rds" -e "staging"
  assert_success
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0 --document-name exampleinfraexamplerdsstaging-rds-shell --parameters RootPassword=example-root-password"
  assert_stub_called_with "ssm start-session --target i-0fedcba987654321f --document-name exampleinfraexamplerdsstaging-rds-shell --parameters RootPassword=example-root-password"
}

@test "rds shell fails when all candidate ECS instances fail to start a session" {
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-two.json
  stub_exit aws-ssm-start_session 1

  run --separate-stderr run_command bin/rds/v1/shell -i "example-infra" -r "example-rds" -e "staging"
  assert_failure 1
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0"
  assert_stub_called_with "ssm start-session --target i-0fedcba987654321f"
  refute_stub_called_with "--target null"
}

@test "rds shell fails when no running ECS instances exist" {
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-empty.json

  run --separate-stderr run_command bin/rds/v1/shell -i "example-infra" -r "example-rds" -e "staging"
  assert_failure 1
  refute_stub_called_with "ssm start-session"
}

@test "rds shell fails and does not start a session when the password lookup fails" {
  stub_exit aws-ssm-get_parameters 1
  run --separate-stderr run_command bin/rds/v1/shell -i "example-infra" -r "example-rds" -e "staging"
  assert_failure
  refute_stub_called_with "ssm start-session"
}
