#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "deploy-build-logs prints usage with no arguments" {
  run --separate-stderr run_command bin/ci/v1/deploy-build-logs
  assert_failure 1
  assert_stderr_contains "Usage: deploy-build-logs"
  assert_output_contains "-I <infrastructure_name>"
}

@test "deploy-build-logs -h shows usage" {
  run --separate-stderr run_command bin/ci/v1/deploy-build-logs -h
  assert_failure 1
  assert_stderr_contains "Usage: deploy-build-logs"
}

@test "deploy-build-logs requires -I" {
  run --separate-stderr run_command bin/ci/v1/deploy-build-logs -z
  assert_failure 1
  assert_stderr_contains "Usage: deploy-build-logs"
}

@test "deploy-build-logs streams log events and reports success" {
  stub_response_file aws-codepipeline-get_pipeline_state ci-v1-pipeline-state.json
  stub_response_file aws-codebuild-batch_get_builds ci-v1-codebuild-batch-get-builds.json
  stub_response_file aws-logs-get_log_events ci-v1-log-events.json

  run --separate-stderr run_command bin/ci/v1/deploy-build-logs -I "example-infra"
  assert_success
  assert_output_contains "Example build log line"
  assert_line $(( ${#lines[@]} - 1 )) "Succeeded"
  assert_stub_called_with "codebuild batch-get-builds --ids example-build-id-0001"
}

@test "deploy-build-logs reports a build failure and exits non-zero" {
  stub_response_file aws-codepipeline-get_pipeline_state ci-v1-pipeline-state-failed.json
  stub_response_file aws-codebuild-batch_get_builds ci-v1-codebuild-batch-get-builds.json
  stub_response_file aws-logs-get_log_events ci-v1-log-events.json

  run --separate-stderr run_command bin/ci/v1/deploy-build-logs -I "example-infra"
  assert_failure 1
  assert_output_contains "Build Failed"
}

@test "deploy-build-logs reports waiting when no log events are available yet" {
  stub_response_file aws-codepipeline-get_pipeline_state ci-v1-pipeline-state.json
  stub_response_file aws-codebuild-batch_get_builds ci-v1-codebuild-batch-get-builds.json
  stub_response_file aws-logs-get_log_events ci-v1-log-events-empty.json

  run --separate-stderr run_command bin/ci/v1/deploy-build-logs -I "example-infra"
  assert_success
  assert_output_contains "Waiting for logs ..."
}
