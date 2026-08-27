#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-ec2-describe_security_groups util-v1-security-groups.json
}

@test "util list-security-group-rules prints usage and exits 1 with -h" {
  run --separate-stderr run_command bin/util/v1/list-security-group-rules -h
  assert_failure 1
  assert_stderr_contains "Usage: list-security-group-rules"
  assert_output_contains "List all the open ports"
  assert_output_contains "-i <infrastructure>"
}

@test "util list-security-group-rules prints usage and exits 1 for an unrecognised option" {
  run --separate-stderr run_command bin/util/v1/list-security-group-rules -z
  assert_failure 1
  assert_stderr_contains "Usage: list-security-group-rules"
}

@test "util list-security-group-rules lists a CSV row per CIDR/group/IPv6 entry" {
  run run_command bin/util/v1/list-security-group-rules
  assert_success
  [ "${#lines[@]}" -eq 5 ]
  assert_line 0 "web-sg,443-443,0.0.0.0/0"
  assert_line 1 "web-sg,443-443,sg-abc123"
  assert_line 2 "web-sg,443-443,::/0"
  assert_line 3 "web-sg,22-22,10.0.0.0/8"
  assert_line 4 "db-sg,5432-5432,sg-web123"
}

@test "util list-security-group-rules does not actually accept an infrastructure argument" {
  # getopts is declared as "ih" -- no colon after i -- so -i takes no
  # argument. Given "-i example-infra", getopts consumes only "-i" and leaves
  # "example-infra" as an unused stray positional argument; $INFRASTRUCTURE_NAME
  # is always empty. Output is identical with or without -i.
  run run_command bin/util/v1/list-security-group-rules -i example-infra
  assert_success
  [ "${#lines[@]}" -eq 5 ]
  assert_line 0 "web-sg,443-443,0.0.0.0/0"
}

@test "util list-security-group-rules logs an (always empty) infrastructure name" {
  export QUIET_MODE=0
  run run_command bin/util/v1/list-security-group-rules -i example-infra
  assert_success
  # Documents the -i bug above: the logged account name is blank, not
  # "example-infra", because $INFRASTRUCTURE_NAME was never actually set.
  # (log_info's output is wrapped in ANSI colour codes, so this checks a
  # substring rather than the exact line.)
  assert_output_contains "Open Ports in the  account"
}

@test "util list-security-group-rules calls the aws CLI with no query or filtering" {
  run run_command bin/util/v1/list-security-group-rules
  assert_success
  assert_stub_called_with "aws ec2 describe-security-groups"
  refute_stub_called_with "--query"
}

@test "util list-security-group-rules produces no rows when there are no security groups" {
  stub_response aws-ec2-describe_security_groups <<< '{"SecurityGroups": []}'

  run run_command bin/util/v1/list-security-group-rules
  assert_success
  assert_output ""
}
