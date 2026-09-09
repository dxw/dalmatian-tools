#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  stub_response_file dalmatian-aws-run_command-p-example_account-cognito_idp-list_user_pools v2-cognito-list-user-pools.json
  stub_response_file dalmatian-aws-run_command-p-example_account-cognito_idp-get_csv_header v2-cognito-get-csv-header.json
  stub_response_file dalmatian-aws-run_command-p-example_account-cognito_idp-list_users v2-cognito-list-users.json
  OUT_DIR="$SANDBOX/export"
  mkdir -p "$OUT_DIR"
  CSV="$OUT_DIR/users.csv"
}

@test "export-users prints usage with no arguments" {
  run --separate-stderr run_command bin/cognito/v2/export-users
  assert_failure 1
  assert_stderr_contains "Usage: export-users"
  assert_output_contains "-o <csv_file>"
  refute_stub_called_with "cognito-idp"
}

@test "export-users requires infrastructure, environment, pool and an output file" {
  run --separate-stderr run_command bin/cognito/v2/export-users -i "example-infra" -e "staging" -p "app"
  assert_failure 1
  assert_stderr_contains "Usage: export-users"
  refute_stub_called_with "cognito-idp"
}

@test "export-users refuses to overwrite an existing file before any AWS call" {
  echo "keep me" > "$CSV"

  run --separate-stderr run_command bin/cognito/v2/export-users -i "example-infra" -e "staging" -p "app" -o "$CSV"
  assert_failure 1
  assert_stderr_contains "already exists; refusing to overwrite"
  refute_stub_called_with "list-infrastructures"
  [ "$(cat "$CSV")" = "keep me" ]
}

@test "export-users writes the pool's header then one row per user" {
  run run_command bin/cognito/v2/export-users -i "example-infra" -e "staging" -p "app" -o "$CSV"
  assert_success
  assert_call_args dalmatian aws run-command -p example-account cognito-idp get-csv-header --user-pool-id eu-west-2_AppPool01
  assert_call_args dalmatian aws run-command -p example-account cognito-idp list-users --user-pool-id eu-west-2_AppPool01

  local -a rows
  mapfile -t rows < "$CSV"
  [ "${#rows[@]}" -eq 3 ]
  [ "${rows[0]}" = "cognito:username,email,email_verified,name,cognito:mfa_enabled" ]
  [ "${rows[1]}" = '"alice@example.invalid","alice@example.invalid","TRUE","Alice Example","FALSE"' ]
  [ "${rows[2]}" = '"bob@example.invalid","bob@example.invalid","TRUE","","FALSE"' ]
}

@test "export-users writes a file readable only by its owner" {
  run run_command bin/cognito/v2/export-users -i "example-infra" -e "staging" -p "app" -o "$CSV"
  assert_success
  [ -n "$(find "$CSV" -perm 600)" ]
}

@test "export-users leaves no temporary file behind" {
  run run_command bin/cognito/v2/export-users -i "example-infra" -e "staging" -p "app" -o "$CSV"
  assert_success
  [ "$(ls -A "$OUT_DIR")" = "users.csv" ]
}

@test "export-users reports the row count and warns about personal data" {
  QUIET_MODE=0 run --separate-stderr run_command bin/cognito/v2/export-users -i "example-infra" -e "staging" -p "app" -o "$CSV"
  assert_success
  assert_output_contains "Wrote 2 users to $CSV"
  assert_stderr_contains "This file contains personal data"
}

@test "export-users writes only the header for an empty pool" {
  stub_response dalmatian-aws-run_command-p-example_account-cognito_idp-list_users '{ "Users": [] }'
  QUIET_MODE=0 run run_command bin/cognito/v2/export-users -i "example-infra" -e "staging" -p "app" -o "$CSV"
  assert_success
  [ "$(wc -l < "$CSV" | tr -d ' ')" = "1" ]
  assert_output_contains "Wrote 0 users"
}

@test "export-users fails and writes nothing when the pool does not exist" {
  run --separate-stderr run_command bin/cognito/v2/export-users -i "example-infra" -e "staging" -p "missing" -o "$CSV"
  assert_failure 1
  assert_stderr_contains "Cognito User Pool 'example-project-example-infra-staging-missing' not found"
  [ ! -e "$CSV" ]
  [ -z "$(ls -A "$OUT_DIR")" ]
}

@test "export-users leaves no file behind when list-users fails" {
  stub_exit dalmatian-aws-run_command-p-example_account-cognito_idp-list_users 255

  run run_command bin/cognito/v2/export-users -i "example-infra" -e "staging" -p "app" -o "$CSV"
  assert_failure
  [ ! -e "$CSV" ]
  [ -z "$(ls -A "$OUT_DIR")" ]
}
