#!/usr/bin/env bats

load ../test_helper

# The poll loop sleeps 5s between describe-user-import-job calls. Every
# happy-path test stubs the first describe as already terminal, and the
# retry test wants three fast failures, so sleep is shimmed to a no-op.
fake_instant_sleep() {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/bin/sleep"
  chmod +x "$SANDBOX/bin/sleep"
}

write_csv() {
  CSV="$SANDBOX/users.csv"
  cat > "$CSV" <<'CSV'
cognito:username,email,email_verified,name,cognito:mfa_enabled
"alice@example.invalid","alice@example.invalid","TRUE","Alice Example","FALSE"
"bob@example.invalid","bob@example.invalid","TRUE","","FALSE"
CSV
}

setup() {
  setup_sandbox
  use_stubs
  fake_instant_sleep
  export QUIET_MODE=1
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  stub_response_file dalmatian-aws-run_command-p-example_account-cognito_idp-list_user_pools v2-cognito-list-user-pools.json
  stub_response_file dalmatian-aws-run_command-p-example_account-cognito_idp-get_csv_header v2-cognito-get-csv-header.json
  stub_response_file dalmatian-aws-run_command-p-example_account-cognito_idp-describe_user_pool v2-cognito-describe-user-pool-app.json
  stub_response_file dalmatian-aws-run_command-p-example_account-iam-get_role v2-cognito-iam-get-role.json
  stub_response_file dalmatian-aws-run_command-p-example_account-cognito_idp-create_user_import_job v2-cognito-create-user-import-job.json
  stub_response_file dalmatian-aws-run_command-p-example_account-cognito_idp-describe_user_import_job v2-cognito-describe-user-import-job-succeeded.json
  write_csv
}

@test "import-users prints usage with no arguments" {
  run --separate-stderr run_command bin/cognito/v2/import-users
  assert_failure 1
  assert_stderr_contains "Usage: import-users"
  assert_output_contains "-F "
  refute_stub_called_with "cognito-idp"
}

@test "import-users requires infrastructure, environment, pool and a CSV file" {
  run --separate-stderr run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app"
  assert_failure 1
  assert_stderr_contains "Usage: import-users"
  refute_stub_called_with "cognito-idp"
}

@test "import-users refuses a missing CSV before any AWS call" {
  run --separate-stderr run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app" -f "$SANDBOX/missing.csv"
  assert_failure 1
  assert_stderr_contains "does not exist or is not readable"
  refute_stub_called_with "list-infrastructures"
  refute_stub_called_with "cognito-idp"
}

@test "import-users validates the CSV header against the pool's own header" {
  run run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app" -f "$CSV"
  assert_success
  assert_call_args dalmatian aws run-command -p example-account cognito-idp get-csv-header --user-pool-id eu-west-2_AppPool01
}

@test "import-users rejects a CSV whose header does not match and creates nothing" {
  printf 'email,name\n"alice@example.invalid","Alice"\n' > "$CSV"

  run --separate-stderr run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app" -f "$CSV"
  assert_failure 1
  assert_stderr_contains "CSV header does not match the pool's import format"
  refute_stub_called_with "create-user-import-job"
  refute_stub_called_with "curl"
}

@test "import-users tolerates a CRLF header line" {
  printf 'cognito:username,email,email_verified,name,cognito:mfa_enabled\r\n"alice@example.invalid","alice@example.invalid","TRUE","Alice","FALSE"\r\n' > "$CSV"

  run run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app" -f "$CSV"
  assert_success
}

@test "import-users rejects a CSV with a header but no rows" {
  printf 'cognito:username,email,email_verified,name,cognito:mfa_enabled\n' > "$CSV"

  run --separate-stderr run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app" -f "$CSV"
  assert_failure 1
  assert_stderr_contains "has no data rows"
  refute_stub_called_with "create-user-import-job"
}

@test "import-users refuses a populated pool unless -F is given" {
  stub_response dalmatian-aws-run_command-p-example_account-cognito_idp-describe_user_pool '{ "UserPool": { "Id": "eu-west-2_AppPool01", "EstimatedNumberOfUsers": 7 } }'

  run --separate-stderr run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app" -f "$CSV"
  assert_failure 1
  assert_stderr_contains "already contains approximately 7 users"
  assert_stderr_contains "Pass -F"
  refute_stub_called_with "create-user-import-job"

  run run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app" -f "$CSV" -F
  assert_success
  assert_stub_called_with "create-user-import-job"
}

@test "import-users refuses when the user count cannot be read" {
  stub_response dalmatian-aws-run_command-p-example_account-cognito_idp-describe_user_pool '{ "UserPool": { "Id": "eu-west-2_AppPool01" } }'

  run --separate-stderr run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app" -f "$CSV"
  assert_failure 1
  assert_stderr_contains "Could not determine the number of users"
  refute_stub_called_with "create-user-import-job"
}

