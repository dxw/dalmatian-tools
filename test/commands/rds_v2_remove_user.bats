#!/usr/bin/env bats
# The task scripts are matched literally, $DB_PASSWORD and all, because the
# container expands them, not this shell
# shellcheck disable=SC2016,SC2030,SC2031

load ../test_helper
load ../rds_v2_task_helper

CLUSTERS=dalmatian-aws-run_command-p-example_account-rds-describe_db_clusters
INSTANCES=dalmatian-aws-run_command-p-example_account-rds-describe_db_instances
DELETE_PARAMETER=dalmatian-aws-run_command-p-example_account-ssm-delete_parameter-name-_example_infra_staging_rds_example_rds_app_user_password
RUN_COMMAND=dalmatian-utilities-run_command

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
  stub_response "$DELETE_PARAMETER" ""
}

use_cluster() {
  unstub "$CLUSTERS"
  stub_response_file "$CLUSTERS" v2-rds-describe-db-clusters-aurora-mysql-full.json
}

remove_user() {
  run_command bin/rds/v2/remove-user -i "example-infra" -e "staging" -r "example-rds" -u "app_user" "$@"
}

@test "remove-user prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v2/remove-user
  assert_failure 1
  assert_stderr_contains "Usage: remove-user"
}

@test "remove-user requires a user name" {
  run --separate-stderr run_command bin/rds/v2/remove-user -i "example-infra" -e "staging" -r "example-rds"
  assert_failure 1
  assert_stderr_contains "Usage: remove-user"
  refute_stub_called_with "utilities run-command"
}

@test "remove-user refuses a user name that is not a plain identifier" {
  run --separate-stderr remove_user -u "app-user" -y
  assert_failure 1
  assert_stderr_contains "User name must be"
  refute_stub_called_with "describe-db"
}

@test "remove-user refuses the root user" {
  run --separate-stderr run_command bin/rds/v2/remove-user -i "example-infra" -e "staging" -r "example-rds" -u "root" -y
  assert_failure 1
  assert_stderr_contains "root user"
  refute_stub_called_with "utilities run-command"
  refute_stub_called_with "delete-parameter"
}

@test "remove-user refuses an unknown engine before doing anything" {
  stub_response "$INSTANCES" '{"DBInstances": [{"Engine": "oracle-ee", "MasterUsername": "root", "Endpoint": {"Address": "example.eu-west-2.rds.amazonaws.com"}}]}'

  run --separate-stderr remove_user -y
  assert_failure 1
  assert_stderr_contains "Unrecognised engine: oracle-ee"
  refute_stub_called_with "utilities run-command"
  refute_stub_called_with "delete-parameter"
}

@test "remove-user asks for confirmation naming what goes, and does nothing on no" {
  run --separate-stderr remove_user <<< "n"
  assert_success
  assert_stderr_contains "app_user will be dropped from ccb69c87-example-rds (example-infra staging)"
  refute_stub_called_with "utilities run-command"
  refute_stub_called_with "delete-parameter"
}

@test "remove-user defaults to no on an empty answer" {
  run --separate-stderr remove_user <<< ""
  assert_success
  refute_stub_called_with "utilities run-command"
}

@test "remove-user goes ahead on yes" {
  stub_task_outcome "exited 0"

  run remove_user <<< "y"
  assert_success
  assert_stub_called_with "utilities run-command"
  assert_call_args dalmatian aws run-command -p example-account ssm delete-parameter --name /example-infra/staging/rds/example-rds/app_user/password
}

@test "remove-user drops the user on Postgres, then deletes the parameter" {
  unset QUIET_MODE
  stub_task_outcome "exited 0"

  run remove_user -y
  assert_success
  assert_output_contains "Dropped app_user"
  assert_output_contains "Deleted /example-infra/staging/rds/example-rds/app_user/password"

  run_task_script "$(fake_password user)" "1"
  grep -qxF -- "ccb69c87-example-rds.abcdefghijkl.eu-west-2.rds.amazonaws.com" "$SANDBOX/psql.args"
  [ "$(cat "$SANDBOX/psql.stdin")" == 'DROP USER IF EXISTS "app_user";' ]
}

@test "remove-user drops the user on MySQL, then deletes the parameter" {
  use_cluster
  stub_task_outcome "exited 0"

  run remove_user -y
  assert_success
  assert_stub_called_with "delete-parameter"

  run_task_script "$(fake_password user)" "app_user"
  grep -qxF -- "ccb69c87-example-rds.cluster-abcdefghijkl.eu-west-2.rds.amazonaws.com" "$SANDBOX/mysql.args"
  [ "$(cat "$SANDBOX/mysql.stdin")" == "DROP USER IF EXISTS 'app_user'@'%';" ]
}

@test "remove-user's task script still drops, and exits 10, when the user is not found" {
  stub_task_outcome "exited 0"
  remove_user -y
  run --separate-stderr run_task_script "$(fake_password user)" ""
  assert_failure 10
  assert_stderr_contains "User app_user did not exist"
  [ "$(cat "$SANDBOX/psql.stdin")" == 'DROP USER IF EXISTS "app_user";' ]
}

@test "remove-user's task script exits 1, not psql's 3, when the DROP fails on Postgres" {
  stub_task_outcome "exited 0"
  remove_user -y
  export TASK_CLIENT_EXIT=3
  run --separate-stderr run_task_script "$(fake_password user)" "1"
  assert_failure 1
  export TASK_CLIENT_EXIT=1
  run --separate-stderr run_task_script "$(fake_password user)" "1"
  assert_failure 1
}

