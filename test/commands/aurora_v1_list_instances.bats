#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-rds-describe_db_clusters aurora-v1-describe-db-clusters.json
}

@test "aurora list-instances prints usage with no arguments" {
  # usage() sends only its first line to stderr; the option list is plain
  # `echo`, so it lands on stdout. Same as the rds twin.
  run --separate-stderr run_command bin/aurora/v1/list-instances
  assert_failure 1
  assert_stderr_contains "Usage: list-instances"
  assert_output_contains "-i <infrastructure>"
}

@test "aurora list-instances requires an environment" {
  run --separate-stderr run_command bin/aurora/v1/list-instances -i "example-infra"
  assert_failure 1
  assert_stderr_contains "Usage: list-instances"
}

@test "aurora list-instances requires an infrastructure" {
  run --separate-stderr run_command bin/aurora/v1/list-instances -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: list-instances"
}

@test "aurora list-instances -h prints usage" {
  run --separate-stderr run_command bin/aurora/v1/list-instances -h
  assert_failure 1
  assert_stderr_contains "Usage: list-instances"
}

# Diverges from the rds twin: aurora calls `aws rds describe-db-clusters` and
# reads .DBClusters[]/.DBClusterIdentifier, with .Endpoint as a plain string
# field (a cluster endpoint), not the .Endpoint.Address/.Endpoint.Port object
# an instance has. rds calls describe-db-instances instead. Verified directly
# against both scripts.
@test "aurora list-instances filters by infrastructure and environment, ignoring dashes" {
  run run_command bin/aurora/v1/list-instances -i "example-infra" -e "staging"
  assert_success
  assert_output "Name: exampleinfraexampledbstaging Engine: aurora-postgresql Address: exampleinfraexampledbstaging.cluster-abc123.eu-west-2.rds.amazonaws.com:5432"
}

@test "aurora list-instances excludes instances that only match one half of the search" {
  run run_command bin/aurora/v1/list-instances -i "example-infra" -e "staging"
  assert_success
  refute_output_line "Name: exampleinfraexampledbprod Engine: aurora-postgresql Address: exampleinfraexampledbprod.cluster-abc123.eu-west-2.rds.amazonaws.com:5432"
  refute_output_line "Name: otherinfraexampledbstaging Engine: aurora-mysql Address: otherinfraexampledbstaging.cluster-abc123.eu-west-2.rds.amazonaws.com:3306"
}

# grep is the last command in the pipeline, so when nothing matches, the
# script exits with grep's own non-zero status and prints nothing anywhere.
# Same existing behaviour as the rds twin.
@test "aurora list-instances fails silently with no output when nothing matches" {
  run --separate-stderr run_command bin/aurora/v1/list-instances -i "no-such-infra" -e "staging"
  assert_failure
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "aurora list-instances fails when the AWS call fails" {
  stub_exit aws-rds-describe_db_clusters 1
  run --separate-stderr run_command bin/aurora/v1/list-instances -i "example-infra" -e "staging"
  assert_failure
}
