#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  stub_cli
  export QUIET_MODE=1
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-aws-run_command-i-example_infra-e-staging-ec2-describe_instances ec2-describe-instances-two.json
}

@test "ecs v2 ec2-access prints usage with no arguments" {
  run --separate-stderr run_command bin/ecs/v2/ec2-access
  assert_failure 1
  assert_stderr_contains "Usage: ec2-access"
  assert_output_contains "-i <infrastructure>"
}

@test "ecs v2 ec2-access requires an environment" {
  run --separate-stderr run_command bin/ecs/v2/ec2-access -i "example-infra"
  assert_failure 1
  assert_stderr_contains "Usage: ec2-access"
}

@test "ecs v2 ec2-access -l lists the instances and connects to none" {
  run run_command bin/ecs/v2/ec2-access -i "example-infra" -e "staging" -l
  assert_success
  assert_output_contains "i-0123456789abcdef0"
  assert_output_contains "i-0fedcba987654321f"
  refute_stub_called_with "ssm start-session"
}

@test "ecs v2 ec2-access filters instances by tag:Infrastructure/tag:Environment/tag:Project, unlike v1's tag:Name wildcard" {
  # v1 filters with a single `Name=tag:Name,Values="$INFRA-$ENV*"` wildcard
  # match. v2 instead filters on three separate exact-match tags
  # (Infrastructure, Environment, Project), and goes through
  # "$APP_ROOT/bin/dalmatian" aws run-command rather than calling `aws`
  # directly -- a deliberate difference, not drift, but worth calling out
  # since the two versions would behave differently against instances tagged
  # only one of the two ways.
  run run_command bin/ecs/v2/ec2-access -i "example-infra" -e "staging" -l
  assert_success
  assert_stub_called_with "Name=tag:Infrastructure,Values=example-infra"
  assert_stub_called_with "Name=tag:Environment,Values=staging"
  refute_stub_called_with "Name=tag:Name,Values=example-infra-staging*"
  # PROJECT_NAME is read with `jq -c '.project_name'` rather than `jq -r`
  # (list-deployments' v2 script uses -r for the same field), so the JSON
  # string's quote characters are never stripped: the filter actually sent
  # is Values="example-project", literally including the double quotes. That
  # can never match a real tag value, so this filter alone would exclude
  # every instance -- it happens to have no visible effect only because AWS
  # ANDs multiple --filters entries together and Infrastructure/Environment
  # already narrow to the right instances in this fixture.
  assert_stub_called_with 'Name=tag:Project,Values="example-project"'
}

@test "ecs v2 ec2-access connects to the first instance by default" {
  run run_command bin/ecs/v2/ec2-access -i "example-infra" -e "staging"
  assert_success
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0"
}

@test "ecs v2 ec2-access connects to an explicitly given instance" {
  run run_command bin/ecs/v2/ec2-access -i "example-infra" -e "staging" -I "i-0fedcba987654321f"
  assert_success
  assert_stub_called_with "ssm start-session --target i-0fedcba987654321f"
}

@test "ecs v2 ec2-access rejects an instance id that is not running" {
  run --separate-stderr run_command bin/ecs/v2/ec2-access -i "example-infra" -e "staging" -I "i-00000000000000000"
  assert_failure 1
  assert_stderr_contains "was not found or is not running"
}

@test "ecs v2 ec2-access reports when no instances match" {
  stub_response_file dalmatian-aws-run_command-i-example_infra-e-staging-ec2-describe_instances ec2-describe-instances-empty.json

  run --separate-stderr run_command bin/ecs/v2/ec2-access -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "No instances found for Infrastructure 'example-infra' Environment 'staging'"
}

@test "ecs v2 ec2-access -c cannot prompt with no terminal" {
  run --separate-stderr run_command bin/ecs/v2/ec2-access -i "example-infra" -e "staging" -c < /dev/null
  assert_failure
  assert_stderr_contains "there is no terminal to choose one with"
}

@test "ecs v2 ec2-access fails without the session-manager-plugin" {
  local original_path="$PATH"
  PATH="/usr/bin:/bin:/usr/sbin:/sbin"

  run --separate-stderr run_command bin/ecs/v2/ec2-access -i "example-infra" -e "staging"

  PATH="$original_path"

  assert_failure 1
  assert_stderr_contains "requires the \`session-manager-plugin\` to be installed"
}
