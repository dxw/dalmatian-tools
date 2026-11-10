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

  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-describe_tasks v2-ecs-describe-tasks-exited-0.json

  run run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "echo hi"
  assert_success
  assert_stub_called_with "rds describe-db-instances --db-instance-identifier ccb69c87-example-rds"
  assert_stub_called_with "ecs run-task --cluster example-project-example-infra-staging-infrastructure-utilities --launch-type FARGATE --task-definition example-project-example-infra-staging-infrastructure-utilities-example-rds"

  # The `logs tail` call is deliberately not asserted. The script backgrounds
  # it with `&`, so whether the stub has written its line to the
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

  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-describe_tasks v2-ecs-describe-tasks-exited-0.json

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

@test "utilities_v2_run_command targets resources using the override" {
  jq '.terraform_project_name = .project_name | .project_name = "installation-project"' "$CONFIG_SETUP_JSON_FILE" > "$SANDBOX/override.json"
  mv "$SANDBOX/override.json" "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-aws-run_command-p-example_account-rds-describe_db_instances v2-rds-describe-db-instances.json
  stub_response_file dalmatian-aws-run_command-p-example_account-rds-describe_db_subnet_groups v2-rds-describe-db-subnet-groups.json

  run run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "echo hi"
  assert_stub_called_with "rds describe-db-instances --db-instance-identifier ccb69c87-example-rds"
  assert_stub_called_with "ecs run-task --cluster example-project-example-infra-staging-infrastructure-utilities --launch-type FARGATE --task-definition example-project-example-infra-staging-infrastructure-utilities-example-rds"

}

run_rc_setup() {
  stub_response_file dalmatian-aws-run_command-p-example_account-rds-describe_db_instances v2-rds-describe-db-instances.json
  stub_response_file dalmatian-aws-run_command-p-example_account-rds-describe_db_subnet_groups v2-rds-describe-db-subnet-groups.json
  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-describe_tasks "v2-ecs-describe-tasks-$1.json"
}

@test "run-command exits with the utilities container's exit code" {
  run_rc_setup exited-3
  run run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "false"
  assert_failure 3
}

@test "run-command exits 0 when the container exits 0" {
  run_rc_setup exited-0
  run run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "true"
  assert_success
}

@test "run-command writes the outcome to the -R file" {
  run_rc_setup exited-3
  run run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "false" -R "$SANDBOX/result"
  assert_failure 3
  [ "$(cat "$SANDBOX/result")" = "exited 3" ] || fail "result file was: $(cat "$SANDBOX/result")"
}

@test "run-command writes never-ran and the stopped reason when the container has no exit code" {
  run_rc_setup never-ran
  run --separate-stderr run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "true" -R "$SANDBOX/result"
  assert_failure 1
  [ "$(cat "$SANDBOX/result")" = "never-ran" ] || fail "result file was: $(cat "$SANDBOX/result")"
  assert_stderr_contains "CannotPullContainerError: image not found"
}

@test "run-command leaves -R empty and fails when the task started but the container has no exit code" {
  run_rc_setup started-no-exit-code
  : > "$SANDBOX/result"
  run --separate-stderr run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "true" -R "$SANDBOX/result"
  assert_failure 1
  [ ! -s "$SANDBOX/result" ] || fail "result file was: $(cat "$SANDBOX/result")"
  assert_stderr_contains "Task stopped by user"
}

# A task that finishes within one 6 s poll is already STOPPED when
# tasks-running first looks, which that waiter treats as a terminal failure.
@test "run-command still reports the exit code when the tasks-running wait fails" {
  run_rc_setup exited-3
  stub_exit dalmatian-aws-run_command-p-example_account-ecs-wait-tasks_running 255
  run run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "false" -R "$SANDBOX/result"
  assert_failure 3
  [ "$(cat "$SANDBOX/result")" = "exited 3" ] || fail "result file was: $(cat "$SANDBOX/result")"
  assert_stub_called_with "ecs wait tasks-stopped"
}

@test "run-command leaves the -R file empty when the wait fails" {
  run_rc_setup exited-0
  stub_exit dalmatian-aws-run_command-p-example_account-ecs-wait-tasks_stopped 255
  : > "$SANDBOX/result"
  run run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "true" -R "$SANDBOX/result"
  assert_failure
  [ ! -s "$SANDBOX/result" ] || fail "result file was: $(cat "$SANDBOX/result")"
}

@test "run-command leaves the -R file empty when describe-tasks returns no task" {
  run_rc_setup no-task
  : > "$SANDBOX/result"
  run --separate-stderr run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "true" -R "$SANDBOX/result"
  assert_failure 1
  [ ! -s "$SANDBOX/result" ] || fail "result file was: $(cat "$SANDBOX/result")"
  assert_stderr_contains "Could not determine the outcome"
  assert_stderr_contains "MISSING"
}

@test "run-command refuses -R with -I" {
  run --separate-stderr run_command bin/utilities/v2/run-command -i "example-infra" -e "staging" -I -R "$SANDBOX/result"
  assert_failure 1
  assert_stderr_contains "Usage: run-command"
}
