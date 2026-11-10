#!/usr/bin/env bats

load ../test_helper

CLUSTERS=dalmatian-aws-run_command-p-example_account-rds-describe_db_clusters
INSTANCES=dalmatian-aws-run_command-p-example_account-rds-describe_db_instances
GET_REGION=dalmatian-aws-run_command-p-example_account-configure-get-region

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
  stub_dalmatian
  stub_rds_not_found "$CLUSTERS" DBClusterNotFoundFault
  stub_response_file "$INSTANCES" v2-rds-describe-db-instances-postgres.json
  stub_response "$GET_REGION" "eu-west-2"
}

@test "rds_target prints the engine, writer endpoint, root username and region" {
  run rds_target -p example-account -i ccb69c87-example-rds
  assert_success
  [ "$(echo "$output" | jq -r '.engine')" == "postgres" ]
  [ "$(echo "$output" | jq -r '.endpoint')" == "ccb69c87-example-rds.abcdefghijkl.eu-west-2.rds.amazonaws.com" ]
  [ "$(echo "$output" | jq -r '.root_username')" == "root" ]
  [ "$(echo "$output" | jq -r '.region')" == "eu-west-2" ]
}

@test "rds_target gives a cluster's writer endpoint, not its reader" {
  unstub "$CLUSTERS"
  stub_response_file "$CLUSTERS" v2-rds-describe-db-clusters-aurora-mysql-full.json

  run rds_target -p example-account -i ccb69c87-example-rds
  assert_success
  [ "$(echo "$output" | jq -r '.endpoint')" == "ccb69c87-example-rds.cluster-abcdefghijkl.eu-west-2.rds.amazonaws.com" ]
}

@test "rds_target refuses an unexpected endpoint" {
  stub_response "$INSTANCES" '{"DBInstances": [{"Engine": "postgres", "MasterUsername": "root", "Endpoint": {"Address": "x;id"}}]}'

  run --separate-stderr rds_target -p example-account -i ccb69c87-example-rds
  assert_failure 1
  assert_stderr_contains "Unexpected endpoint"
}

@test "rds_target refuses an unexpected root username" {
  stub_response "$INSTANCES" '{"DBInstances": [{"Engine": "postgres", "MasterUsername": "ro-ot", "Endpoint": {"Address": "example.eu-west-2.rds.amazonaws.com"}}]}'

  run --separate-stderr rds_target -p example-account -i ccb69c87-example-rds
  assert_failure 1
  assert_stderr_contains "Unexpected root username"
}

@test "rds_target refuses an unexpected region" {
  stub_response "$GET_REGION" 'eu west'

  run --separate-stderr rds_target -p example-account -i ccb69c87-example-rds
  assert_failure 1
  assert_stderr_contains "Unexpected region"
}

@test "rds_target requires a profile and an identifier" {
  run --separate-stderr rds_target -p example-account
  assert_failure 1
  assert_stderr_contains "Invalid \`rds_target\` function usage"
}
