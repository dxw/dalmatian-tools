#!/usr/bin/env bats
# The task scripts are matched literally, $DB_PASSWORD and all, because the
# container expands them, not this shell
# shellcheck disable=SC2016

load ../test_helper

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

# Test passwords are made at run time rather than written out, so that no
# literal password assignment in this file trips secret scanners
fake_password() {
  printf 'fake%s%s' "$1" "$BATS_TEST_NUMBER"
}

# The command handed to `utilities run-command -c`
task_command() {
  sed -n 's/^dalmatian utilities run-command .* -c //p' "$DALMATIAN_STUB_LOG"
}

# The script it pipes into bash in the container, decoded
task_script() {
  task_command | sed -n 's/^echo \([A-Za-z0-9+\/=]*\) | base64 -d | bash$/\1/p' | base64 -d
}

# Run the decoded script as the container would, with aws answering the
# parameter lookup with $1 and mysql/psql recording their arguments and stdin
run_task_script() {
  local password=$1

  mkdir -p "$SANDBOX/container"
  printf '#!/usr/bin/env bash\nprintf "%%s" %q\n' "$password" > "$SANDBOX/container/aws"
  for client in mysql psql
  do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > %q\ncat > %q\n' \
      "$SANDBOX/$client.args" "$SANDBOX/$client.stdin" > "$SANDBOX/container/$client"
  done
  chmod +x "$SANDBOX/container/"*
  task_script > "$SANDBOX/task-script"
  DB_USER=root DB_PASSWORD="$(fake_password root)" PATH="$SANDBOX/container:$PATH" bash "$SANDBOX/task-script"
}

@test "create-database prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v2/create-database
  assert_failure 1
  assert_stderr_contains "Usage: create-database"
}

@test "create-database requires a database and a user name" {
  run --separate-stderr run_command bin/rds/v2/create-database -i "example-infra" -e "staging" -r "example-rds" -d "app"
  assert_failure 1
  assert_stderr_contains "Usage: create-database"
  refute_stub_called_with "utilities run-command"
}

@test "create-database generates a password and stores it with put-secret when none is stored" {
  run run_command bin/rds/v2/create-database -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user"
  assert_success
  assert_call_args dalmatian aws run-command -p example-account ssm get-parameter --name "$PARAMETER_NAME" --query Parameter.ARN --output text
  assert_call_args dalmatian aws put-secret -i example-infra -e staging -n rds/example-rds/app_user/password
  [[ "$(stub_stdin "$PUT_SECRET")" =~ ^[A-Za-z0-9]{32}$ ]] || fail "unexpected generated password: $(stub_stdin "$PUT_SECRET")"
}

@test "create-database reuses the password already stored for the user" {
  unstub "$GET_PARAMETER"
  stub_response "$GET_PARAMETER" "arn:aws:ssm:eu-west-2:123456789012:parameter$PARAMETER_NAME"

  run run_command bin/rds/v2/create-database -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user"
  assert_success
  refute_stub_called_with "put-secret"
  assert_stub_called_with "utilities run-command"
}

@test "create-database stores the password given with -P, replacing any stored one" {
  local given
  given="$(fake_password given)"

  run run_command bin/rds/v2/create-database -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user" -P "$given"
  assert_success
  refute_stub_called_with "ssm get-parameter"
  [ "$(stub_stdin "$PUT_SECRET")" == "$given" ]
}

@test "create-database stops on a parameter lookup failure other than not found" {
  stub_stderr "$GET_PARAMETER" "An error occurred (AccessDeniedException) when calling the GetParameter operation: denied"

  run --separate-stderr run_command bin/rds/v2/create-database -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user"
  assert_failure 254
  assert_stderr_contains "AccessDeniedException"
  refute_stub_called_with "put-secret"
  refute_stub_called_with "utilities run-command"
}

@test "create-database sends the task the parameter name and never the password" {
  local given
  given="$(fake_password given)"

  run run_command bin/rds/v2/create-database -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user" -P "$given"
  assert_success
  assert_stub_called_with "dalmatian utilities run-command -i example-infra -e staging -r example-rds -c echo "
  case "$(task_command)$(task_script)" in
    *"$given"*) fail "the password reached the task request" ;;
  esac
  task_script | grep -qF -- "aws ssm get-parameter --region eu-west-2 --name $PARAMETER_NAME --with-decryption"
}

