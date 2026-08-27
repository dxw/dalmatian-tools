#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
}

@test "pick_ec2_instance returns the only instance without prompting" {
  run pick_ec2_instance -j "$(fixture_json ec2-describe-instances-one.json)"
  assert_success
  assert_output "i-0123456789abcdef0"
}

@test "pick_ec2_instance fails when there is nothing to pick" {
  run --separate-stderr pick_ec2_instance -j "$(fixture_json ec2-describe-instances-empty.json)"
  assert_failure
  assert_stderr_contains "No running instances to choose from"
}

@test "pick_ec2_instance refuses to prompt with no terminal" {
  run --separate-stderr pick_ec2_instance -j "$(fixture_json ec2-describe-instances-two.json)" < /dev/null
  assert_failure
  assert_stderr_contains "there is no terminal to choose one with"
}

@test "pick_ec2_instance lists the candidates when it cannot prompt" {
  run --separate-stderr pick_ec2_instance -j "$(fixture_json ec2-describe-instances-two.json)" < /dev/null
  assert_failure
  assert_stderr_contains "i-0123456789abcdef0"
  assert_stderr_contains "i-0fedcba987654321f"
  assert_stderr_contains "Pass an instance id explicitly with \`-I\`"
}

@test "pick_ec2_instance rejects a missing -j" {
  run --separate-stderr pick_ec2_instance
  assert_failure
  assert_stderr_contains "Invalid \`pick_ec2_instance\` function usage"
}
