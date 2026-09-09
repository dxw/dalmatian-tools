#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-rds-describe_db_instances rds-v1-describe-db-instances.json
}

@test "rds list-instances prints usage with no arguments" {
  # usage() sends only its first line to stderr; the option list (lines 9-11
  # of the script) is plain `echo`, so it lands on stdout.
  run --separate-stderr run_command bin/rds/v1/list-instances
  assert_failure 1
  assert_stderr_contains "Usage: list-instances"
  assert_output_contains "-i <infrastructure>"
}

@test "rds list-instances requires an environment" {
  run --separate-stderr run_command bin/rds/v1/list-instances -i "example-infra"
  assert_failure 1
  assert_stderr_contains "Usage: list-instances"
}

@test "rds list-instances requires an infrastructure" {
  run --separate-stderr run_command bin/rds/v1/list-instances -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: list-instances"
}

@test "rds list-instances -h prints usage" {
  run --separate-stderr run_command bin/rds/v1/list-instances -h
  assert_failure 1
  assert_stderr_contains "Usage: list-instances"
}

@test "rds list-instances filters by infrastructure and environment, ignoring dashes" {
  run run_command bin/rds/v1/list-instances -i "example-infra" -e "staging"
  assert_success
  assert_output "Name: exampleinfraexampledbstaging Engine: postgres Address: exampleinfraexampledbstaging.abc123.eu-west-2.rds.amazonaws.com:5432"
}

@test "rds list-instances excludes instances that only match one half of the search" {
  run run_command bin/rds/v1/list-instances -i "example-infra" -e "staging"
  assert_success
  refute_output_line "Name: exampleinfraexampledbprod Engine: postgres Address: exampleinfraexampledbprod.abc123.eu-west-2.rds.amazonaws.com:5432"
  refute_output_line "Name: otherinfraexampledbstaging Engine: mysql Address: otherinfraexampledbstaging.abc123.eu-west-2.rds.amazonaws.com:3306"
}

# grep is the last command in the pipeline, so when nothing matches, the
# script exits with grep's own non-zero status. There is no "no instances
# found" message anywhere in this script -- an unmatched search fails silently
# with empty output. This is existing behaviour of the script under test.
@test "rds list-instances fails silently with no output when nothing matches" {
  run --separate-stderr run_command bin/rds/v1/list-instances -i "no-such-infra" -e "staging"
  assert_failure
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "rds list-instances fails when the AWS call fails" {
  stub_exit aws-rds-describe_db_instances 1
  run --separate-stderr run_command bin/rds/v1/list-instances -i "example-infra" -e "staging"
  assert_failure
}