@test "create-database creates a Postgres user, grants it to root and creates a database it owns" {
  run run_command bin/rds/v2/create-database -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user"
  assert_success

  local value
  value="$(fake_password user)"
  run_task_script "$value"
  grep -qxF -- "-h" "$SANDBOX/psql.args"
  grep -qxF -- "ccb69c87-example-rds.abcdefghijkl.eu-west-2.rds.amazonaws.com" "$SANDBOX/psql.args"
  grep -qxF -- "password=$value" "$SANDBOX/psql.args"
  [ "$(cat "$SANDBOX/psql.stdin")" == "$(printf '%s\n' \
    "CREATE USER \"app_user\" WITH PASSWORD :'password';" \
    "GRANT \"app_user\" TO \"root\";" \
    "CREATE DATABASE \"app\" OWNER \"app_user\";")" ]
}

@test "create-database creates a MySQL database on a cluster's writer endpoint, not its reader" {
  use_cluster

  run run_command bin/rds/v2/create-database -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user"
  assert_success

  local value
  value="$(fake_password user)"
  run_task_script "$value"
  grep -qxF -- "ccb69c87-example-rds.cluster-abcdefghijkl.eu-west-2.rds.amazonaws.com" "$SANDBOX/mysql.args"
  [ "$(cat "$SANDBOX/mysql.stdin")" == "$(printf '%s\n' \
    "CREATE DATABASE \`app\` DEFAULT CHARSET utf8mb4;" \
    "CREATE USER 'app_user'@'%' IDENTIFIED BY '$value';" \
    "GRANT ALL ON \`app\`.* TO 'app_user'@'%';")" ]
}

@test "create-database escapes a hostile password inside the MySQL container script" {
  use_cluster

  run run_command bin/rds/v2/create-database -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user"
  assert_success

  run_task_script "a'b\\c\"\$(touch $SANDBOX/pwned)\`x\`"
  [ ! -e "$SANDBOX/pwned" ] || fail "the password was executed"
  grep -qF "IDENTIFIED BY 'a''b\\\\c\"\$(touch $SANDBOX/pwned)\`x\`';" "$SANDBOX/mysql.stdin"
}

@test "create-database hands a hostile password to psql as a variable, unexpanded" {
  run run_command bin/rds/v2/create-database -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user"
  assert_success

  local hostile
  hostile="a'b\$(touch $SANDBOX/pwned)"
  run_task_script "$hostile"
  [ ! -e "$SANDBOX/pwned" ] || fail "the password was executed"
  grep -qxF -- "password=$hostile" "$SANDBOX/psql.args"
  grep -qF "WITH PASSWORD :'password';" "$SANDBOX/psql.stdin"
}

@test "create-database refuses a database name that is not a plain identifier" {
  run --separate-stderr run_command bin/rds/v2/create-database -i "example-infra" -e "staging" -r "example-rds" -d 'app"; DROP' -u "app_user"
  assert_failure 1
  assert_stderr_contains "Database name must be"
  refute_stub_called_with "describe-db"
}

@test "create-database refuses a user name that is not a plain identifier" {
  run --separate-stderr run_command bin/rds/v2/create-database -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app-user"
  assert_failure 1
  assert_stderr_contains "User name must be"
  refute_stub_called_with "describe-db"
}

@test "create-database refuses an RDS name that could break the parameter path" {
  run --separate-stderr run_command bin/rds/v2/create-database -i "example-infra" -e "staging" -r 'rds;id' -d "app" -u "app_user"
  assert_failure 1
  assert_stderr_contains "must be letters, digits"
  refute_stub_called_with "describe-db"
}

@test "create-database refuses an unknown engine" {
  stub_response "$INSTANCES" '{"DBInstances": [{"Engine": "oracle-ee", "MasterUsername": "root", "Endpoint": {"Address": "example.eu-west-2.rds.amazonaws.com"}}]}'

  run --separate-stderr run_command bin/rds/v2/create-database -i "example-infra" -e "staging" -r "example-rds" -d "app" -u "app_user"
  assert_failure 1
  assert_stderr_contains "Unrecognised engine: oracle-ee"
  refute_stub_called_with "utilities run-command"
}
