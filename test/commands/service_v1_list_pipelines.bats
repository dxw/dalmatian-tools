#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-codepipeline-list_pipelines service-deploy-list-pipelines.json
}

@test "list-pipelines prints usage with no arguments" {
  run --separate-stderr run_command bin/service/v1/list-pipelines
  assert_failure 1
  assert_stderr_contains "Usage: list-pipelines"
  assert_output_contains "-i <infrastructure>"
}

@test "list-pipelines -h shows usage" {
  run --separate-stderr run_command bin/service/v1/list-pipelines -h
  assert_failure 1
  assert_stderr_contains "Usage: list-pipelines"
}

@test "list-pipelines requires an infrastructure" {
  run --separate-stderr run_command bin/service/v1/list-pipelines -e staging
  assert_failure 1
  assert_stderr_contains "Usage: list-pipelines"
}

@test "list-pipelines defaults service and environment to match anything" {
  run run_command bin/service/v1/list-pipelines -i example-infra
  assert_success
  assert_output_contains "example-infra-example-service-staging-build-and-deploy"
  assert_output_contains "example-infra-other-service-staging-build-and-deploy"
  refute_output_line "other-infra-example-service-staging-build-and-deploy"
}

@test "list-pipelines filters to the exact pipeline when -s and -e are given" {
  run run_command bin/service/v1/list-pipelines -i example-infra -s example-service -e staging
  assert_success
  assert_output "example-infra-example-service-staging-build-and-deploy"
}

@test "list-pipelines prints nothing, and still exits 0, when nothing matches" {
  run run_command bin/service/v1/list-pipelines -i totally-different-infra
  assert_success
  assert_output ""
}

@test "list-pipelines propagates a failing list-pipelines call" {
  stub_exit aws-codepipeline-list_pipelines 1

  run --separate-stderr run_command bin/service/v1/list-pipelines -i example-infra
  assert_failure
}
