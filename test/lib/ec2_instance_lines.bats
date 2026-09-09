#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  load_all_functions
}

@test "ec2_instance_lines renders one line per instance" {
  run ec2_instance_lines -j "$(fixture_json ec2-describe-instances-two.json)"
  assert_success
  [ "${#lines[@]}" -eq 2 ]
}

@test "ec2_instance_lines puts the instance id first" {
  run ec2_instance_lines -j "$(fixture_json ec2-describe-instances-one.json)"
  assert_success
  assert_output "i-0123456789abcdef0 | example-infra-staging-ecs | 2026-01-01T00:00:00+00:00"
}

@test "ec2_instance_lines keeps an untagged instance and calls it No Name" {
  run ec2_instance_lines -j "$(fixture_json ec2-describe-instances-two.json)"
  assert_success
  assert_line 1 "i-0fedcba987654321f | No Name | 2026-01-02T00:00:00+00:00"
}

@test "ec2_instance_lines treats an empty Name tag as No Name" {
  run ec2_instance_lines -j "$(fixture_json ec2-describe-instances-empty-name.json)"
  assert_success
  assert_output_contains "No Name"
}

@test "ec2_instance_lines produces nothing for no instances" {
  run ec2_instance_lines -j "$(fixture_json ec2-describe-instances-empty.json)"
  assert_success
  assert_output ""
}

@test "ec2_instance_lines rejects a missing -j" {
  run --separate-stderr ec2_instance_lines
  assert_failure
  assert_stderr_contains "Invalid \`ec2_instance_lines\` function usage"
}
