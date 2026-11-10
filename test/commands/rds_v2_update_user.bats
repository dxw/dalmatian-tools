#!/usr/bin/env bats
# The task scripts are matched literally, $DB_PASSWORD and all, because the
# container expands them, not this shell
# shellcheck disable=SC2016

load ../test_helper
load ../rds_v2_task_helper

CLUSTERS=dalmatian-aws-run_command-p-example_account-rds-describe_db_clusters
INSTANCES=dalmatian-aws-run_command-p-example_account-rds-describe_db_instances
GET_PARAMETER=dalmatian-aws-run_command-p-example_account-ssm-get_parameter-name-_example_infra_staging_rds_example_rds_app_user_password
STORED_VERSION="$GET_PARAMETER-query-Parameter_Version"
PREVIOUS_VALUE="${GET_PARAMETER}_5-with_decryption"
PUT_SECRET=dalmatian-aws-put_secret
RUN_COMMAND=dalmatian-utilities-run_command
PARAMETER_NAME=/example-infra/staging/rds/example-rds/app_user/password

# ccb69c87 is the resource prefix hash for example-project / example-infra /
# staging, as pinned by test/lib/resource_prefix_hash.bats.
setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  stub_rds_not_found "$CLUSTERS" DBClusterNotFoundFault
  stub_response_file "$INSTANCES" v2-rds-describe-db-instances-postgres.json
  stub_response dalmatian-aws-run_command-p-example_account-configure-get-region "eu-west-2"
  stub_response "$STORED_VERSION" "5"
  stub_response "$PREVIOUS_VALUE" "$(fake_password previous)"
  stub_capture_stdin "$PUT_SECRET"
}

use_cluster() {
  unstub "$CLUSTERS"
  stub_response_file "$CLUSTERS" v2-rds-describe-db-clusters-aurora-mysql-full.json
}

stub_no_stored_password() {
  unstub "$STORED_VERSION"
  stub_exit "$STORED_VERSION" 254
  stub_stderr "$STORED_VERSION" "An error occurred (ParameterNotFound) when calling the GetParameter operation: "
}

put_secret_calls() {
  grep -c '^dalmatian aws put-secret ' "$DALMATIAN_STUB_LOG" || true
}

assert_restored() {
  assert_call_args dalmatian aws run-command -p example-account ssm get-parameter --name "$PARAMETER_NAME:5" --with-decryption --query Parameter.Value --output text
  [ "$(put_secret_calls)" -eq 2 ] || fail "expected 2 put-secret calls, got $(put_secret_calls)"
  [ "$(grep '^dalmatian aws put-secret ' "$DALMATIAN_STUB_ARGV_LOG" | tail -n 1)" == "dalmatian aws put-secret -i example-infra -e staging -n rds/example-rds/app_user/password" ] \
    || fail "restored to the wrong place: $(grep '^dalmatian aws put-secret ' "$DALMATIAN_STUB_ARGV_LOG" | tail -n 1)"
  [ "$(stub_stdin "$PUT_SECRET")" == "$(fake_password previous)" ] || fail "restored the wrong value"
}

# After stub_task_outcome: put-secret succeeds until the task has run, then
# fails, so the restore's write fails but the first write does not
fail_put_secret_after_task() {
  mv "$SANDBOX/cli/bin/dalmatian" "$SANDBOX/cli/outcome-wrapper"
  cat > "$SANDBOX/cli/bin/dalmatian" <<WRAPPER
#!/usr/bin/env bash
if [ "\${1-} \${2-}" == "utilities run-command" ]
then
  printf '1\\n' > "$DALMATIAN_STUB_RESPONSES/$PUT_SECRET.exit"
fi
exec "$SANDBOX/cli/outcome-wrapper" "\$@"
WRAPPER
  chmod +x "$SANDBOX/cli/bin/dalmatian"
}

assert_unknown_outcome() {
  [ "$(put_secret_calls)" -eq 1 ] || fail "expected 1 put-secret call, got $(put_secret_calls)"
  refute_stub_called_with "--with-decryption"
  refute_stub_called_with "delete-parameter"
  assert_stderr_contains "may still have the old password"
  assert_stderr_contains "update-user again"
}

@test "update-user prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v2/update-user
  assert_failure 1
  assert_stderr_contains "Usage: update-user"
}

@test "update-user requires a user name" {
  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds"
  assert_failure 1
  assert_stderr_contains "Usage: update-user"
  refute_stub_called_with "put-secret"
}

