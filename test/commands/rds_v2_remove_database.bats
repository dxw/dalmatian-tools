#!/usr/bin/env bats
# The task scripts are matched literally, $DB_PASSWORD and all, because the
# container expands them, not this shell
# shellcheck disable=SC2016

load ../test_helper
load ../rds_v2_task_helper

CLUSTERS=dalmatian-aws-run_command-p-example_account-rds-describe_db_clusters
INSTANCES=dalmatian-aws-run_command-p-example_account-rds-describe_db_instances
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
}

use_cluster() {
  unstub "$CLUSTERS"
  stub_response_file "$CLUSTERS" v2-rds-describe-db-clusters-aurora-mysql-full.json
}

remove_database() {
  run_command bin/rds/v2/remove-database -i "example-infra" -e "staging" -r "example-rds" -d "app_db" "$@"
}

# Runs the decoded task script with mysql recording its calls. The revoke
# generator (-N) and the other calls are recorded apart, as they run
# concurrently in a pipeline: mysql.gen holds the generator's arguments and
# stdin, mysql.calls those of the other calls in order. A call whose
# arguments mention information_schema is the existence lookup, answered
# with $1
run_mysql_task_script() {
  mkdir -p "$SANDBOX/container"
  rm -f "$SANDBOX/mysql.calls" "$SANDBOX/mysql.gen"
  cat > "$SANDBOX/container/mysql" <<FAKE
#!/usr/bin/env bash
case "\$*" in
  *information_schema*)
    printf '%s' "$1"
    exit "\${TASK_LOOKUP_EXIT:-0}"
    ;;
  -N*)
    { printf 'args: %s\n' "\$*"; cat; } > "$SANDBOX/mysql.gen"
    ;;
  *)
    { printf 'args: %s\n' "\$*"; cat; } >> "$SANDBOX/mysql.calls"
    ;;
esac
exit "\${TASK_CLIENT_EXIT:-0}"
FAKE
  chmod +x "$SANDBOX/container/mysql"
  task_script > "$SANDBOX/task-script"
  DB_USER=root DB_PASSWORD="$(fake_password root)" PATH="$SANDBOX/container:$PATH" bash "$SANDBOX/task-script" < /dev/null
}

@test "remove-database prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v2/remove-database
  assert_failure 1
  assert_stderr_contains "Usage: remove-database"
}

@test "remove-database requires a database name" {
  run --separate-stderr run_command bin/rds/v2/remove-database -i "example-infra" -e "staging" -r "example-rds"
  assert_failure 1
  assert_stderr_contains "Usage: remove-database"
  refute_stub_called_with "utilities run-command"
}

@test "remove-database refuses a database name that is not a plain identifier" {
  run --separate-stderr remove_database -d 'app"db' -y
  assert_failure 1
  assert_stderr_contains "Database name must"
  refute_stub_called_with "describe-db"
}

@test "remove-database refuses the Postgres maintenance databases before running anything" {
  for name in postgres template0 template1 rdsadmin Postgres; do
    run --separate-stderr remove_database -d "$name" -y
    assert_failure 1
    assert_stderr_contains "cannot be removed"
  done
  refute_stub_called_with "utilities run-command"
}

@test "remove-database refuses the MySQL system databases before running anything" {
  use_cluster
  for name in mysql sys information_schema performance_schema; do
    run --separate-stderr remove_database -d "$name" -y
    assert_failure 1
    assert_stderr_contains "cannot be removed"
  done
  refute_stub_called_with "utilities run-command"
}

@test "remove-database allows a Postgres system name on MySQL" {
  use_cluster
  stub_task_outcome "exited 0"
  run remove_database -d postgres -y
  assert_success
}

@test "remove-database refuses an unknown engine before doing anything" {
  stub_response "$INSTANCES" '{"DBInstances": [{"Engine": "oracle-ee", "MasterUsername": "root", "Endpoint": {"Address": "example.eu-west-2.rds.amazonaws.com"}}]}'

  run --separate-stderr remove_database -y
  assert_failure 1
  assert_stderr_contains "Unrecognised engine: oracle-ee"
  refute_stub_called_with "utilities run-command"
}

@test "remove-database asks for confirmation naming what goes, and does nothing on no" {
  run --separate-stderr remove_database <<< "n"
  assert_success
  assert_stderr_contains "Database app_db will be dropped from ccb69c87-example-rds (example-infra staging)"
  refute_stub_called_with "utilities run-command"
}

@test "remove-database defaults to no on an empty answer" {
  run --separate-stderr remove_database <<< ""
  assert_success
  refute_stub_called_with "utilities run-command"
}

