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

  # The exit status is deliberately not asserted, because it is a race.
  #
  # The stubbed `logs tail --follow &` background job exits almost instantly
  # (the stub has no real "follow" behaviour), so the script's final
  # `kill $LOG_PID` may find the process already gone -- in which case kill
  # returns non-zero and errexit fails the whole script even though every AWS
  # call above it succeeded -- or may still win, in which case the script exits
  # 0. Which way it falls depends on whether the shell has reaped the job yet,
  # so asserting either outcome makes the test flaky. That unguarded kill is
  # filed as part of #523; the same thing would happen for real if `aws logs
  # tail` exited early (expired credentials, a reset connection, a very
  # short-lived task).
  #
  # What is deterministic is everything up to the kill, which is what the
  # assertions below cover.
  run run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "echo hi"
  assert_stub_called_with "rds describe-db-instances --db-instance-identifier ccb69c87-example-rds"
  assert_stub_called_with "ecs run-task --cluster example-project-example-infra-staging-infrastructure-utilities --launch-type FARGATE --task-definition example-project-example-infra-staging-infrastructure-utilities-example-rds"

  # The `logs tail` call is deliberately not asserted. The script backgrounds
  # it with `&` (line 315-321), so whether the stub has written its line to the
  # call log by the time this test reads the log is a second race, separate
  # from the kill one. Asserting it failed roughly one run in twenty.
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

  # As in the "finds the DB instance" test above, the exit status is a race on
  # the final `kill $LOG_PID` and so is not asserted. The wrapping is what
  # this test is for, and that is deterministic.
  run run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "SELECT 1;" -s
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

  # Matched without a trailing space on purpose. The message really is
  # "Unrecognised engine: " with nothing after the colon, but whether that
  # trailing space survives into $stderr depends on whether another line
  # follows it -- and what follows is the kill race described above. Asserting
  # the space made this test fail roughly a third of the time.
  assert_stderr_contains "Unrecognised engine:"

  # The point of the test: $ENGINE is unset, so the real engine name must not
  # appear. This is what would break if the script were fixed to use
  # $DB_ENGINE.
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