@test "update-user asks for confirmation and does nothing on no" {
  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" <<< "n"
  assert_success
  assert_stderr_contains "breaks anything using app_user until it picks up the new password"
  refute_stub_called_with "put-secret"
  refute_stub_called_with "utilities run-command"
}

@test "update-user goes ahead on yes" {
  stub_task_outcome "exited 0"

  run run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" <<< "y"
  assert_success
  [ "$(put_secret_calls)" -eq 1 ]
  assert_stub_called_with "utilities run-command"
}

@test "update-user writes a new password and alters the user on Postgres" {
  unset QUIET_MODE
  stub_task_outcome "exited 0"

  run run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_success
  assert_call_args dalmatian aws put-secret -i example-infra -e staging -n rds/example-rds/app_user/password
  [ "$(put_secret_calls)" -eq 1 ]
  [[ "$(stub_stdin "$PUT_SECRET")" =~ ^[A-Za-z0-9]{32}$ ]] || fail "unexpected generated password: $(stub_stdin "$PUT_SECRET")"
  assert_output_contains "$PARAMETER_NAME"
  assert_output_contains "until it picks up the new password"
  refute_stub_called_with "--with-decryption"

  local value
  value="$(fake_password user)"
  run_task_script "$value" "1"
  grep -qxF -- "ccb69c87-example-rds.abcdefghijkl.eu-west-2.rds.amazonaws.com" "$SANDBOX/psql.args"
  grep -qxF -- "password=$value" "$SANDBOX/psql.args"
  [ "$(cat "$SANDBOX/psql.stdin")" == "ALTER USER \"app_user\" WITH PASSWORD :'password';" ]
}

@test "update-user writes a new password and alters the user on MySQL" {
  use_cluster
  stub_task_outcome "exited 0"

  run run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_success
  [ "$(put_secret_calls)" -eq 1 ]

  local value
  value="$(fake_password user)"
  run_task_script "$value" "app_user"
  grep -qxF -- "ccb69c87-example-rds.cluster-abcdefghijkl.eu-west-2.rds.amazonaws.com" "$SANDBOX/mysql.args"
  [ "$(cat "$SANDBOX/mysql.stdin")" == "ALTER USER 'app_user'@'%' IDENTIFIED BY '$value';" ]
}

@test "update-user's task fails with 4 when the user does not exist on Postgres" {
  stub_task_outcome "exited 0"
  run run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_success

  run --separate-stderr run_task_script "$(fake_password user)" ""
  assert_failure 4
  assert_stderr_contains "User app_user does not exist"
  [ ! -e "$SANDBOX/psql.stdin" ] || fail "ALTER USER was attempted"
}

@test "update-user's task fails with 4 when the user does not exist on MySQL" {
  use_cluster
  stub_task_outcome "exited 0"
  run run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_success

  run --separate-stderr run_task_script "$(fake_password user)" ""
  assert_failure 4
  assert_stderr_contains "User app_user does not exist"
  [ ! -e "$SANDBOX/mysql.stdin" ] || fail "ALTER USER was attempted"
}

@test "update-user restores the previous version when the SQL fails" {
  stub_task_outcome "exited 1"

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_failure 1
  assert_restored
  assert_stderr_contains "database was not changed"
  assert_stderr_contains "restored to the password app_user still has"
  assert_stderr_contains "terraform-dxw-dalmatian-infrastructure v0.51.0 or later"
}

@test "update-user restores when the task never ran" {
  stub_task_outcome "never-ran"
  stub_exit "$RUN_COMMAND" 1

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_failure
  assert_restored
  assert_stderr_contains "database was not changed"
}

@test "update-user restores and points to create-user when the user does not exist" {
  stub_task_outcome "exited 4"
  stub_exit "$RUN_COMMAND" 4

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_failure 4
  assert_restored
  assert_stderr_contains "User app_user does not exist"
  assert_stderr_contains "put back to its previous version"
  [[ "$stderr" != *"still has"* ]] || fail "said the user still has a password: $stderr"
  assert_stderr_contains "create-user"
  assert_stderr_contains "create-database"
}

@test "update-user deletes a takeover's parameter and says so when the user does not exist" {
  stub_no_stored_password
  stub_task_outcome "exited 4"

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_failure 4
  assert_call_args dalmatian aws run-command -p example-account ssm delete-parameter --name "$PARAMETER_NAME"
  assert_stderr_contains "User app_user does not exist"
  assert_stderr_contains "has been deleted"
  [[ "$stderr" != *"still has"* ]] || fail "said the user still has a password: $stderr"
  [[ "$stderr" != *"restored"* ]] || fail "said the parameter was restored: $stderr"
}

