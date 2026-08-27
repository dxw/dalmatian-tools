#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1

  stub_response_file aws-elasticache-describe_cache_clusters cdn-elasticache-clusters.json
  stub_response_file \
    aws-elasticache-list_tags_for_resource-resource_name-arn_aws_elasticache_eu_west_2_123456789012_cluster_example_cluster_001 \
    cdn-elasticache-tags-cluster-001-staging.json
  stub_response_file \
    aws-elasticache-list_tags_for_resource-resource_name-arn_aws_elasticache_eu_west_2_123456789012_cluster_example_cluster_002 \
    cdn-elasticache-tags-cluster-002-prod.json
}

@test "list-clusters prints usage with no arguments" {
  run --separate-stderr run_command bin/elasticache/v1/list-clusters
  assert_failure 1
  assert_stderr_contains "Usage: list-clusters"
  assert_output_contains "-i <infrastructure>"
}

# usage() takes an explicit exit code, and -h passes it 0 -- unlike a bare
# invocation or a validation failure, -h alone actually exits successfully.
@test "list-clusters -h shows usage and exits 0" {
  run --separate-stderr run_command bin/elasticache/v1/list-clusters -h
  assert_success
  assert_stderr_contains "Usage: list-clusters"
}

@test "list-clusters requires an infrastructure" {
  run --separate-stderr run_command bin/elasticache/v1/list-clusters -e staging
  assert_failure 1
  assert_stderr_contains "Usage: list-clusters"
}

# FINDING: the getopts string "i:c:e:avh" accepts -c/-a/-v, but the case
# statement (copied from reboot, presumably) only handles i/e/h -- so any of
# -c, -a or -v falls into the `*)` catch-all and always shows usage, even
# though getopts itself parses them without complaint.
@test "list-clusters -c is accepted by getopts but always falls through to usage" {
  run --separate-stderr run_command bin/elasticache/v1/list-clusters -i example-infra -c ignored
  assert_failure 1
  assert_stderr_contains "Usage: list-clusters"
}

@test "list-clusters lists every cluster's Infrastructure-Name-Environment and engine when no -e filter is given" {
  run run_command bin/elasticache/v1/list-clusters -i example-infra
  assert_success
  assert_output_contains "Name: example-infra-cache-staging Engine: redis"
  assert_output_contains "Name: example-infra-cache-prod Engine: memcached"
}

@test "list-clusters -e filters to only clusters tagged with that environment" {
  run run_command bin/elasticache/v1/list-clusters -i example-infra -e staging
  assert_success
  assert_output_contains "Name: example-infra-cache-staging Engine: redis"
  refute_output_line "Name: example-infra-cache-prod Engine: memcached"
}
