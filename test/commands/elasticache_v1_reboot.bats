#!/usr/bin/env bats

load ../test_helper

# reboot targets whichever cluster's tags have BOTH Name==<-c> and
# Environment==<-e>. The fixture deliberately gives both clusters the same
# Name ("cache") in different environments, so a wrong-target reboot would
# show up as the prod cluster (example-cluster-002) being rebooted instead of
# (or as well as) the staging one (example-cluster-001).
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

@test "reboot prints usage with no arguments" {
  run --separate-stderr run_command bin/elasticache/v1/reboot
  assert_failure 1
  assert_stderr_contains "Usage: reboot"
  assert_output_contains "-c <cluster_name>"
}

@test "reboot -h shows usage and exits 0" {
  run --separate-stderr run_command bin/elasticache/v1/reboot -h
  assert_success
  assert_stderr_contains "Usage: reboot"
}

@test "reboot requires a cluster name" {
  run --separate-stderr run_command bin/elasticache/v1/reboot -i example-infra -e staging
  assert_failure 1
  assert_stderr_contains "Usage: reboot"
}

@test "reboot requires an environment" {
  run --separate-stderr run_command bin/elasticache/v1/reboot -i example-infra -c cache
  assert_failure 1
  assert_stderr_contains "Usage: reboot"
}

@test "reboot requires an infrastructure" {
  run --separate-stderr run_command bin/elasticache/v1/reboot -e staging -c cache
  assert_failure 1
  assert_stderr_contains "Usage: reboot"
}

@test "reboot reboots exactly the cluster matching both name and environment" {
  run run_command bin/elasticache/v1/reboot -i example-infra -e staging -c cache
  assert_success
  assert_stub_called_with "reboot-cache-cluster --cache-cluster-id example-cluster-001 --cache-node-ids-to-reboot 0001"
}

# The most important safety property of a destructive command: same -c name,
# different -e environment, must NOT reboot the other environment's cluster.
@test "reboot does not touch the same-named cluster in a different environment" {
  run run_command bin/elasticache/v1/reboot -i example-infra -e staging -c cache
  assert_success
  refute_stub_called_with "cache-cluster-id example-cluster-002"
}

@test "reboot with an environment that matches nothing reboots no cluster at all" {
  run run_command bin/elasticache/v1/reboot -i example-infra -e nonexistent-env -c cache
  assert_success
  refute_stub_called_with "reboot-cache-cluster"
}

@test "reboot with an unknown cluster name reboots nothing, even though the environment matches" {
  run run_command bin/elasticache/v1/reboot -i example-infra -e staging -c no-such-cluster
  assert_success
  refute_stub_called_with "reboot-cache-cluster"
}

@test "reboot -v verbose mode reports the node ids without changing the target" {
  QUIET_MODE=0 run run_command bin/elasticache/v1/reboot -i example-infra -e staging -c cache -v
  assert_success
  assert_output_contains "Rebooting node(s) 0001 in Elasticache cluster example-infra-cache-staging (id: example-cluster-001)..."
  assert_stub_called_with "reboot-cache-cluster --cache-cluster-id example-cluster-001 --cache-node-ids-to-reboot 0001"
}
