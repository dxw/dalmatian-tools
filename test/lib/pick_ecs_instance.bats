#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
}

@test "pick_ecs_instance returns the first instance ID by default" {
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-two.json

  run pick_ecs_instance -i "example-infra" -e "staging"
  assert_success
  assert_output "i-0123456789abcdef0"
  assert_stub_called_with "Name=instance-state-code,Values=16 Name=tag:Name,Values=example-infra-staging*"
}

@test "pick_ecs_instance -a returns all running instance IDs across reservations" {
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-two.json

  run pick_ecs_instance -i "example-infra" -e "staging" -a
  assert_success
  assert_line 0 "i-0123456789abcdef0"
  assert_line 1 "i-0fedcba987654321f"
}

@test "pick_ecs_instance -v adds a VPC ID filter" {
  stub_response_file aws-ec2-describe_instances rds-v1-ec2-describe-instances-single.json

  run pick_ecs_instance -i "example-infra" -e "staging" -v "vpc-0123456789abcdef0"
  assert_success
  assert_output "i-0123456789abcdef0"
  assert_stub_called_with "Name=vpc-id,Values=vpc-0123456789abcdef0 Name=instance-state-code,Values=16 Name=tag:Name,Values=example-infra-staging*"
}

@test "pick_ecs_instance returns empty output when no instances match" {
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-empty.json

  run pick_ecs_instance -i "example-infra" -e "staging" -a
  assert_success
  assert_output ""
}

@test "pick_ecs_instance propagates ec2 describe-instances failures" {
  stub_exit aws-ec2-describe_instances 1

  run pick_ecs_instance -i "example-infra" -e "staging" -a
  assert_failure 1
}

@test "pick_ecs_instance works after caller getopts has already advanced OPTIND" {
  stub_response_file aws-ec2-describe_instances rds-v1-ec2-describe-instances-single.json
  OPTIND=5

  run pick_ecs_instance -i "example-infra" -e "staging"
  assert_success
  assert_output "i-0123456789abcdef0"
  assert_stub_called_with "Name=tag:Name,Values=example-infra-staging*"
}

@test "pick_ecs_instance rejects missing required flags" {
  run --separate-stderr pick_ecs_instance -i "example-infra"
  assert_failure 1
  assert_stderr_contains "Invalid \`pick_ecs_instance\` function usage"
}
