#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  stub_dalmatian
  load_all_functions
  stub_response_file dalmatian-aws-run_command-p-example_account-ec2-describe_instances marklogic-describe-instances.json
}

@test "marklogic_stack_nodes queries the running instances tagged for the stack" {
  run marklogic_stack_nodes -p example-account -n cf-ccb69c87-marklogic-cluster
  assert_success
  assert_call_args dalmatian aws run-command -p example-account ec2 describe-instances --filters "Name=tag:marklogic:stack:name,Values=cf-ccb69c87-marklogic-cluster" "Name=instance-state-name,Values=running"
  assert_output_contains '"InstanceId": "i-0aaaaaaaaaaaaaaaa"'
}

@test "marklogic_stack_nodes rejects missing arguments" {
  run --separate-stderr marklogic_stack_nodes -p example-account
  assert_failure
  assert_stderr_contains "Invalid \`marklogic_stack_nodes\` function usage"
}

@test "marklogic_node_lines formats one line per node with name, zone, AMI and launch time" {
  run marklogic_node_lines -j "$(fixture_json marklogic-describe-instances.json)"
  assert_success
  assert_line 0 "i-0aaaaaaaaaaaaaaaa | marklogic-1 | eu-west-2a | ami-0old0000000000000 | 2026-07-09T15:43:13+00:00"
  assert_line 1 "i-0bbbbbbbbbbbbbbbb | No Name | eu-west-2b | ami-0old0000000000000 | 2026-07-09T16:19:10+00:00"
}

@test "marklogic_node_lines rejects a missing -j" {
  run --separate-stderr marklogic_node_lines
  assert_failure
  assert_stderr_contains "Invalid \`marklogic_node_lines\` function usage"
}