@test "update-user says the parameter could not be restored when the user does not exist" {
  stub_task_outcome "exited 4"
  unstub "$PREVIOUS_VALUE"
  stub_exit "$PREVIOUS_VALUE" 254

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_failure 4
  assert_stderr_contains "User app_user does not exist"
  assert_stderr_contains "could not be restored"
  [[ "$stderr" != *"does not have"* ]] || fail "spoke of the user's password: $stderr"
}

@test "update-user goes by the outcome, not run-command's exit status" {
  stub_task_outcome "exited 0"
  stub_exit "$RUN_COMMAND" 1

  run run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_success
  [ "$(put_secret_calls)" -eq 1 ]
}

@test "update-user keeps the new password when the outcome is unknown" {
  stub_task_outcome ""
  stub_exit "$RUN_COMMAND" 255

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_failure 255
  [ "$(put_secret_calls)" -eq 1 ]
  refute_stub_called_with "--with-decryption"
  refute_stub_called_with "delete-parameter"
  assert_stderr_contains "may still have the old password"
  assert_stderr_contains "update-user again"
}

@test "update-user treats an empty outcome as unknown even if run-command succeeded" {
  stub_task_outcome ""

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_failure 1
  [ "$(put_secret_calls)" -eq 1 ]
  assert_stderr_contains "may still have the old password"
}

@test "update-user removes its result file" {
  stub_task_outcome "exited 0"

  run run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_success
  local result_file
  result_file="$(sed -n 's/^dalmatian utilities run-command .* -R \([^ ]*\)$/\1/p' "$DALMATIAN_STUB_LOG")"
  [ -n "$result_file" ] || fail "run-command was not given -R"
  [ ! -e "$result_file" ] || fail "left behind $result_file"
}

@test "update-user says so when it cannot restore the previous version" {
  stub_task_outcome "exited 1"
  unstub "$PREVIOUS_VALUE"
  stub_exit "$PREVIOUS_VALUE" 254

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_failure
  [ "$(put_secret_calls)" -eq 1 ]
  assert_stderr_contains "could not restore"
  assert_stderr_contains "update-user again"
}

@test "update-user takes over a user with no stored password" {
  stub_no_stored_password
  stub_task_outcome "exited 0"

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" <<< "y"
  assert_success
  assert_stderr_contains "app_user has no stored password and will be taken over"
  [ "$(put_secret_calls)" -eq 1 ]
}

@test "update-user deletes the parameter it wrote for a takeover that fails" {
  stub_no_stored_password
  stub_task_outcome "exited 1"

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_failure 1
  assert_call_args dalmatian aws run-command -p example-account ssm delete-parameter --name "$PARAMETER_NAME"
  [ "$(put_secret_calls)" -eq 1 ]
  assert_stderr_contains "database was not changed"
  assert_stderr_contains "has been deleted"
  [[ "$stderr" != *"restored"* ]] || fail "said the parameter was restored: $stderr"
  assert_stderr_contains "terraform-dxw-dalmatian-infrastructure v0.51.0 or later"
}

@test "update-user stops when the stored version cannot be read" {
  unstub "$STORED_VERSION"
  stub_exit "$STORED_VERSION" 254
  stub_stderr "$STORED_VERSION" "An error occurred (AccessDeniedException) when calling the GetParameter operation: "

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_failure
  refute_stub_called_with "put-secret"
}

@test "update-user -p stores the password read from stdin" {
  local given
  given="$(fake_password given)"
  stub_task_outcome "exited 0"

  run run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y -p <<< "$given"
  assert_success
  [ "$(stub_stdin "$PUT_SECRET")" == "$given" ]
}

@test "update-user -p refuses an empty password" {
  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y -p <<< ""
  assert_failure 1
  assert_stderr_contains "Password cannot be empty"
  [[ "$stderr" != *"may already hold"* ]] || fail "reported a write that never happened: $stderr"
  refute_stub_called_with "put-secret"
  refute_stub_called_with "utilities run-command"
}

@test "update-user -p from a pipe needs -y, so the password is not read as the answer" {
  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -p <<< "$(fake_password given)"
  assert_failure 1
  assert_stderr_contains "-y"
  refute_stub_called_with "put-secret"
}

