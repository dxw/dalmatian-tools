#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "ecs list-deployments prints usage with no arguments" {
  run --separate-stderr run_command bin/ecs/v1/list-deployments
  assert_failure 1
  assert_stderr_contains "Usage: list-deployments"
  assert_output_contains "-d                     - include Deployment ID"
}

@test "ecs list-deployments requires an environment" {
  run --separate-stderr run_command bin/ecs/v1/list-deployments -i "example-infra"
  assert_failure 1
  assert_stderr_contains "Usage: list-deployments"
}

@test "ecs list-deployments succeeds quietly when the cluster has no services" {
  stub_response_file aws-ecs-list_services ecs-more-list-services-empty.json

  QUIET_MODE=0 run run_command bin/ecs/v1/list-deployments -i "example-infra" -e "staging"
  assert_success
  assert_output_contains "No services found in cluster example-infra-staging"
}

@test "ecs list-deployments fails loudly when the cluster does not exist" {
  stub_exit aws-ecs-list_services 254

  run --separate-stderr run_command bin/ecs/v1/list-deployments -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Failed to list services for cluster example-infra-staging. Does it exist?"
}

@test "ecs list-deployments -s uses the given service name directly, without listing services" {
  stub_response_file aws-ecs-list_service_deployments ecs-more-list-service-deployments-empty.json

  QUIET_MODE=0 run run_command bin/ecs/v1/list-deployments -i "example-infra" -e "staging" -s "example-service"
  assert_success
  assert_output_contains "No deployments found in the last week."
  refute_stub_called_with "ecs list-services"
}

@test "ecs list-deployments prints deployments sorted newest first with computed durations" {
  stub_response_file aws-ecs-list_services ecs-more-list-services.json
  stub_response_file aws-ecs-list_service_deployments ecs-more-list-service-deployments.json

  run run_command bin/ecs/v1/list-deployments -i "example-infra" -e "staging"
  assert_success
  local expected_header
  expected_header=$(printf "%-30s %-10s %-20s %-12s" "SERVICE" "DURATION" "CREATED AT" "STATUS")
  assert_line 0 "$expected_header"
  assert_output_contains "3m 20s"
  assert_output_contains "2m 5s"
  # Newer deployment (createdAt 1700001000, "3m 20s") sorts before the older
  # one (createdAt 1700000000, "2m 5s")
  [[ "$output" == *"3m 20s"*"2m 5s"* ]] || fail "expected the newer (3m 20s) deployment before the older (2m 5s) one, got: $output"
  refute_output_line "DEPLOYMENT ID"
}

@test "ecs list-deployments -d adds a truncated Deployment ID column" {
  stub_response_file aws-ecs-list_services ecs-more-list-services.json
  stub_response_file aws-ecs-list_service_deployments ecs-more-list-service-deployments.json

  run run_command bin/ecs/v1/list-deployments -i "example-infra" -e "staging" -d
  assert_success
  assert_output_contains "DEPLOYMENT ID"
  # Deployment ids are 32 hex characters; the ID column truncates to 19
  assert_output_contains "abcdef1234567890abc"
  assert_output_contains "1234567890abcdef123"
  refute_output_line "abcdef1234567890abcdef1234567890"
}
