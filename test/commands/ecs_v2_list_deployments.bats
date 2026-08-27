#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  stub_cli
  export QUIET_MODE=1
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  # resolve_aws_profile goes through two calls: `dalmatian deploy
  # list-infrastructures` (via the stubbed CLI) to work out which account
  # workspace owns example-infra/staging, then a direct (non-CLI) `aws
  # configure list-profiles` to confirm that profile actually exists
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
}

@test "ecs v2 list-deployments prints usage with no arguments" {
  run --separate-stderr run_command bin/ecs/v2/list-deployments
  assert_failure 1
  assert_stderr_contains "Usage: list-deployments"
  assert_output_contains "-d                     - include Deployment ID"
}

@test "ecs v2 list-deployments requires an environment" {
  run --separate-stderr run_command bin/ecs/v2/list-deployments -i "example-infra"
  assert_failure 1
  assert_stderr_contains "Usage: list-deployments"
}

@test "ecs v2 list-deployments builds its cluster name as <project>-<infra>-<env>-infrastructure, unlike v1's <infra>-<env>" {
  # v1's CLUSTER is "$INFRASTRUCTURE_NAME-$ENVIRONMENT". v2 reads
  # project_name from setup.json and builds
  # "$PROJECT_NAME-$INFRASTRUCTURE_NAME-$ENVIRONMENT-infrastructure" instead
  # -- a deliberate difference (v2 clusters are project-qualified), but worth
  # flagging as a divergence between the two command versions.
  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-list_services ecs-more-list-services-empty.json

  run run_command bin/ecs/v2/list-deployments -i "example-infra" -e "staging"
  assert_success
  assert_stub_called_with "ecs list-services --cluster example-project-example-infra-staging-infrastructure"
}

@test "ecs v2 list-deployments dies silently (no 'Does it exist?' message) when the cluster does not exist" {
  # v1 wraps its list-services call in `$(...) || { err ...; exit 1; }`, so a
  # failure gets a friendly "Failed to list services ... Does it exist?"
  # message and a guaranteed exit 1. v2 dropped the `|| { ... }` fallback:
  # `SERVICE_ARNS=$(... | jq ...)` failing just trips `set -e` directly, so
  # the script aborts with whatever exit code the pipeline produced and NO
  # explanatory message at all. This is a real behavioural divergence, not
  # just a cosmetic one.
  stub_exit dalmatian-aws-run_command-p-example_account-ecs-list_services 7

  run --separate-stderr run_command bin/ecs/v2/list-deployments -i "example-infra" -e "staging"
  assert_failure 7
  [ -z "$stderr" ] || fail "expected v2 to fail silently (no error message), got stderr: $stderr"
}

@test "ecs v2 list-deployments -s uses the given service name directly, without listing services or resolving a profile via list-infrastructures" {
  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-list_service_deployments ecs-more-list-service-deployments-empty.json

  QUIET_MODE=0 run run_command bin/ecs/v2/list-deployments -i "example-infra" -e "staging" -s "example-service"
  assert_success
  assert_output_contains "No deployments found in the last week."
  refute_stub_called_with "ecs list-services"
}

@test "ecs v2 list-deployments prints deployments sorted newest first with computed durations, via the CLI wrapper rather than aws directly" {
  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-list_services ecs-more-list-services.json
  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-list_service_deployments ecs-more-list-service-deployments.json

  run run_command bin/ecs/v2/list-deployments -i "example-infra" -e "staging"
  assert_success
  local expected_header
  expected_header=$(printf "%-30s %-10s %-20s %-12s" "SERVICE" "DURATION" "CREATED AT" "STATUS")
  assert_line 0 "$expected_header"
  [[ "$output" == *"3m 20s"*"2m 5s"* ]] || fail "expected the newer (3m 20s) deployment before the older (2m 5s) one, got: $output"
  # Every AWS call for this command goes through
  # "$APP_ROOT/bin/dalmatian" aws run-command, never `aws` directly
  refute_stub_called_with "aws ecs"
}

@test "ecs v2 list-deployments -d adds a truncated Deployment ID column" {
  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-list_services ecs-more-list-services.json
  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-list_service_deployments ecs-more-list-service-deployments.json

  run run_command bin/ecs/v2/list-deployments -i "example-infra" -e "staging" -d
  assert_success
  assert_output_contains "DEPLOYMENT ID"
  assert_output_contains "abcdef1234567890abc"
  assert_output_contains "1234567890abcdef123"
}