@test "update-user escapes a hostile password inside the MySQL container script" {
  use_cluster
  stub_task_outcome "exited 0"

  run run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_success

  run_task_script "a'b\\c\"\$(touch $SANDBOX/pwned)\`x\`" "app_user"
  [ ! -e "$SANDBOX/pwned" ] || fail "the password was executed"
  grep -qF "IDENTIFIED BY 'a''b\\\\c\"\$(touch $SANDBOX/pwned)\`x\`';" "$SANDBOX/mysql.stdin"
}

@test "update-user hands a hostile password to psql as a variable, unexpanded" {
  stub_task_outcome "exited 0"

  run run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_success

  local hostile
  hostile="a'b\"c\\d\`x\`\$(touch $SANDBOX/pwned)"
  run_task_script "$hostile" "1"
  [ ! -e "$SANDBOX/pwned" ] || fail "the password was executed"
  grep -qxF -- "password=$hostile" "$SANDBOX/psql.args"
  grep -qF "WITH PASSWORD :'password';" "$SANDBOX/psql.stdin"
}

@test "update-user sends the task the parameter name and never the password" {
  local given
  given="$(fake_password given)"
  stub_task_outcome "exited 0"

  run run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y -p <<< "$given"
  assert_success
  case "$(task_command)$(task_script)" in
    *"$given"*) fail "the password reached the task request" ;;
  esac
  task_script | grep -qF -- "aws ssm get-parameter --region eu-west-2 --name $PARAMETER_NAME --with-decryption"
}

@test "update-user refuses the RDS's root user" {
  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "root" -y
  assert_failure 1
  assert_stderr_contains "get-root-password"
  refute_stub_called_with "put-secret"
  refute_stub_called_with "utilities run-command"
}

@test "update-user refuses a user name that is not a plain identifier" {
  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app-user" -y
  assert_failure 1
  assert_stderr_contains "User name must be"
  refute_stub_called_with "describe-db"
}

@test "update-user refuses an unknown engine before writing anything" {
  stub_response "$INSTANCES" '{"DBInstances": [{"Engine": "oracle-ee", "MasterUsername": "root", "Endpoint": {"Address": "example.eu-west-2.rds.amazonaws.com"}}]}'

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_failure 1
  assert_stderr_contains "Unrecognised engine: oracle-ee"
  refute_stub_called_with "put-secret"
  refute_stub_called_with "utilities run-command"
}

@test "update-user treats a malformed outcome as unknown" {
  stub_task_outcome "exited x"

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_failure 1
  assert_unknown_outcome
}

@test "update-user treats a killed container as an unknown outcome" {
  stub_task_outcome "exited 137"
  stub_exit "$RUN_COMMAND" 137

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_failure 137
  assert_unknown_outcome
}

@test "update-user treats a terminated container as an unknown outcome" {
  stub_task_outcome "exited 143"

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_failure
  assert_unknown_outcome
}

@test "update-user says so when storing the new password fails" {
  stub_task_outcome "exited 0"
  stub_exit "$PUT_SECRET" 1

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_failure 1
  assert_stderr_contains "may already hold a new password"
  assert_stderr_contains "update-user again"
  [ "$(put_secret_calls)" -eq 1 ]
  refute_stub_called_with "utilities run-command"
  refute_stub_called_with "--with-decryption"
}

@test "update-user says so when writing back the previous version fails" {
  stub_task_outcome "exited 1"
  fail_put_secret_after_task

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_failure 1
  assert_call_args dalmatian aws run-command -p example-account ssm get-parameter --name "$PARAMETER_NAME:5" --with-decryption --query Parameter.Value --output text
  [ "$(put_secret_calls)" -eq 2 ]
  assert_stderr_contains "could not restore"
  assert_stderr_contains "update-user again"
}

@test "update-user says so when deleting a failed takeover's parameter fails" {
  stub_no_stored_password
  stub_task_outcome "exited 1"
  stub_exit dalmatian-aws-run_command-p-example_account-ssm-delete_parameter 254

  run --separate-stderr run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_failure 1
  assert_call_args dalmatian aws run-command -p example-account ssm delete-parameter --name "$PARAMETER_NAME"
  assert_stderr_contains "could not restore"
  assert_stderr_contains "update-user again"
}

@test "update-user -y still says it is taking a user over" {
  unset QUIET_MODE
  stub_no_stored_password
  stub_task_outcome "exited 0"

  run run_command bin/rds/v2/update-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" -y
  assert_success
  assert_output_contains "app_user has no stored password and is being taken over"
}
