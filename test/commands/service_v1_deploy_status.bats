#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "deploy-status prints usage with no arguments" {
  run --separate-stderr run_command bin/service/v1/deploy-status
  assert_failure 1
  assert_stderr_contains "Usage: deploy-status"
  assert_output_contains "-i <infrastructure>"
}

@test "deploy-status -h shows usage" {
  run --separate-stderr run_command bin/service/v1/deploy-status -h
  assert_failure 1
  assert_stderr_contains "Usage: deploy-status"
}

@test "deploy-status requires infrastructure, service and environment" {
  run --separate-stderr run_command bin/service/v1/deploy-status -i example-infra
  assert_failure 1
  assert_stderr_contains "Usage: deploy-status"
}

# The -w flag is accepted by getopts and implemented (it execs into the real
# `watch` binary in an infinite polling loop), but it is not documented in
# usage() at all -- only -h/-i/-s/-e are listed. Since -w execs into `watch`,
# that path cannot be exercised in this suite; see "watches ... " comment
# below for what is covered instead.
@test "deploy-status queries the pipeline once and formats each stage's status" {
  stub_response_file aws-codepipeline-get_pipeline_state service-deploy-pipeline-state.json

  run run_command bin/service/v1/deploy-status -i example-infra -s example-service -e staging
  assert_success
  assert_stub_called_with "codepipeline get-pipeline-state --name example-infra-example-service-staging-build-and-deploy"
  assert_line 0 "Source: Succeeded (2026-01-01T00:00:00+00:00)"
  assert_line 1 "Build: Succeeded (2026-01-01T00:05:00+00:00)"
}

@test "deploy-status propagates a failing get-pipeline-state call" {
  stub_exit aws-codepipeline-get_pipeline_state 1

  run --separate-stderr run_command bin/service/v1/deploy-status -i example-infra -s example-service -e staging
  assert_failure
}

# Not tested: passing -w. It sets WATCH=1 and then execs `watch -n5 -x
# /bin/bash -c "pipeline_status ..."`, replacing the process with a real,
# indefinitely-polling `watch` invocation -- there is no terminal state to
# stub that makes it return, so exercising that branch here would hang.
