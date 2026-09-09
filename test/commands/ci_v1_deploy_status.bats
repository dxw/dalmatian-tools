#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "deploy-status -h shows usage" {
  run --separate-stderr run_command bin/ci/v1/deploy-status -h
  assert_failure 1
  assert_stderr_contains "Usage: deploy-status"
  assert_output_contains "-w <watch>"
}

@test "deploy-status rejects an unrecognised flag" {
  run --separate-stderr run_command bin/ci/v1/deploy-status -z
  assert_failure 1
  assert_stderr_contains "Usage: deploy-status"
}

@test "deploy-status with no arguments queries the pipeline once, not usage" {
  # Unlike most other commands in this suite, there is no leading
  # \`$# -eq 0\` guard: -w/-h are the only recognised flags, and neither is
  # required, so a bare invocation runs the live pipeline query.
  stub_response_file aws-codepipeline-get_pipeline_state ci-v1-pipeline-state.json

  run run_command bin/ci/v1/deploy-status
  assert_success
  assert_stub_called_with "codepipeline get-pipeline-state --name ci-terraform-build-pipeline"
  assert_output_contains "Source: Succeeded (2026-01-01T00:00:00+00:00)"
  assert_output_contains "Build: Succeeded (2026-01-01T00:05:00+00:00)"
  assert_output_contains "  - Build-example-infra: Succeeded (2026-01-01T00:05:00+00:00)"
}

@test "deploy-status propagates a failing pipeline-state call" {
  stub_exit aws-codepipeline-get_pipeline_state 1

  run --separate-stderr run_command bin/ci/v1/deploy-status
  assert_failure
}
