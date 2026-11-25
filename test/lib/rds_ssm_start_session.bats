#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
  export QUIET_MODE=1
}

@test "rds_ssm_start_session uses an explicit -I instance and does not query EC2 or retry" {
  stub_exit aws-ssm-start_session 1

  run --separate-stderr rds_ssm_start_session \
    -i "example-infra" -e "staging" -I "i-0fedcba987654321f" \
    -d "example-doc" -p "RootPassword=secret"
  assert_failure 1
  refute_stub_called_with "describe-instances"
  assert_stub_called_with "ssm start-session --target i-0fedcba987654321f --document-name example-doc --parameters RootPassword=secret"
  assert_stderr_contains "Failed to start SSM session on i-0fedcba987654321f"
}

@test "rds_ssm_start_session tries the next ECS instance when the first fails" {
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-two.json
  stub_exit aws-ssm-start_session-target-i_0123456789abcdef0 1

  run --separate-stderr rds_ssm_start_session \
    -i "example-infra" -e "staging" \
    -d "example-doc" -p "RootPassword=secret"
  assert_success
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0 --document-name example-doc --parameters RootPassword=secret"
  assert_stub_called_with "ssm start-session --target i-0fedcba987654321f --document-name example-doc --parameters RootPassword=secret"
  assert_stderr_contains "Failed to start SSM session on i-0123456789abcdef0 (exit 1); trying next instance..."
}

@test "rds_ssm_start_session stops and fails once all ECS instances have been tried" {
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-two.json
  stub_exit aws-ssm-start_session 2

  run --separate-stderr rds_ssm_start_session \
    -i "example-infra" -e "staging" \
    -d "example-doc" -p "RootPassword=secret"
  assert_failure 2
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0"
  assert_stub_called_with "ssm start-session --target i-0fedcba987654321f"
  refute_stub_called_with "--target null"
  assert_stderr_contains "Failed to start SSM session on any available ECS instance"
}

@test "rds_ssm_start_session does not retry on SIGINT (130)" {
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-two.json
  stub_exit aws-ssm-start_session-target-i_0123456789abcdef0 130

  run --separate-stderr rds_ssm_start_session \
    -i "example-infra" -e "staging" \
    -d "example-doc" -p "RootPassword=secret"
  assert_failure 130
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0"
  refute_stub_called_with "ssm start-session --target i-0fedcba987654321f"
}

@test "rds_ssm_start_session fails cleanly when no running ECS instances are found" {
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-empty.json

  run --separate-stderr rds_ssm_start_session \
    -i "example-infra" -e "staging" \
    -d "example-doc" -p "RootPassword=secret"
  assert_failure 1
  refute_stub_called_with "ssm start-session"
  assert_stderr_contains "No running ECS instances found"
}

@test "rds_ssm_start_session rejects missing required flags" {
  run --separate-stderr rds_ssm_start_session -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Invalid \`rds_ssm_start_session\` function usage"
}
