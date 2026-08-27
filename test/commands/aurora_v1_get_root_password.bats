#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-ssm-get_parameters rds-v1-ssm-get-parameters.json
  stub_response_file aws-rds-describe_db_clusters aurora-v1-describe-db-cluster-single.json
}

@test "aurora get-root-password prints usage with no arguments" {
  run --separate-stderr run_command bin/aurora/v1/get-root-password
  assert_failure 1
  assert_stderr_contains "Usage: dalmatian v1 get-root-password"
  assert_output_contains "-r <aurora_name>"
}

@test "aurora get-root-password requires an environment" {
  run --separate-stderr run_command bin/aurora/v1/get-root-password -i "example-infra" -r "example-rds"
  assert_failure 1
  assert_stderr_contains "Usage: dalmatian v1 get-root-password"
}

# usage() derives the first word of its message from
# basename(dirname($BASH_SOURCE)), which is the version directory ("v1"), not
# the command family ("aurora"). Same existing behaviour as the rds twin,
# verified directly against the script.
@test "aurora get-root-password -h prints the usage banner as the script actually renders it" {
  run --separate-stderr run_command bin/aurora/v1/get-root-password -h
  assert_failure 1
  assert_stderr_contains "Usage: dalmatian v1 get-root-password [OPTIONS]"
}

# Diverges from the rds twin: aurora reads the password from
# "<identifier>-aurora/password" and looks the cluster up with
# `describe-db-clusters --db-cluster-identifier`, not
# "<identifier>-rds/password" and `describe-db-instances`.
@test "aurora get-root-password builds the RDS identifier from infra+rds+env with dashes stripped" {
  run run_command bin/aurora/v1/get-root-password -i "example-infra" -r "example-rds" -e "staging"
  assert_success
  assert_stub_called_with "ssm get-parameters --names /example-infra/exampleinfraexamplerdsstaging-aurora/password --with-decryption"
  assert_stub_called_with "rds describe-db-clusters --db-cluster-identifier exampleinfraexamplerdsstaging"
}

@test "aurora get-root-password prints the username and password from AWS" {
  run run_command bin/aurora/v1/get-root-password -i "example-infra" -r "example-rds" -e "staging"
  assert_success
  assert_line 0 "Root username: dbadmin"
  assert_line 1 "Root password: example-root-password"
}

@test "aurora get-root-password fails without printing anything when the parameter lookup fails" {
  stub_exit aws-ssm-get_parameters 1
  run --separate-stderr run_command bin/aurora/v1/get-root-password -i "example-infra" -r "example-rds" -e "staging"
  assert_failure
  [ -z "$output" ]
}
