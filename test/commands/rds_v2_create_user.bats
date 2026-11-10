#!/usr/bin/env bats
# The task scripts are matched literally, $DB_PASSWORD and all, because the
# container expands them, not this shell
# shellcheck disable=SC2016

load ../test_helper
load ../rds_v2_task_helper

CLUSTERS=dalmatian-aws-run_command-p-example_account-rds-describe_db_clusters
INSTANCES=dalmatian-aws-run_command-p-example_account-rds-describe_db_instances
GET_PARAMETER=dalmatian-aws-run_command-p-example_account-ssm-get_parameter
PUT_SECRET=dalmatian-aws-put_secret
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
  stub_exit "$GET_PARAMETER" 254
  stub_stderr "$GET_PARAMETER" "An error occurred (ParameterNotFound) when calling the GetParameter operation: "
  stub_capture_stdin "$PUT_SECRET"
}

use_cluster() {
  unstub "$CLUSTERS"
  stub_response_file "$CLUSTERS" v2-rds-describe-db-clusters-aurora-mysql-full.json
}

@test "create-user prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v2/create-user
  assert_failure 1
  assert_stderr_contains "Usage: create-user"
}

@test "create-user requires a database and a user name" {
  run --separate-stderr run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app"
  assert_failure 1
  assert_stderr_contains "Usage: create-user"
  refute_stub_called_with "utilities run-command"
}

stub_stored_password() {
  unstub "$GET_PARAMETER"
  stub_response "$GET_PARAMETER" "3"
}

@test "create-user generates a password and stores it with put-secret when none is stored" {
  run run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user"
  assert_success
  assert_call_args dalmatian aws put-secret -i example-infra -e staging -n rds/example-rds/app_user/password
  [[ "$(stub_stdin "$PUT_SECRET")" =~ ^[A-Za-z0-9]{32}$ ]] || fail "unexpected generated password: $(stub_stdin "$PUT_SECRET")"
}

@test "create-user changes nothing when a password is already stored" {
  stub_stored_password

  run --separate-stderr run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user"
  assert_failure 1
  assert_stderr_contains "$PARAMETER_NAME"
  assert_stderr_contains "update-user"
  assert_stderr_contains "-f"
  refute_stub_called_with "put-secret"
  refute_stub_called_with "utilities run-command"
}

@test "create-user -p stores the password read from stdin" {
  local given
  given="$(fake_password given)"

  run run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user" -p <<< "$given"
  assert_success
  [ "$(stub_stdin "$PUT_SECRET")" == "$given" ]
}

@test "create-user -p refuses an empty password" {
  run --separate-stderr run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user" -p <<< ""
  assert_failure 1
  assert_stderr_contains "Password cannot be empty"
  refute_stub_called_with "put-secret"
  refute_stub_called_with "utilities run-command"
}

@test "create-user -f with -p is refused" {
  run --separate-stderr run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user" -f -p <<< "$(fake_password given)"
  assert_failure 1
  assert_stderr_contains "Usage: create-user"
  refute_stub_called_with "put-secret"
  refute_stub_called_with "utilities run-command"
}

@test "create-user -f reuses the stored password" {
  stub_stored_password

  run run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user" -f
  assert_success
  refute_stub_called_with "put-secret"
  assert_stub_called_with "utilities run-command"
}

