#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "deploy-build-logs prints usage with no arguments" {
  run --separate-stderr run_command bin/service/v1/deploy-build-logs
  assert_failure 1
  assert_stderr_contains "Usage: deploy-build-logs"
  assert_output_contains "-i <infrastructure>"
}

@test "deploy-build-logs -h shows usage" {
  run --separate-stderr run_command bin/service/v1/deploy-build-logs -h
  assert_failure 1
  assert_stderr_contains "Usage: deploy-build-logs"
}

@test "deploy-build-logs requires infrastructure, service and environment" {
  run --separate-stderr run_command bin/service/v1/deploy-build-logs -i example-infra
  assert_failure 1
  assert_stderr_contains "Usage: deploy-build-logs"
}

# getopts is "i:e:s:wh", so -w is accepted by the parser, but the case
# statement only handles i/e/s/h -- there is no `w)` branch, so an opt of "w"
# falls through to the `*)` default and calls usage(). Unlike
# service/v1/deploy-status and force-deployment (where -w is both documented
# and implemented) or show-deployment-status (where -w is documented and
# implemented), here -w is neither documented nor functional: it just forces
# a usage/exit-1, the same as any other unrecognised flag.
@test "deploy-build-logs treats -w as an unrecognised flag and shows usage" {
  run --separate-stderr run_command bin/service/v1/deploy-build-logs \
    -i example-infra -s example-service -e staging -w
  assert_failure 1
  assert_stderr_contains "Usage: deploy-build-logs"
}

@test "deploy-build-logs streams log events and reports the final build status" {
  stub_response_file aws-codepipeline-get_pipeline_state service-deploy-pipeline-state.json
  stub_response_file aws-codebuild-batch_get_builds service-deploy-codebuild-batch-get-builds.json
  stub_response_file aws-logs-get_log_events service-deploy-log-events.json

  run --separate-stderr run_command bin/service/v1/deploy-build-logs \
    -i example-infra -s example-service -e staging
  assert_success
  assert_stub_called_with "codepipeline get-pipeline-state --name example-infra-example-service-staging-build-and-deploy"
  assert_stub_called_with "codebuild batch-get-builds --ids example-build-id-0001"
  assert_output_contains "Example build log line"
  assert_line $(( ${#lines[@]} - 1 )) "Succeeded"
}

@test "deploy-build-logs reports a build failure and exits non-zero" {
  stub_response_file aws-codepipeline-get_pipeline_state service-deploy-pipeline-state-failed.json
  stub_response_file aws-codebuild-batch_get_builds service-deploy-codebuild-batch-get-builds.json
  stub_response_file aws-logs-get_log_events service-deploy-log-events.json

  run --separate-stderr run_command bin/service/v1/deploy-build-logs \
    -i example-infra -s example-service -e staging
  assert_failure 1
  assert_output_contains "Build Failed"
}

@test "deploy-build-logs reports waiting when no log events are available yet" {
  stub_response_file aws-codepipeline-get_pipeline_state service-deploy-pipeline-state.json
  stub_response_file aws-codebuild-batch_get_builds service-deploy-codebuild-batch-get-builds.json
  stub_response_file aws-logs-get_log_events service-deploy-log-events-empty.json

  run --separate-stderr run_command bin/service/v1/deploy-build-logs \
    -i example-infra -s example-service -e staging
  assert_success
  assert_output_contains "Waiting for logs ..."
}
