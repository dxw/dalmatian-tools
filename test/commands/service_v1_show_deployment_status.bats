#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "show-deployment-status prints usage with no arguments" {
  run --separate-stderr run_command bin/service/v1/show-deployment-status
  assert_failure 1
  assert_stderr_contains "Usage: show-deployment-status"
  assert_output_contains "-i <infrastructure>"
}

@test "show-deployment-status -h shows usage" {
  run --separate-stderr run_command bin/service/v1/show-deployment-status -h
  assert_failure 1
  assert_stderr_contains "Usage: show-deployment-status"
}

@test "show-deployment-status requires infrastructure, service and environment" {
  run --separate-stderr run_command bin/service/v1/show-deployment-status -i example-infra -s example-service
  assert_failure 1
  assert_stderr_contains "Usage: show-deployment-status"
}

@test "show-deployment-status queries the pipeline named from -i/-s/-e and formats each action" {
  stub_response_file aws-codepipeline-get_pipeline_state service-deploy-pipeline-state.json

  run run_command bin/service/v1/show-deployment-status -i example-infra -s example-service -e staging
  assert_success
  assert_stub_called_with "codepipeline get-pipeline-state --name example-infra-example-service-staging-build-and-deploy"
  assert_output_contains "Action: Source"
  assert_output_contains "Action: Build"
  assert_output_contains "Status: Succeeded"
  assert_output_contains "pipeline id: example-pipeline-execution-id"
}

@test "show-deployment-status propagates a failing get-pipeline-state call" {
  stub_exit aws-codepipeline-get_pipeline_state 1

  run --separate-stderr run_command bin/service/v1/show-deployment-status -i example-infra -s example-service -e staging
  assert_failure
}

# Unlike deploy-status/force-deployment/deploy-build-logs (whose getopts
# strings all include "w"), this script's optstring is "i:e:s:h" with no w at
# all -- so -w is not merely undocumented or unimplemented, it is rejected
# outright by getopts as an illegal option before usage() is even reached via
# the normal "*)" case (getopts itself prints "illegal option -- w" and the
# `*)` case still fires, since an unknown opt is reported as `?`).
@test "show-deployment-status rejects -w as an illegal option" {
  run --separate-stderr run_command bin/service/v1/show-deployment-status \
    -i example-infra -s example-service -e staging -w
  assert_failure 1
  assert_stderr_contains "Usage: show-deployment-status"
}
