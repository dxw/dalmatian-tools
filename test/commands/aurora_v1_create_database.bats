#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-ssm-get_parameters rds-v1-ssm-get-parameters.json
  stub_response_file aws-rds-describe_db_clusters aurora-v1-describe-db-cluster-single.json
  stub_response_file aws-ec2-describe_instances rds-v1-ec2-describe-instances-single.json
}

@test "aurora create-database prints usage with no arguments" {
  run --separate-stderr run_command bin/aurora/v1/create-database
  assert_failure 1
  assert_stderr_contains "Usage: create-database"
  assert_output_contains "-u <user_name>"
}

@test "aurora create-database requires a user password and does not start a session" {
  run --separate-stderr run_command bin/aurora/v1/create-database \
    -i "example-infra" -r "example-rds" -e "staging" -d "exampledb" -u "exampleuser"
  assert_failure 1
  refute_stub_called_with "ssm start-session"
}

@test "aurora create-database -h prints usage and does not start a session" {
  run --separate-stderr run_command bin/aurora/v1/create-database -h
  assert_failure 1
  refute_stub_called_with "ssm start-session"
}

# Diverges from the rds twin: aurora reads the password from the
# "-aurora/password" parameter and looks up the cluster with
# `describe-db-clusters --db-cluster-identifier`, not the "-rds/password"
# parameter and `describe-db-instances`. It also never computes or logs a VPC
# ID -- rds does, purely for a log line, and neither script actually uses it
# to scope the ECS instance search (both call the shared pick_ecs_instance
# with only -i/-e). Verified directly against both scripts.
@test "aurora create-database creates the db with an explicitly given ECS instance" {
  run run_command bin/aurora/v1/create-database \
    -i "example-infra" -r "example-rds" -e "staging" \
    -d "exampledb" -u "exampleuser" -P "exampleuserpass" -I "i-0fedcba987654321f"
  assert_success
  assert_stub_called_with "ssm get-parameters --names /example-infra/exampleinfraexamplerdsstaging-aurora/password"
  assert_stub_called_with "rds describe-db-clusters --db-cluster-identifier exampleinfraexamplerdsstaging"
  assert_stub_called_with "ssm start-session --target i-0fedcba987654321f --document-name exampleinfraexamplerdsstaging-aurora-db-creation --parameters RootPassword=example-root-password,NewDbName=exampledb,NewUserName=exampleuser,NewUserPassword=exampleuserpass"
}

# Same pre-existing pick_ecs_instance quirk as the rds twin: that function's
# own `getopts "i:e"` is missing the colon after `e`, so in isolation -e's
# value never reaches its OPTARG. Here OPTIND is already past this script's
# own option parsing when pick_ecs_instance is called, so its getopts loop
# matches nothing and its INFRASTRUCTURE_NAME/ENVIRONMENT locals fall through
# to this script's identically-named globals, which happen to hold the right
# values. The filter below is correct today only because of that
# variable-name and OPTIND coincidence. Verified directly against both the
# isolated function and this call site.
@test "aurora create-database picks an ECS instance by infra+environment tag when -I is omitted" {
  run run_command bin/aurora/v1/create-database \
    -i "example-infra" -r "example-rds" -e "staging" \
    -d "exampledb" -u "exampleuser" -P "exampleuserpass"
  assert_success
  assert_stub_called_with "Name=tag:Name,Values=example-infra-staging*"
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0"
}

@test "aurora create-database fails and does not start a session when the password lookup fails" {
  stub_exit aws-ssm-get_parameters 1
  run --separate-stderr run_command bin/aurora/v1/create-database \
    -i "example-infra" -r "example-rds" -e "staging" \
    -d "exampledb" -u "exampleuser" -P "exampleuserpass"
  assert_failure
  refute_stub_called_with "ssm start-session"
}
