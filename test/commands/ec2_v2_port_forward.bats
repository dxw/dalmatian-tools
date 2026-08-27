#!/usr/bin/env bats

load ../test_helper

# port-forward ends with `"$APP_ROOT/bin/dalmatian" aws run-command -i ... -e
# ... ssm start-session --document-name AWS-StartPortForwardingSession ...`,
# an interactive session. stub_cli intercepts that call, so the
# picking/validation logic up to and including the exact ssm invocation is
# fully covered here; this file stops at the point the real script would
# hand off to an interactive terminal.

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  stub_response_file dalmatian-aws-run_command ec2-describe-instances-one.json
}

@test "port-forward prints usage with no arguments" {
  run --separate-stderr run_command bin/ec2/v2/port-forward
  assert_failure 1
  assert_stderr_contains "Usage: port-forward"
  assert_output_contains "-R <remote_port>"
}

@test "port-forward -l still requires both infrastructure and environment" {
  run --separate-stderr run_command bin/ec2/v2/port-forward -i "example-infra" -l
  assert_failure 1
  assert_stderr_contains "Usage: port-forward"
}

@test "port-forward requires remote and local ports when not listing" {
  run --separate-stderr run_command bin/ec2/v2/port-forward -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: port-forward"
}

@test "port-forward -h shows usage" {
  run --separate-stderr run_command bin/ec2/v2/port-forward -h
  assert_failure 1
  assert_stderr_contains "Usage: port-forward"
}

@test "port-forward -l lists the running instances and connects to none" {
  run run_command bin/ec2/v2/port-forward -i "example-infra" -e "staging" -l
  assert_success
  assert_output_contains "i-0123456789abcdef0"
  refute_stub_called_with "ssm start-session"
}

@test "port-forward queries instances with the given infrastructure and environment" {
  run run_command bin/ec2/v2/port-forward -i "example-infra" -e "staging" -l
  assert_success
  assert_stub_called_with "aws run-command -i example-infra -e staging ec2 describe-instances --filters Name=instance-state-code,Values=16"
}

@test "port-forward starts a forwarding session to the sole instance with the given ports" {
  run run_command bin/ec2/v2/port-forward -i "example-infra" -e "staging" -R 5432 -L 15432
  assert_success
  assert_stub_called_with "aws run-command -i example-infra -e staging ssm start-session --document-name AWS-StartPortForwardingSession --target i-0123456789abcdef0 --parameters portNumber=5432,localPortNumber=15432"
}

@test "port-forward starts a forwarding session to an explicitly given instance" {
  stub_response_file dalmatian-aws-run_command ec2-describe-instances-two.json

  run run_command bin/ec2/v2/port-forward -i "example-infra" -e "staging" -I "i-0fedcba987654321f" -R 5432 -L 15432
  assert_success
  assert_stub_called_with "--target i-0fedcba987654321f --parameters portNumber=5432,localPortNumber=15432"
}

@test "port-forward rejects an instance id that is not running" {
  stub_response_file dalmatian-aws-run_command ec2-describe-instances-two.json

  run --separate-stderr run_command bin/ec2/v2/port-forward -i "example-infra" -e "staging" -I "i-00000000000000000" -R 5432 -L 15432
  assert_failure 1
  assert_stderr_contains "was not found or is not running"
  refute_stub_called_with "ssm start-session"
}

@test "port-forward reports no instances found" {
  stub_response_file dalmatian-aws-run_command ec2-describe-instances-empty.json

  run --separate-stderr run_command bin/ec2/v2/port-forward -i "example-infra" -e "staging" -R 5432 -L 15432
  assert_failure 1
  assert_stderr_contains "No instances found for Infrastructure 'example-infra' Environment 'staging'"
}

@test "port-forward cannot prompt with no terminal when multiple instances are found" {
  stub_response_file dalmatian-aws-run_command ec2-describe-instances-two.json

  run --separate-stderr run_command bin/ec2/v2/port-forward -i "example-infra" -e "staging" -R 5432 -L 15432 < /dev/null
  assert_failure
  assert_stderr_contains "there is no terminal to choose one with"
}

@test "port-forward fails without the session-manager-plugin" {
  # session-manager-plugin is checked via `command -v`, a PATH lookup rather
  # than a stub hash, so it is exercised with a restricted PATH the way
  # ecs_ec2_access.bats does for the v1 equivalent.
  local original_path="$PATH"
  PATH="/usr/bin:/bin:/usr/sbin:/sbin"

  run --separate-stderr run_command bin/ec2/v2/port-forward -i "example-infra" -e "staging" -R 5432 -L 15432

  PATH="$original_path"

  assert_failure 1
  assert_stderr_contains "requires the \`session-manager-plugin\` to be installed"
}
