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
  stub_response_file dalmatian-aws-run_command-p-example_account-ec2-describe_security_groups v2-ec2-describe-security-groups.json
  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-run_task v2-ecs-run-task.json
}

@test "run-command prints usage with no arguments" {
  run --separate-stderr run_command bin/utilities/v2/run-command
  assert_failure 1
  assert_stderr_contains "Usage: run-command"
  assert_output_contains "-c <command>"
}

@test "run-command requires an infrastructure" {
  run --separate-stderr run_command bin/utilities/v2/run-command -e "staging" -c "echo hi"
  assert_failure 1
  assert_stderr_contains "Usage: run-command"
}

@test "run-command requires an environment" {
  run --separate-stderr run_command bin/utilities/v2/run-command -i "example-infra" -c "echo hi"
  assert_failure 1
  assert_stderr_contains "Usage: run-command"
}

@test "run-command requires a command unless -I is given" {
  run --separate-stderr run_command bin/utilities/v2/run-command -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: run-command"
}

@test "run-command -h shows usage" {
  run --separate-stderr run_command bin/utilities/v2/run-command -h
  assert_failure 1
  assert_stderr_contains "Usage: run-command"
}

# The `-s` validation at lines 75-82 of the script reads:
#   if [[ "$RUN_ON_RDS" == 1 && -z "$RUN_ON_RDS" ]]
# RUN_ON_RDS is set to 1 by getopts' `s)` branch and never anything else, so
# it can never be both "1" and empty at once: the intended "an RDS name is
# required with -s" check is dead code and never fires, regardless of
# whether -r was given. This documents that as existing (buggy) behaviour.
@test "BUG: -s without -r never triggers its own \"RDS name must be provided\" validation" {
  run --separate-stderr run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -c "echo hi" -s

  refute_stub_called_with "This should never match"
  case "$stderr" in
    *"An RDS name must be provided"*)
      fail "the dead validation unexpectedly fired: $stderr" ;;
  esac
  # Execution reaches real work well past the never-firing check.
  assert_stub_called_with "ec2 describe-security-groups"
}

@test "run-command finds the DB instance and runs the given command in a Fargate task" {
  stub_response_file dalmatian-aws-run_command-p-example_account-rds-describe_db_instances v2-rds-describe-db-instances.json
  stub_response_file dalmatian-aws-run_command-p-example_account-rds-describe_db_subnet_groups v2-rds-describe-db-subnet-groups.json

  # BUG: the stubbed `logs tail --follow &` background job exits almost
  # instantly (the stub has no real "follow" behaviour), so by the time the
  # script reaches its final `kill $LOG_PID` the process is already gone.
  # `kill` on a since-exited pid returns non-zero, and `set -e` turns that
  # into a whole-script failure -- even though every AWS call above it
  # (including the task actually running) succeeded. The same thing would
  # happen for real if `aws logs tail` ever exited early (expired
  # credentials, a throttled/reset connection, a very short-lived task).
  # Asserted here as actual behaviour: everything up to the final `kill` is
  # correct, but the overall exit status is still a failure.
  run run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "echo hi"
  assert_failure
  assert_output_contains "kill:"
  assert_stub_called_with "rds describe-db-instances --db-instance-identifier ccb69c87-example-rds"
  assert_stub_called_with "ecs run-task --cluster example-project-example-infra-staging-infrastructure-utilities --launch-type FARGATE --task-definition example-project-example-infra-staging-infrastructure-utilities-example-rds"
  assert_stub_called_with "logs tail example-project-example-infra-staging-infrastructure-utilities-example-rds"
}

@test "run-command fails and does not launch a task when the RDS does not exist" {
  # Neither describe-db-clusters nor describe-db-instances is stubbed, so
  # both resolve to empty output.
  run --separate-stderr run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "echo hi"
  assert_failure 1
  assert_stderr_contains "RDS ccb69c87-example-rds does not exist"
  refute_stub_called_with "ecs run-task"
}

@test "run-command wraps the command for a mysql RDS shell when -s is given" {
  stub_response_file dalmatian-aws-run_command-p-example_account-rds-describe_db_clusters v2-rds-describe-db-clusters-aurora-mysql.json
  stub_response_file dalmatian-aws-run_command-p-example_account-rds-describe_db_subnet_groups v2-rds-describe-db-subnet-groups.json

  # See the "finds the DB instance" test above: the final `kill $LOG_PID`
  # fails against the stub's already-exited background job, so the overall
  # run still fails even though the command was wrapped and dispatched
  # correctly.
  run run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "SELECT 1;" -s
  assert_failure
  assert_stub_called_with "MYSQL_PWD=\$DB_PASSWORD mysql -u \$DB_USER -h \$DB_HOST"
}

# The "$RUN_ON_RDS" == 1 engine check at lines 143-151 compares against the
# literal string "postgresql", but a real (non-aurora) Postgres RDS instance
# reports its engine as "postgres" -- so this branch never recognises it, and
# falls to `err "Unrecognised engine: $ENGINE"`. $ENGINE is never assigned
# anywhere in the script (only $DB_ENGINE is); the message is always empty
# where the engine name should be. err() does not exit, so the script
# continues past this rather than aborting.
@test "BUG: a real (non-aurora) postgres engine is unrecognised, and the error names the wrong variable" {
  stub_response_file dalmatian-aws-run_command-p-example_account-rds-describe_db_instances v2-rds-describe-db-instances.json
  stub_response_file dalmatian-aws-run_command-p-example_account-rds-describe_db_subnet_groups v2-rds-describe-db-subnet-groups.json

  run --separate-stderr run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "SELECT 1;" -s
  assert_stderr_contains "Unrecognised engine: "
  case "$stderr" in
    *"Unrecognised engine: postgres"*)
      fail "expected the message to be empty (\$ENGINE is unset), but the real engine leaked through: $stderr" ;;
  esac
}

@test "run-command fails when no AWS profile matches the infrastructure/environment" {
  stub_response aws-configure-list_profiles "dalmatian-main"

  run --separate-stderr run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -c "echo hi"
  assert_failure
  assert_stderr_contains "Profile does not exist for example-infra staging"
  refute_stub_called_with "ecs run-task"
}
