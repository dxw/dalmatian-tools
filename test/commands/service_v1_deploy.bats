#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "deploy prints usage with no arguments" {
  run --separate-stderr run_command bin/service/v1/deploy
  assert_failure 1
  assert_stderr_contains "Usage: deploy"
  assert_output_contains "-i <infrastructure>"
}

@test "deploy -h shows usage" {
  run --separate-stderr run_command bin/service/v1/deploy -h
  assert_failure 1
  assert_stderr_contains "Usage: deploy"
}

@test "deploy requires an infrastructure" {
  run --separate-stderr run_command bin/service/v1/deploy -s example-service -e staging
  assert_failure 1
  assert_stderr_contains "Usage: deploy"
  refute_stub_called_with "start-pipeline-execution"
}

@test "deploy requires a service" {
  run --separate-stderr run_command bin/service/v1/deploy -i example-infra -e staging
  assert_failure 1
  assert_stderr_contains "Usage: deploy"
  refute_stub_called_with "start-pipeline-execution"
}

@test "deploy requires an environment" {
  run --separate-stderr run_command bin/service/v1/deploy -i example-infra -s example-service
  assert_failure 1
  assert_stderr_contains "Usage: deploy"
  refute_stub_called_with "start-pipeline-execution"
}

@test "deploy starts the pipeline execution named from -i/-s/-e" {
  run run_command bin/service/v1/deploy -i example-infra -s example-service -e staging
  assert_success
  assert_stub_called_with "codepipeline start-pipeline-execution --name example-infra-example-service-staging-build-and-deploy"
}

@test "deploy propagates a failing start-pipeline-execution call" {
  stub_exit aws-codepipeline-start_pipeline_execution 1

  run --separate-stderr run_command bin/service/v1/deploy -i example-infra -s example-service -e staging
  assert_failure
}

@test "deploy logs a confirmation on success when not quiet" {
  QUIET_MODE=0 run run_command bin/service/v1/deploy -i example-infra -s example-service -e staging
  assert_success
  assert_line 0 $'\033[0;36m==>\033[0m deploying example-service in staging'
}
