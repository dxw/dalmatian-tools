#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
  stub_dalmatian
  stub_response_file dalmatian-aws-run_command-p-example_account-cognito_idp-list_user_pools v2-cognito-list-user-pools.json
}

@test "cognito_user_pool_id resolves a pool ID from its full name" {
  run cognito_user_pool_id -p "example-account" -n "example-project-example-infra-staging-app"
  assert_success
  assert_output "eu-west-2_AppPool01"
}

@test "cognito_user_pool_id lists pools through the CLI with the given profile" {
  run cognito_user_pool_id -p "example-account" -n "example-project-example-infra-staging-admin"
  assert_success
  assert_output "eu-west-2_AdmPool02"
  assert_call_args dalmatian aws run-command -p example-account cognito-idp list-user-pools --max-results 60
}

@test "cognito_user_pool_id matches the whole name, not a prefix" {
  run --separate-stderr cognito_user_pool_id -p "example-account" -n "example-project-example-infra-staging"
  assert_failure 1
  assert_stderr_contains "Cognito User Pool 'example-project-example-infra-staging' not found"
}

@test "cognito_user_pool_id fails when no pool has that name" {
  run --separate-stderr cognito_user_pool_id -p "example-account" -n "example-project-example-infra-staging-missing"
  assert_failure 1
  assert_stderr_contains "not found"
  [ -z "$output" ]
}

# The function does not test the pipeline itself; it relies on the errexit
# and pipefail every command script sets before calling it. load_function
# turns those off in the test shell, so this test runs it in a shell that has
# them on, the way bin/cognito/v2/* do.
@test "cognito_user_pool_id fails when the CLI call fails" {
  stub_exit dalmatian-aws-run_command-p-example_account-cognito_idp-list_user_pools 1
  export -f cognito_user_pool_id err

  run --separate-stderr bash -e -o pipefail -c 'cognito_user_pool_id -p "example-account" -n "example-project-example-infra-staging-app"'
  assert_failure
  [ -z "$output" ]
}

@test "cognito_user_pool_id refuses to pick between two pools with the same name" {
  stub_response dalmatian-aws-run_command-p-example_account-cognito_idp-list_user_pools <<'JSON'
{
  "UserPools": [
    { "Id": "eu-west-2_Dupe000001", "Name": "example-project-example-infra-staging-app" },
    { "Id": "eu-west-2_Dupe000002", "Name": "example-project-example-infra-staging-app" }
  ]
}
JSON

  run --separate-stderr cognito_user_pool_id -p "example-account" -n "example-project-example-infra-staging-app"
  assert_failure 1
  assert_stderr_contains "More than one Cognito User Pool is named"
  [ -z "$output" ]
}

@test "cognito_user_pool_id requires both a profile and a name" {
  run --separate-stderr cognito_user_pool_id -p "example-account"
  assert_failure 1
  assert_stderr_contains "Invalid \`cognito_user_pool_id\` function usage"
  refute_stub_called_with "list-user-pools"

  run --separate-stderr cognito_user_pool_id -n "example-project-example-infra-staging-app"
  assert_failure 1
  assert_stderr_contains "Invalid \`cognito_user_pool_id\` function usage"
}

@test "cognito_user_pool_id rejects an unknown flag" {
  run --separate-stderr cognito_user_pool_id -z "nope"
  assert_failure 1
  assert_stderr_contains "Invalid \`cognito_user_pool_id\` function usage"
}
