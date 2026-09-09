#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-ssm-get_parameters rds-v1-ssm-get-parameters.json
  stub_response_file aws-ec2-describe_instances rds-v1-ec2-describe-instances-single.json
}

@test "aurora list-databases prints usage with no arguments" {
  run --separate-stderr run_command bin/aurora/v1/list-databases
  assert_failure 1
  assert_stderr_contains "Usage: list-databases"
  assert_output_contains "-r <aurora_name>"
}

@test "aurora list-databases requires an RDS name" {
  run --separate-stderr run_command bin/aurora/v1/list-databases -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: list-databases"
}

@test "aurora list-databases -h prints usage" {
  run --separate-stderr run_command bin/aurora/v1/list-databases -h
  assert_failure 1
  assert_stderr_contains "Usage: list-databases"
}

@test "aurora list-databases builds the SSM parameter path from infra+rds+env with an -aurora suffix" {
  run run_command bin/aurora/v1/list-databases -i "example-infra" -r "example-rds" -e "staging"
  assert_success
  assert_stub_called_with "ssm get-parameters --names /example-infra/exampleinfraexamplerdsstaging-aurora/password --with-decryption"
}

# Biggest divergence from the rds twin: rds list-databases hand-rolls its own
# `aws rds describe-db-instances` + `aws ec2 describe-instances --filters
# Name=vpc-id,...` lookup, scoping the ECS instance search to the RDS
# instance's own VPC. aurora list-databases never calls `aws rds
# describe-db-clusters`/`describe-db-instances` at all -- it goes straight to
# the shared pick_ecs_instance helper, which filters ECS instances by
# infra+environment tag alone, with no VPC scoping. Verified directly against
# both scripts.
@test "aurora list-databases never looks up cluster info, and picks the ECS instance by tag alone (no VPC filter)" {
  run run_command bin/aurora/v1/list-databases -i "example-infra" -r "example-rds" -e "staging"
  assert_success
  refute_stub_called_with "describe-db-clusters"
  refute_stub_called_with "describe-db-instances"
  refute_stub_called_with "vpc-id"
  assert_stub_called_with "Name=tag:Name,Values=example-infra-staging*"
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0 --document-name exampleinfraexamplerdsstaging-aurora-db-list --parameters RootPassword=example-root-password"
}

@test "aurora list-databases fails and does not start a session when the parameter lookup fails" {
  stub_exit aws-ssm-get_parameters 1
  run --separate-stderr run_command bin/aurora/v1/list-databases -i "example-infra" -r "example-rds" -e "staging"
  assert_failure
  refute_stub_called_with "ssm start-session"
}

# Same existing bug as the rds twin: the script never checks that Parameter
# Store actually returned a value, so an empty Parameters array makes
# RDS_ROOT_PASSWORD the literal string "null" (jq -r on a missing index),
# which is then passed on to the ECS session unchanged.
@test "aurora list-databases passes through a literal 'null' password when Parameter Store has nothing" {
  stub_response_file aws-ssm-get_parameters rds-v1-ssm-get-parameters-empty.json
  run run_command bin/aurora/v1/list-databases -i "example-infra" -r "example-rds" -e "staging"
  assert_success
  assert_stub_called_with "RootPassword=null"
}
