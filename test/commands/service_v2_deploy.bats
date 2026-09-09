#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
}

@test "deploy prints usage with no arguments" {
  # usage() sends only its first line to stderr; the option list (lines
  # 9-12 of the script) is plain \`echo\`, so it lands on stdout.
  run --separate-stderr run_command bin/service/v2/deploy
  assert_failure 1
  assert_stderr_contains "Usage: deploy"
  assert_output_contains "-s <service>"
}

@test "deploy requires an infrastructure" {
  run --separate-stderr run_command bin/service/v2/deploy -e "staging" -s "example-service"
  assert_failure 1
  assert_stderr_contains "Usage: deploy"
}

@test "deploy requires an environment" {
  run --separate-stderr run_command bin/service/v2/deploy -i "example-infra" -s "example-service"
  assert_failure 1
  assert_stderr_contains "Usage: deploy"
}

@test "deploy requires a service" {
  run --separate-stderr run_command bin/service/v2/deploy -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: deploy"
}

@test "deploy -h shows usage" {
  run --separate-stderr run_command bin/service/v2/deploy -h
  assert_failure 1
  assert_stderr_contains "Usage: deploy"
}

@test "deploy starts a pipeline execution named from project, infrastructure, environment and service" {
  run run_command bin/service/v2/deploy -i "example-infra" -e "staging" -s "example-service"
  assert_success
  assert_stub_called_with "aws run-command -i example-infra -e staging codepipeline start-pipeline-execution --name example-project-example-infra-staging-ecs-service-example-service"
}

@test "deploy propagates a failing dalmatian call" {
  stub_exit dalmatian-aws-run_command 3

  run run_command bin/service/v2/deploy -i "example-infra" -e "staging" -s "example-service"
  assert_failure 3
}

@test "deploy does not call the CLI when validation fails" {
  run run_command bin/service/v2/deploy -i "example-infra"
  refute_stub_called_with "codepipeline start-pipeline-execution"
}