@test "import-users fails when the platform import role is missing" {
  stub_response dalmatian-aws-run_command-p-example_account-iam-get_role '{}'

  run --separate-stderr run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app" -f "$CSV"
  assert_failure 1
  assert_stderr_contains "Import role 'example-project-example-infra-staging-app-user-import' not found"
  refute_stub_called_with "create-user-import-job"
}

@test "import-users creates the job with the pool's import role" {
  run run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app" -f "$CSV"
  assert_success
  assert_call_args dalmatian aws run-command -p example-account iam get-role --role-name example-project-example-infra-staging-app-user-import
  assert_stub_called_with "cognito-idp create-user-import-job --user-pool-id eu-west-2_AppPool01 --job-name import-"
  assert_stub_called_with "--cloud-watch-logs-role-arn arn:aws:iam::123456789012:role/example-project-example-infra-staging-app-user-import"
}

@test "import-users fails without starting anything when create-user-import-job returns no job" {
  stub_response dalmatian-aws-run_command-p-example_account-cognito_idp-create_user_import_job '{ "UserImportJob": { "Status": "Created" } }'

  run --separate-stderr run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app" -f "$CSV"
  assert_failure 1
  assert_stderr_contains "returned no job ID or upload URL; nothing was started"
  refute_stub_called_with "curl"
  refute_stub_called_with "start-user-import-job"
}

@test "import-users refuses a non-HTTPS upload URL" {
  stub_response dalmatian-aws-run_command-p-example_account-cognito_idp-create_user_import_job '{ "UserImportJob": { "JobId": "import-ExampleJob0001", "PreSignedUrl": "http://example.invalid/upload" } }'

  run --separate-stderr run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app" -f "$CSV"
  assert_failure 1
  assert_stderr_contains "non-HTTPS upload URL"
  refute_stub_called_with "curl"
  refute_stub_called_with "start-user-import-job"
}

@test "import-users uploads the CSV to the presigned URL with the SSE header" {
  run run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app" -f "$CSV"
  assert_success
  assert_call_args curl -fsS -H "x-amz-server-side-encryption: aws:kms" --upload-file "$CSV" "https://example.invalid/import-upload/ExampleJob0001"
}

@test "import-users does not start the job when the upload fails" {
  stub_exit curl 22

  run --separate-stderr run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app" -f "$CSV"
  assert_failure 1
  assert_stderr_contains "Upload of $CSV failed"
  assert_stderr_contains "import-ExampleJob0001 was created but not started"
  refute_stub_called_with "start-user-import-job"
}

@test "import-users starts the job and polls it to completion" {
  QUIET_MODE=0 run --separate-stderr run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app" -f "$CSV"
  assert_success
  assert_call_args dalmatian aws run-command -p example-account cognito-idp start-user-import-job --user-pool-id eu-west-2_AppPool01 --job-id import-ExampleJob0001
  assert_call_args dalmatian aws run-command -p example-account cognito-idp describe-user-import-job --user-pool-id eu-west-2_AppPool01 --job-id import-ExampleJob0001
  assert_output_contains "Job:      import-ExampleJob0001 (Succeeded)"
  assert_output_contains "Rows:     2"
  assert_output_contains "Imported: 2"
  assert_output_contains "Failed:   0"
  assert_output_contains "Message:  Import Job Completed Successfully."
  assert_output_contains "Logs:     /aws/cognito/userpools/eu-west-2_AppPool01/import-ExampleJob0001"
}

@test "import-users exits non-zero when the job finishes with failed rows" {
  stub_response_file dalmatian-aws-run_command-p-example_account-cognito_idp-describe_user_import_job v2-cognito-describe-user-import-job-failed.json
  QUIET_MODE=0 run --separate-stderr run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app" -f "$CSV"
  assert_failure 1
  assert_output_contains "Job:      import-ExampleJob0001 (Failed)"
  assert_output_contains "Failed:   1"
  assert_stderr_contains "Import did not complete cleanly"
}

@test "import-users gives up after three consecutive describe failures" {
  stub_exit dalmatian-aws-run_command-p-example_account-cognito_idp-describe_user_import_job 255

  run --separate-stderr run_command bin/cognito/v2/import-users -i "example-infra" -e "staging" -p "app" -f "$CSV"
  assert_failure 1
  assert_stderr_contains "describe-user-import-job failed (attempt 1 of 3)"
  assert_stderr_contains "describe-user-import-job failed (attempt 2 of 3)"
  assert_stderr_contains "Could not read the status of import job import-ExampleJob0001 after 3 attempts"
  [ "$(grep -c 'describe-user-import-job' "$DALMATIAN_STUB_LOG")" -eq 3 ]
}
