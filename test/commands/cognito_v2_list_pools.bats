#!/usr/bin/env bats

load ../test_helper

# Stub keys carry the pool ID, so each describe-user-pool call is answered
# with that pool's own fixture and the test can check IDs and keys line up.
setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  stub_response_file dalmatian-aws-run_command-p-example_account-cognito_idp-list_user_pools v2-cognito-list-user-pools.json
  stub_response_file dalmatian-aws-run_command-p-example_account-cognito_idp-describe_user_pool-user_pool_id-eu_west_2_AppPool01 v2-cognito-describe-user-pool-app.json
  stub_response_file dalmatian-aws-run_command-p-example_account-cognito_idp-describe_user_pool-user_pool_id-eu_west_2_AdmPool02 v2-cognito-describe-user-pool-admin.json
}

@test "list-pools prints usage with no arguments" {
  run --separate-stderr run_command bin/cognito/v2/list-pools
  assert_failure 1
  assert_stderr_contains "Usage: list-pools"
  assert_output_contains "-i <infrastructure>"
  refute_stub_called_with "list-user-pools"
}

@test "list-pools requires an environment" {
  run --separate-stderr run_command bin/cognito/v2/list-pools -i "example-infra"
  assert_failure 1
  assert_stderr_contains "Usage: list-pools"
  refute_stub_called_with "list-user-pools"
}

@test "list-pools requires an infrastructure" {
  run --separate-stderr run_command bin/cognito/v2/list-pools -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: list-pools"
}

@test "list-pools -h shows usage" {
  run --separate-stderr run_command bin/cognito/v2/list-pools -h
  assert_failure 1
  assert_stderr_contains "Usage: list-pools"
}

@test "list-pools lists pools through the resolved profile" {
  run run_command bin/cognito/v2/list-pools -i "example-infra" -e "staging"
  assert_success
  assert_stub_called_with "deploy list-infrastructures"
  assert_call_args dalmatian aws run-command -p example-account cognito-idp list-user-pools --max-results 60
}

@test "list-pools keeps only pools named for this project, infrastructure and environment" {
  run run_command bin/cognito/v2/list-pools -i "example-infra" -e "staging"
  assert_success
  assert_call_args dalmatian aws run-command -p example-account cognito-idp describe-user-pool --user-pool-id eu-west-2_AppPool01
  assert_call_args dalmatian aws run-command -p example-account cognito-idp describe-user-pool --user-pool-id eu-west-2_AdmPool02
  refute_stub_called_with "eu-west-2_OthPool03"
  refute_stub_called_with "eu-west-2_PrdPool04"
  [ "$(echo "$output" | jq -r '.pools | keys | join(",")')" = "admin,app" ]
}

@test "list-pools keys each pool by its short name and shapes the fields" {
  run run_command bin/cognito/v2/list-pools -i "example-infra" -e "staging"
  assert_success
  [ "$(echo "$output" | jq -c '.pools.app')" = '{"id":"eu-west-2_AppPool01","arn":"arn:aws:cognito-idp:eu-west-2:123456789012:userpool/eu-west-2_AppPool01","deletion_protection":"ACTIVE","tier":"ESSENTIALS","estimated_users":0}' ]
  [ "$(echo "$output" | jq -c '.pools.admin')" = '{"id":"eu-west-2_AdmPool02","arn":"arn:aws:cognito-idp:eu-west-2:123456789012:userpool/eu-west-2_AdmPool02","deletion_protection":"INACTIVE","tier":"LITE","estimated_users":12}' ]
}

@test "list-pools falls back to UNKNOWN and 0 when describe-user-pool omits fields" {
  stub_response dalmatian-aws-run_command-p-example_account-cognito_idp-describe_user_pool-user_pool_id-eu_west_2_AppPool01 '{ "UserPool": { "Id": "eu-west-2_AppPool01" } }'

  run run_command bin/cognito/v2/list-pools -i "example-infra" -e "staging"
  assert_success
  [ "$(echo "$output" | jq -c '.pools.app')" = '{"id":"eu-west-2_AppPool01","arn":"","deletion_protection":"UNKNOWN","tier":"UNKNOWN","estimated_users":0}' ]
}

@test "list-pools prints an empty pools object when nothing matches" {
  stub_response dalmatian-aws-run_command-p-example_account-cognito_idp-list_user_pools '{ "UserPools": [] }'

  run run_command bin/cognito/v2/list-pools -i "example-infra" -e "staging"
  assert_success
  [ "$(echo "$output" | jq -c .)" = '{"pools":{}}' ]
  refute_stub_called_with "describe-user-pool"
}

@test "list-pools exits non-zero and prints no JSON when list-user-pools fails" {
  stub_exit dalmatian-aws-run_command-p-example_account-cognito_idp-list_user_pools 255

  run run_command bin/cognito/v2/list-pools -i "example-infra" -e "staging"
  assert_failure
  case "$output" in
    *pools*) fail "expected no JSON on failure, got: $output" ;;
  esac
  refute_stub_called_with "describe-user-pool"
}

@test "list-pools fails when no AWS profile matches the infrastructure and environment" {
  stub_response aws-configure-list_profiles "dalmatian-main"

  run --separate-stderr run_command bin/cognito/v2/list-pools -i "example-infra" -e "staging"
  assert_failure
  assert_stderr_contains "Profile does not exist for example-infra staging"
  refute_stub_called_with "list-user-pools"
}
