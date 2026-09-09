#!/usr/bin/env bats

load ../test_helper

# The client name is <resource prefix hash>-<pool>-<client>; ccb69c87 is the
# hash for example-project / example-infra / staging, as pinned by
# test/lib/resource_prefix_hash.bats.
setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  stub_response_file dalmatian-aws-run_command-p-example_account-cognito_idp-list_user_pools v2-cognito-list-user-pools.json
  stub_response_file dalmatian-aws-run_command-p-example_account-cognito_idp-list_user_pool_clients v2-cognito-list-user-pool-clients.json
  stub_response_file dalmatian-aws-run_command-p-example_account-cognito_idp-describe_user_pool_client v2-cognito-describe-user-pool-client.json
  stub_response dalmatian-aws-run_command-p-example_account-configure-get-region "eu-west-2"
}

@test "show-client prints usage with no arguments" {
  run --separate-stderr run_command bin/cognito/v2/show-client
  assert_failure 1
  assert_stderr_contains "Usage: show-client"
  assert_output_contains "-s "
  refute_stub_called_with "cognito-idp"
}

@test "show-client requires infrastructure, environment, pool and client" {
  run --separate-stderr run_command bin/cognito/v2/show-client -i "example-infra" -e "staging" -p "app"
  assert_failure 1
  assert_stderr_contains "Usage: show-client"
  refute_stub_called_with "cognito-idp"
}

@test "show-client -h shows usage" {
  run --separate-stderr run_command bin/cognito/v2/show-client -h
  assert_failure 1
  assert_stderr_contains "Usage: show-client"
}

@test "show-client prints the four environment lines with the secret redacted" {
  run run_command bin/cognito/v2/show-client -i "example-infra" -e "staging" -p "app" -c "web"
  assert_success
  assert_line 0 "COGNITO_REGION=eu-west-2"
  assert_line 1 "COGNITO_USER_POOL_ID=eu-west-2_AppPool01"
  assert_line 2 "COGNITO_CLIENT_ID=1webclientid000000000000000"
  assert_line 3 "COGNITO_CLIENT_SECRET=[redacted - pass -s to show]"
  [ "${#lines[@]}" -eq 4 ]
}

@test "show-client does not ask AWS for the secret unless -s is given" {
  run run_command bin/cognito/v2/show-client -i "example-infra" -e "staging" -p "app" -c "web"
  assert_success
  refute_stub_called_with "describe-user-pool-client"
  case "$output" in
    *example-client-secret-value*) fail "secret was printed without -s" ;;
  esac
}

@test "show-client looks the client up by its platform name in the resolved pool" {
  run run_command bin/cognito/v2/show-client -i "example-infra" -e "staging" -p "app" -c "worker"
  assert_success
  assert_call_args dalmatian aws run-command -p example-account cognito-idp list-user-pool-clients --user-pool-id eu-west-2_AppPool01 --max-results 60
  assert_line 2 "COGNITO_CLIENT_ID=2workerclientid00000000000"
}

@test "show-client -s fetches and prints the secret with a warning on stderr" {
  run --separate-stderr run_command bin/cognito/v2/show-client -i "example-infra" -e "staging" -p "app" -c "web" -s
  assert_success
  assert_call_args dalmatian aws run-command -p example-account cognito-idp describe-user-pool-client --user-pool-id eu-west-2_AppPool01 --client-id 1webclientid000000000000000
  assert_line 3 "COGNITO_CLIENT_SECRET=example-client-secret-value"
  assert_stderr_contains "clear your terminal scrollback"
}

@test "show-client -s warns when the client has no secret" {
  stub_response dalmatian-aws-run_command-p-example_account-cognito_idp-describe_user_pool_client '{ "UserPoolClient": { "ClientId": "1webclientid000000000000000" } }'

  run --separate-stderr run_command bin/cognito/v2/show-client -i "example-infra" -e "staging" -p "app" -c "web" -s
  assert_success
  assert_stderr_contains "has no secret"
  assert_line 3 "COGNITO_CLIENT_SECRET="
}

@test "show-client fails when the client is not in the pool" {
  run --separate-stderr run_command bin/cognito/v2/show-client -i "example-infra" -e "staging" -p "app" -c "missing"
  assert_failure 1
  assert_stderr_contains "Client 'missing' not found in pool 'app'"
  [ -z "$output" ]
  refute_stub_called_with "describe-user-pool-client"
}

@test "show-client fails when the pool does not exist" {
  run --separate-stderr run_command bin/cognito/v2/show-client -i "example-infra" -e "staging" -p "missing" -c "web"
  assert_failure 1
  assert_stderr_contains "Cognito User Pool 'example-project-example-infra-staging-missing' not found"
  [ -z "$output" ]
  refute_stub_called_with "list-user-pool-clients"
}