@test "remove-user's task script exits 1 when the DROP fails on a user that was not found" {
  stub_task_outcome "exited 0"
  remove_user -y
  export TASK_CLIENT_EXIT=3
  run --separate-stderr run_task_script "$(fake_password user)" ""
  assert_failure 1
}

@test "remove-user's task script exits 1 when the existence lookup fails" {
  stub_task_outcome "exited 0"
  remove_user -y
  export TASK_LOOKUP_EXIT=3
  run --separate-stderr run_task_script "$(fake_password user)" "1"
  assert_failure 1
  [ ! -e "$SANDBOX/psql.stdin" ] || fail "DROP was attempted"
}

@test "remove-user's task script exits 1 when the DROP fails on MySQL" {
  use_cluster
  stub_task_outcome "exited 0"
  remove_user -y
  export TASK_CLIENT_EXIT=1
  run --separate-stderr run_task_script "$(fake_password user)" "app_user"
  assert_failure 1
}

@test "remove-user's task script exits 0 when the user is found" {
  stub_task_outcome "exited 0"
  remove_user -y
  run run_task_script "$(fake_password user)" "1"
  assert_success
}

@test "remove-user reports a user that did not exist and still deletes the parameter" {
  unset QUIET_MODE
  stub_task_outcome "exited 10"

  run remove_user -y
  assert_success
  assert_output_contains "app_user did not exist"
  assert_stub_called_with "delete-parameter"
}

@test "remove-user reports a parameter that was already absent" {
  unset QUIET_MODE
  stub_task_outcome "exited 0"
  unstub "$DELETE_PARAMETER"
  stub_exit "$DELETE_PARAMETER" 254
  stub_stderr "$DELETE_PARAMETER" "An error occurred (ParameterNotFound) when calling the DeleteParameter operation: "

  run remove_user -y
  assert_success
  assert_output_contains "already absent"
}

@test "remove-user fails saying the parameter remains when its deletion fails" {
  stub_task_outcome "exited 0"
  unstub "$DELETE_PARAMETER"
  stub_exit "$DELETE_PARAMETER" 254
  stub_stderr "$DELETE_PARAMETER" "An error occurred (AccessDeniedException) when calling the DeleteParameter operation: denied"

  run --separate-stderr remove_user -y
  assert_failure 1
  assert_stderr_contains "app_user was dropped"
  assert_stderr_contains "remains"
  assert_stderr_contains "AccessDeniedException"
}

@test "remove-user keeps the parameter and points at remove-database when Postgres cannot drop the user" {
  stub_task_outcome "exited 1"

  run --separate-stderr remove_user -y
  assert_failure 1
  refute_stub_called_with "delete-parameter"
  assert_stderr_contains "remove-database first"
  assert_stderr_contains "has been kept"
  assert_stderr_contains "terraform-dxw-dalmatian-infrastructure v0.51.0 or later"
}

@test "remove-user treats exited 3 as a failure, not as a missing user" {
  unset QUIET_MODE
  stub_task_outcome "exited 3"

  run --separate-stderr remove_user -y
  assert_failure 3
  refute_stub_called_with "delete-parameter"
  assert_stderr_contains "was not dropped"
  assert_stderr_contains "remove-database first"
  [[ "$output" != *"did not exist"* ]] || fail "said the user did not exist: $output"
}

@test "remove-user does not mention remove-database on MySQL" {
  use_cluster
  stub_task_outcome "exited 1"

  run --separate-stderr remove_user -y
  assert_failure 1
  refute_stub_called_with "delete-parameter"
  [[ "$stderr" != *remove-database* ]] || fail "mentioned remove-database: $stderr"
}

@test "remove-user keeps the parameter when the task never ran" {
  stub_task_outcome "never-ran"
  stub_exit "$RUN_COMMAND" 1

  run --separate-stderr remove_user -y
  assert_failure 1
  refute_stub_called_with "delete-parameter"
  assert_stderr_contains "has been kept"
}

@test "remove-user keeps the parameter and says to rerun when the outcome is unknown" {
  stub_task_outcome ""
  stub_exit "$RUN_COMMAND" 255

  run --separate-stderr remove_user -y
  assert_failure 255
  refute_stub_called_with "delete-parameter"
  assert_stderr_contains "may or may not have been"
  assert_stderr_contains "remove-user again is safe"
}

@test "remove-user treats an empty outcome as unknown even if run-command succeeded" {
  stub_task_outcome ""

  run --separate-stderr remove_user -y
  assert_failure 1
  refute_stub_called_with "delete-parameter"
}

@test "remove-user treats a malformed outcome as unknown" {
  stub_task_outcome "exited x"

  run --separate-stderr remove_user -y
  assert_failure 1
  refute_stub_called_with "delete-parameter"
  assert_stderr_contains "remove-user again is safe"
}

@test "remove-user treats a killed container as an unknown outcome" {
  stub_task_outcome "exited 137"

  run --separate-stderr remove_user -y
  assert_failure 1
  refute_stub_called_with "delete-parameter"
  assert_stderr_contains "remove-user again is safe"
}

@test "remove-user treats a terminated container as an unknown outcome" {
  stub_task_outcome "exited 143"

  run --separate-stderr remove_user -y
  assert_failure 1
  refute_stub_called_with "delete-parameter"
}
