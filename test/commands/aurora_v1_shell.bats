#!/usr/bin/env bats
#
# bin/aurora/v1/shell ends by dropping into an interactive `aws ssm
# start-session` DB shell. These tests cover argument validation, the -l
# listing shortcut, and every AWS call the script makes on the way to that
# final `aws ssm start-session` invocation -- including asserting its exact
# parameters, since `aws` is stubbed here and the call returns immediately
# rather than opening a real session. They stop there: nothing simulates
# typing at the shell the real command would hand control to.

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-ssm-get_parameters rds-v1-ssm-get-parameters.json
  stub_response_file aws-rds-describe_db_clusters aurora-v1-describe-db-cluster-single.json
  stub_response_file aws-ec2-describe_instances rds-v1-ec2-describe-instances-single.json
}

@test "aurora shell prints usage with no arguments" {
  run --separate-stderr run_command bin/aurora/v1/shell
  assert_failure 1
  assert_stderr_contains "Usage: dalmatian v1 shell [OPTIONS]"
  assert_output_contains "-r <aurora_name>"
}

@test "aurora shell requires an RDS name" {
  run --separate-stderr run_command bin/aurora/v1/shell -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: dalmatian v1 shell [OPTIONS]"
}

@test "aurora shell -h prints usage" {
  run --separate-stderr run_command bin/aurora/v1/shell -h
  assert_failure 1
  assert_stderr_contains "Usage: dalmatian v1 shell [OPTIONS]"
}

# -l is a self-contained shortcut: it lists ECS instances by infra+environment
# tag and exits before the password/cluster lookup or any session starts.
@test "aurora shell -l lists ECS instances and exits without touching SSM or the cluster" {
  run run_command bin/aurora/v1/shell -i "example-infra" -r "example-rds" -e "staging" -l
  assert_success
  assert_stub_called_with "Name=tag:Name,Values=example-infra-staging*"
  assert_output_contains "i-0123456789abcdef0"
  refute_stub_called_with "ssm get-parameters"
  refute_stub_called_with "describe-db-clusters"
  refute_stub_called_with "ssm start-session"
}

# Diverges from the get-root-password/create-database/export-dump family:
# aurora shell prints "Engine: ..." and "Root username: ..." with a plain
# `echo`, not `log_msg`/`log_info -q "$QUIET_MODE"`, so -- unlike those
# commands -- these lines are not suppressed by QUIET_MODE. Verified directly
# against the script.
@test "aurora shell prints engine and username even under QUIET_MODE" {
  run run_command bin/aurora/v1/shell -i "example-infra" -r "example-rds" -e "staging" -I "i-0fedcba987654321f"
  assert_success
  assert_output_contains "Engine: aurora-postgresql"
  assert_output_contains "Root username: dbadmin"
}

# Diverges from every other aurora/v1 command that reaches an
# `aws ssm start-session`: this script has a bare `set -x` right before the
# final command, left over from debugging. Under bats that xtrace line is
# written to stderr, so the exact `aws ssm start-session ...` invocation the
# script is about to run is visible there too -- something no other command in
# this family does. Verified directly against the script.
@test "aurora shell builds the -aurora identifiers and starts the session, tracing the final command to stderr" {
  run --separate-stderr run_command bin/aurora/v1/shell \
    -i "example-infra" -r "example-rds" -e "staging" -I "i-0fedcba987654321f"
  assert_success
  assert_stub_called_with "ssm get-parameters --names /example-infra/exampleinfraexamplerdsstaging-aurora/password"
  assert_stub_called_with "rds describe-db-clusters --db-cluster-identifier exampleinfraexamplerdsstaging"
  assert_stub_called_with "ssm start-session --target i-0fedcba987654321f --document-name exampleinfraexamplerdsstaging-aurora-shell --parameters RootPassword=example-root-password"
  assert_stderr_contains "ssm start-session"
}

@test "aurora shell falls back to picking an ECS instance by infra+environment tag when -I is omitted" {
  run run_command bin/aurora/v1/shell -i "example-infra" -r "example-rds" -e "staging"
  assert_success
  assert_stub_called_with "Name=tag:Name,Values=example-infra-staging*"
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0"
}

@test "aurora shell fails and does not start a session when the password lookup fails" {
  stub_exit aws-ssm-get_parameters 1
  run --separate-stderr run_command bin/aurora/v1/shell -i "example-infra" -r "example-rds" -e "staging"
  assert_failure
  refute_stub_called_with "ssm start-session"
}