@test "remove-database goes ahead on yes" {
  stub_task_outcome "exited 0"
  run remove_database <<< "y"
  assert_success
  assert_stub_called_with "utilities run-command"
}

@test "remove-database drops the database on Postgres from the postgres database" {
  unset QUIET_MODE
  stub_task_outcome "exited 0"

  run remove_database -y
  assert_success
  assert_output_contains "Dropped app_db"
  assert_output_contains "remove-user"

  run_task_script "$(fake_password user)" "1"
  grep -qxF -- "postgres" "$SANDBOX/psql.args"
  grep -qxF -- "ccb69c87-example-rds.abcdefghijkl.eu-west-2.rds.amazonaws.com" "$SANDBOX/psql.args"
  [ "$(cat "$SANDBOX/psql.stdin")" == 'DROP DATABASE IF EXISTS "app_db";' ]
}

@test "remove-database drops the database on MySQL, then revokes its grants, matching the escaped and unescaped name and revoking grant option" {
  use_cluster
  stub_task_outcome "exited 0"

  run remove_database -y
  assert_success

  run run_mysql_task_script "app_db"
  assert_success
  endpoint=ccb69c87-example-rds.cluster-abcdefghijkl.eu-west-2.rds.amazonaws.com
  [ "$(cat "$SANDBOX/mysql.gen")" == "args: -N -r -u root -h $endpoint
SELECT CONCAT('REVOKE ALL ON ', sys.quote_identifier(Db), '.* FROM ', QUOTE(User), '@', QUOTE(Host), ';') FROM mysql.db WHERE Db IN ('app_db', REPLACE('app_db', '_', '\\\\_'))
UNION ALL
SELECT CONCAT('REVOKE GRANT OPTION ON ', sys.quote_identifier(Db), '.* FROM ', QUOTE(User), '@', QUOTE(Host), ';') FROM mysql.db WHERE Db IN ('app_db', REPLACE('app_db', '_', '\\\\_')) AND Grant_priv = 'Y';" ]
  [ "$(cat "$SANDBOX/mysql.calls")" == "args: -u root -h $endpoint
DROP DATABASE IF EXISTS \`app_db\`;
args: -u root -h $endpoint" ]
}

# Grants outlive a DROP DATABASE, so revoking can wait for the drop; revoking
# first would leave users locked out of a database that a failed drop kept
@test "remove-database's MySQL task script revokes nothing when the DROP fails" {
  use_cluster
  stub_task_outcome "exited 0"
  remove_database -y
  TASK_CLIENT_EXIT=1 run --separate-stderr run_mysql_task_script "app_db"
  assert_failure 1
  grep -qF 'DROP DATABASE IF EXISTS `app_db`;' "$SANDBOX/mysql.calls"
  [ ! -e "$SANDBOX/mysql.gen" ] || fail "revoked after a failed DROP"
}

@test "remove-database's MySQL task script still revokes grants when the database is not found" {
  use_cluster
  stub_task_outcome "exited 0"
  remove_database -y
  run --separate-stderr run_mysql_task_script ""
  assert_failure 10
  grep -qF "REVOKE ALL ON" "$SANDBOX/mysql.gen"
}

@test "remove-database's MySQL revoke SQL, as MySQL reads the literal, names only the one database" {
  use_cluster
  stub_task_outcome "exited 0"
  remove_database -y
  run run_mysql_task_script "app_db"
  grep -qF "REPLACE('app_db', '_', '\\\\_')" "$SANDBOX/mysql.gen"
  [[ "$(cat "$SANDBOX/mysql.gen")" != *"'\\_'"* ]] || fail "single backslash in the string literal"
}

@test "remove-database's MySQL task script pipes the revoke statements into a second mysql" {
  use_cluster
  stub_task_outcome "exited 0"
  remove_database -y
  # The generator prints a REVOKE statement; the consumer must receive it
  mkdir -p "$SANDBOX/container"
  cat > "$SANDBOX/container/mysql" <<FAKE
#!/usr/bin/env bash
case "\$*" in
  *information_schema*) printf 'app_db'; exit 0 ;;
  -N*) cat > /dev/null; printf 'REVOKE-MARKER\\n'; exit 0 ;;
esac
cat >> "$SANDBOX/consumed"
FAKE
  chmod +x "$SANDBOX/container/mysql"
  rm -f "$SANDBOX/consumed"
  task_script > "$SANDBOX/task-script"
  DB_USER=root DB_PASSWORD="$(fake_password root)" PATH="$SANDBOX/container:$PATH" run bash "$SANDBOX/task-script"
  assert_success
  grep -qxF "REVOKE-MARKER" "$SANDBOX/consumed"
}

@test "remove-database's task script still drops, and exits 10, when the database is not found" {
  stub_task_outcome "exited 0"
  remove_database -y
  run --separate-stderr run_task_script "$(fake_password user)" ""
  assert_failure 10
  assert_stderr_contains "Database app_db did not exist"
  [ "$(cat "$SANDBOX/psql.stdin")" == 'DROP DATABASE IF EXISTS "app_db";' ]
}

@test "remove-database's MySQL task script exits 10 when the database is not found" {
  use_cluster
  stub_task_outcome "exited 0"
  remove_database -y
  run --separate-stderr run_mysql_task_script ""
  assert_failure 10
  grep -qF 'DROP DATABASE IF EXISTS `app_db`;' "$SANDBOX/mysql.calls"
}

@test "remove-database's Postgres task script exits 1, not psql's 3, when the DROP fails" {
  stub_task_outcome "exited 0"
  remove_database -y
  TASK_CLIENT_EXIT=3 run --separate-stderr run_task_script "$(fake_password user)" "1"
  assert_failure 1
  TASK_CLIENT_EXIT=3 run --separate-stderr run_task_script "$(fake_password user)" ""
  assert_failure 1
}

@test "remove-database's Postgres task script exits 1 when the existence lookup fails" {
  stub_task_outcome "exited 0"
  remove_database -y
  TASK_LOOKUP_EXIT=3 run --separate-stderr run_task_script "$(fake_password user)" "1"
  assert_failure 1
  [ ! -e "$SANDBOX/psql.stdin" ] || fail "DROP was attempted"
}

@test "remove-database's MySQL task script exits 1 when any mysql call fails" {
  use_cluster
  stub_task_outcome "exited 0"
  remove_database -y
  TASK_CLIENT_EXIT=1 run --separate-stderr run_mysql_task_script "app_db"
  assert_failure 1
  TASK_LOOKUP_EXIT=1 run --separate-stderr run_mysql_task_script "app_db"
  assert_failure 1
}

@test "remove-database's task script exits 0 when the database is found" {
  stub_task_outcome "exited 0"
  remove_database -y
  run run_task_script "$(fake_password user)" "1"
  assert_success
}

@test "remove-database reports a database that did not exist as success" {
  unset QUIET_MODE
  stub_task_outcome "exited 10"
  run remove_database -y
  assert_success
  assert_output_contains "app_db did not exist"
}

@test "remove-database says Postgres refuses while connections to it are open when the drop fails" {
  stub_task_outcome "exited 1"
  run --separate-stderr remove_database -y
  assert_failure 1
  assert_stderr_contains "was not dropped"
  assert_stderr_contains "connections to it are open"
  assert_stderr_contains "stop the services"
  assert_stderr_contains "terraform-dxw-dalmatian-infrastructure v0.51.0 or later"
}

@test "remove-database does not mention open connections on MySQL" {
  use_cluster
  stub_task_outcome "exited 1"
  run --separate-stderr remove_database -y
  assert_failure 1
  [[ "$stderr" != *connections* ]] || fail "mentioned connections: $stderr"
  assert_stderr_contains "grants may not all have been revoked"
  assert_stderr_contains "remove-database again is safe"
  assert_stderr_contains "terraform-dxw-dalmatian-infrastructure v0.51.0 or later"
}

@test "remove-database treats exited 3 as a failure, not as a missing database" {
  unset QUIET_MODE
  stub_task_outcome "exited 3"
  run --separate-stderr remove_database -y
  assert_failure 3
  [[ "$output" != *"did not exist"* ]] || fail "said the database did not exist: $output"
}

@test "remove-database fails when the task never ran" {
  stub_task_outcome "never-ran"
  stub_exit "$RUN_COMMAND" 1
  run --separate-stderr remove_database -y
  assert_failure 1
  assert_stderr_contains "was not dropped"
}

@test "remove-database says the outcome is uncertain and rerunning is safe when it is unknown" {
  stub_task_outcome "exited 137"
  run --separate-stderr remove_database -y
  assert_failure 1
  assert_stderr_contains "may or may not have been"
  assert_stderr_contains "remove-database again is safe"
}

@test "remove-database treats an empty outcome as unknown even if run-command succeeded" {
  stub_task_outcome ""
  run --separate-stderr remove_database -y
  assert_failure 1
  assert_stderr_contains "remove-database again is safe"
}

@test "remove-database never calls SSM" {
  stub_task_outcome "exited 0"
  run remove_database -y
  assert_success
  refute_stub_called_with "ssm"
  refute_stub_called_with "parameter"
}

@test "remove-database reminds that users are removed with remove-user" {
  unset QUIET_MODE
  stub_task_outcome "exited 10"
  run remove_database -y
  assert_success
  assert_output_contains "remove-user"
}