@test "create-user on MySQL creates the user and grants the database" {
  use_cluster

  run run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app_db" -u "app_user"
  assert_success

  local value
  value="$(fake_password user)"
  run_task_script "$value" "app_db"
  grep -qxF -- "ccb69c87-example-rds.cluster-abcdefghijkl.eu-west-2.rds.amazonaws.com" "$SANDBOX/mysql.args"
  [ "$(cat "$SANDBOX/mysql.stdin")" == "$(printf '%s\n' \
    "CREATE USER 'app_user'@'%' IDENTIFIED BY '$value';" \
    "GRANT ALL ON \`app\\_db\`.* TO 'app_user'@'%';")" ]
}

@test "create-user on MySQL fails when the database does not exist" {
  use_cluster

  run run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app_db" -u "app_user"
  assert_success

  run --separate-stderr run_task_script "$(fake_password user)" ""
  assert_failure 4
  assert_stderr_contains "Database app_db does not exist"
  [ ! -e "$SANDBOX/mysql.stdin" ] || fail "CREATE USER was attempted"
}

@test "create-user -f makes the MySQL SQL idempotent" {
  use_cluster

  run run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user" -f
  assert_success

  run_task_script "$(fake_password user)" "app"
  [ "$(cat "$SANDBOX/mysql.stdin")" == "$(printf '%s\n' \
    "CREATE USER IF NOT EXISTS 'app_user'@'%' IDENTIFIED BY '$(fake_password user)';" \
    "GRANT ALL ON \`app\`.* TO 'app_user'@'%';")" ]
}

@test "create-user on Postgres takes the owner's role" {
  run run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app_db" -u "app_user"
  assert_success

  local value
  value="$(fake_password user)"
  run_task_script "$value" "app_owner|f"
  grep -qxF -- "ccb69c87-example-rds.abcdefghijkl.eu-west-2.rds.amazonaws.com" "$SANDBOX/psql.args"
  grep -qxF -- "password=$value" "$SANDBOX/psql.args"
  grep -qxF -- "owner=app_owner" "$SANDBOX/psql.args"
  [ "$(cat "$SANDBOX/psql.stdin")" == "$(printf '%s\n' \
    "CREATE USER \"app_user\" WITH PASSWORD :'password';" \
    "GRANT :\"owner\" TO \"app_user\";" \
    "GRANT \"app_user\" TO \"root\";" \
    "ALTER ROLE \"app_user\" IN DATABASE \"app_db\" SET role = :'owner';")" ]
}

@test "create-user on Postgres fails when the database does not exist" {
  run run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app_db" -u "app_user"
  assert_success

  run --separate-stderr run_task_script "$(fake_password user)" ""
  assert_failure 4
  assert_stderr_contains "Database app_db does not exist"
  [ ! -e "$SANDBOX/psql.stdin" ] || fail "CREATE USER was attempted"
}

@test "create-user on Postgres refuses a database owned by a privileged role" {
  run run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app_db" -u "app_user"
  assert_success

  run --separate-stderr run_task_script "$(fake_password user)" "root|t"
  assert_failure 5
  assert_stderr_contains "Database app_db is owned by root, a privileged role"
  [ ! -e "$SANDBOX/psql.stdin" ] || fail "CREATE USER was attempted"
}

@test "create-user's Postgres owner lookup flags any owner that is not a plain role" {
  run run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app_db" -u "app_user"
  assert_success

  task_script | grep -qF "SELECT r.rolname, (r.rolname = :'root' OR r.rolsuper OR r.rolcreaterole OR r.rolreplication OR r.rolbypassrls OR EXISTS (SELECT 1 FROM pg_auth_members m WHERE m.member = r.oid)) FROM pg_database d JOIN pg_roles r ON r.oid = d.datdba WHERE d.datname = :'db';"
}

@test "create-user deletes the password it stored when the database does not exist" {
  stub_exit dalmatian-utilities-run_command 4

  run --separate-stderr run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user"
  assert_failure 4
  assert_call_args dalmatian aws run-command -p example-account ssm delete-parameter --name "$PARAMETER_NAME"
  assert_stderr_contains "create-database"
  [[ "$stderr" != *"-f"* ]] || fail "advised -f: $stderr"
}

@test "create-user deletes the password it stored when the owner is privileged" {
  stub_exit dalmatian-utilities-run_command 5

  run --separate-stderr run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user"
  assert_failure 5
  assert_call_args dalmatian aws run-command -p example-account ssm delete-parameter --name "$PARAMETER_NAME"
  assert_stderr_contains "privileged role"
  [[ "$stderr" != *"-f"* ]] || fail "advised -f: $stderr"
}

@test "create-user -f keeps the stored password when the database does not exist" {
  stub_stored_password
  stub_exit dalmatian-utilities-run_command 4

  run --separate-stderr run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user" -f
  assert_failure 4
  refute_stub_called_with "ssm delete-parameter"
  assert_stderr_contains "create-database"
}

@test "create-user still exits with the task's status when the cleanup delete fails" {
  stub_exit dalmatian-utilities-run_command 4
  stub_exit dalmatian-aws-run_command-p-example_account-ssm-delete_parameter 1

  run --separate-stderr run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user"
  assert_failure 4
  assert_stderr_contains "Could not delete"
}

@test "create-user -f guards the Postgres CREATE USER" {
  run run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user" -f
  assert_success

  run_task_script "$(fake_password user)" "app_owner|f"
  [ "$(cat "$SANDBOX/psql.stdin")" == "$(printf '%s\n' \
    "SELECT 'CREATE USER \"app_user\" WITH PASSWORD ' || quote_literal(:'password') WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_user')\\gexec" \
    "GRANT :\"owner\" TO \"app_user\";" \
    "GRANT \"app_user\" TO \"root\";" \
    "ALTER ROLE \"app_user\" IN DATABASE \"app\" SET role = :'owner';")" ]
}

@test "create-user escapes a hostile password inside the MySQL container script" {
  use_cluster

  run run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user"
  assert_success

  run_task_script "a'b\\c\"\$(touch $SANDBOX/pwned)\`x\`" "app"
  [ ! -e "$SANDBOX/pwned" ] || fail "the password was executed"
  grep -qF "IDENTIFIED BY 'a''b\\\\c\"\$(touch $SANDBOX/pwned)\`x\`';" "$SANDBOX/mysql.stdin"
}

@test "create-user hands a hostile password to psql as a variable, unexpanded" {
  run run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user"
  assert_success

  local hostile
  hostile="a'b\"c\\d\`x\`\$(touch $SANDBOX/pwned)"
  run_task_script "$hostile" "app_owner|f"
  [ ! -e "$SANDBOX/pwned" ] || fail "the password was executed"
  grep -qxF -- "password=$hostile" "$SANDBOX/psql.args"
  grep -qF "WITH PASSWORD :'password';" "$SANDBOX/psql.stdin"
}

@test "create-user sends the task the parameter name and never the password" {
  local given
  given="$(fake_password given)"

  run run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user" -p <<< "$given"
  assert_success
  case "$(task_command)$(task_script)" in
    *"$given"*) fail "the password reached the task request" ;;
  esac
  task_script | grep -qF -- "aws ssm get-parameter --region eu-west-2 --name $PARAMETER_NAME --with-decryption"
}

@test "create-user says to rerun with -f when the task fails" {
  stub_exit dalmatian-utilities-run_command 1

  run --separate-stderr run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user"
  assert_failure 1
  assert_stderr_contains "-f"
  assert_stderr_contains "terraform-dxw-dalmatian-infrastructure v0.51.0 or later"
  refute_stub_called_with "ssm delete-parameter"
}

@test "create-user -f notes update-user on success" {
  unset QUIET_MODE
  stub_stored_password

  run run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user" -f
  assert_success
  assert_output_contains "update-user"
}

@test "create-user refuses a database name that is not a plain identifier" {
  run --separate-stderr run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d 'app"; DROP' -u "app_user"
  assert_failure 1
  assert_stderr_contains "Database name must be"
  refute_stub_called_with "describe-db"
}

@test "create-user refuses a user name that is not a plain identifier" {
  run --separate-stderr run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app-user"
  assert_failure 1
  assert_stderr_contains "User name must be"
  refute_stub_called_with "describe-db"
}

@test "create-user refuses an unknown engine" {
  stub_response "$INSTANCES" '{"DBInstances": [{"Engine": "oracle-ee", "MasterUsername": "root", "Endpoint": {"Address": "example.eu-west-2.rds.amazonaws.com"}}]}'

  run --separate-stderr run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user"
  assert_failure 1
  assert_stderr_contains "Unrecognised engine: oracle-ee"
  refute_stub_called_with "put-secret"
  refute_stub_called_with "utilities run-command"
}

@test "create-user refuses a MySQL user name longer than 32 characters before storing anything" {
  use_cluster

  run --separate-stderr run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "a23456789012345678901234567890123"
  assert_failure 1
  assert_stderr_contains "MySQL user names must be at most 32 characters"
  refute_stub_called_with "put-secret"
  refute_stub_called_with "utilities run-command"
}

@test "create-user accepts a 32 character MySQL user name" {
  use_cluster

  run run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "a2345678901234567890123456789012"
  assert_success
}

@test "create-user allows a Postgres user name longer than 32 characters" {
  run run_command bin/rds/v2/create-user -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "a23456789012345678901234567890123"
  assert_success
}
