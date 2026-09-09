#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-list_tasks v2-ecs-list-tasks.json
  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-describe_tasks v2-ecs-describe-tasks.json
}

@test "container-access prints usage with no arguments" {
  # usage() sends only its first line to stderr; the option list (lines
  # 9-14 of the script) is plain \`echo\`, so it lands on stdout.
  run --separate-stderr run_command bin/service/v2/container-access
  assert_failure 1
  assert_stderr_contains "Usage: container-access"
  assert_output_contains "-s <service_name>"
}

@test "container-access requires an infrastructure" {
  run --separate-stderr run_command bin/service/v2/container-access -e "staging" -s "example-service"
  assert_failure 1
  assert_stderr_contains "Usage: container-access"
}

@test "container-access requires an environment" {
  run --separate-stderr run_command bin/service/v2/container-access -i "example-infra" -s "example-service"
  assert_failure 1
  assert_stderr_contains "Usage: container-access"
}

@test "container-access requires a service" {
  run --separate-stderr run_command bin/service/v2/container-access -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: container-access"
}

@test "container-access -h shows usage" {
  run --separate-stderr run_command bin/service/v2/container-access -h
  assert_failure 1
  assert_stderr_contains "Usage: container-access"
}

@test "container-access finds the task and container, then execs with the default command" {
  run run_command bin/service/v2/container-access -i "example-infra" -e "staging" -s "example-service"
  assert_success
  assert_stub_called_with "ecs list-tasks --cluster example-project-example-infra-staging-infrastructure --service-name example-service"
  assert_stub_called_with "ecs describe-tasks --cluster example-project-example-infra-staging-infrastructure --task arn:aws:ecs:eu-west-2:123456789012:task/example-cluster/task-abc123"
  assert_stub_called_with "ecs execute-command --cluster example-project-example-infra-staging-infrastructure --task arn:aws:ecs:eu-west-2:123456789012:task/example-cluster/task-abc123 --container app --command /bin/bash --interactive"
}

@test "container-access uses a custom command when -c is given" {
  run run_command bin/service/v2/container-access -i "example-infra" -e "staging" -s "example-service" -c "ls -la"
  assert_success
  assert_stub_called_with "--command ls -la --interactive"
}

@test "container-access runs non-interactively when -n is given" {
  run run_command bin/service/v2/container-access -i "example-infra" -e "staging" -s "example-service" -n
  assert_success
  assert_stub_called_with "--command /bin/bash --non-interactive"
}

@test "container-access fails when no AWS profile matches the infrastructure/environment" {
  stub_response aws-configure-list_profiles "dalmatian-main"

  run --separate-stderr run_command bin/service/v2/container-access -i "example-infra" -e "staging" -s "example-service"
  assert_failure
  assert_stderr_contains "Profile does not exist for example-infra staging"
  refute_stub_called_with "ecs list-tasks"
}
