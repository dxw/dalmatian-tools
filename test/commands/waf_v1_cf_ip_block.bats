#!/usr/bin/env bats

load ../test_helper

# cf-ip-block adds/removes a single IP address in a shared CLOUDFRONT-scope IP
# set (read-modify-write against IPSet.Addresses), rather than creating a new
# rule of its own. It never touches a Web ACL.
setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-wafv2-list_ip_sets waf-v1-cloudfront-list-ip-sets.json
  stub_response_file aws-wafv2-get_ip_set waf-v1-cloudfront-ip-set.json
}

@test "cf-ip-block prints usage with no arguments" {
  # usage() sends only its first line to stderr; the option list itself is
  # plain `echo`, so it lands on stdout -- existing behaviour of the script.
  run --separate-stderr run_command bin/waf/v1/cf-ip-block
  assert_failure 1
  assert_stderr_contains "Usage: cf-ip-block"
  assert_output_contains "-b <ip_address>"
}

@test "cf-ip-block requires an infrastructure" {
  run --separate-stderr run_command bin/waf/v1/cf-ip-block -e staging -b 198.51.100.10/32
  assert_failure 1
  assert_stderr_contains "Usage: cf-ip-block"
}

@test "cf-ip-block requires an environment" {
  run --separate-stderr run_command bin/waf/v1/cf-ip-block -i example-infra -b 198.51.100.10/32
  assert_failure 1
  assert_stderr_contains "Usage: cf-ip-block"
}

@test "cf-ip-block refuses to mutate an IP address given without a subnet mask" {
  run --separate-stderr run_command bin/waf/v1/cf-ip-block -i example-infra -e staging -w mywaf -b 198.51.100.10
  assert_failure 1
  assert_stderr_contains "Please include a subnet mask"
  refute_stub_called_with "list-ip-sets"
  refute_stub_called_with "update-ip-set"
}

# FINDING: the subnet-mask check is `[[ $SOURCE_IP =~ /[0-9]{1,2}$ ]]`, which
# only accepts a 1- or 2-digit mask. A legitimate IPv6 CIDR in the /100-/128
# range (3 digits) is rejected by the very validation that exists to support
# -6/IPv6 blocking. This documents the current (broken) behaviour rather than
# the behaviour the usage text implies.
@test "cf-ip-block rejects a valid /128 IPv6 mask as if it had no subnet mask" {
  run --separate-stderr run_command bin/waf/v1/cf-ip-block -i example-infra -e staging -w mywaf -6 -b 2001:db8::1/128
  assert_failure 1
  assert_stderr_contains "Please include a subnet mask"
  refute_stub_called_with "update-ip-set"
}

@test "cf-ip-block adding an address unions it with the existing set instead of replacing it" {
  run run_command bin/waf/v1/cf-ip-block -i example-infra -e staging -w mywaf -b 198.51.100.10/32
  assert_success
  assert_stub_called_with 'update-ip-set --name example-infra-mywaf-waf-staging-blocked-ipv4 --region us-east-1 --scope CLOUDFRONT --id ipset-abc-123 --addresses ["192.0.2.0/24","203.0.113.5/32","198.51.100.10/32"] --lock-token lock-token-abc123'
}

@test "cf-ip-block -d removes only the targeted address and keeps the rest" {
  run run_command bin/waf/v1/cf-ip-block -i example-infra -e staging -w mywaf -b 203.0.113.5/32 -d
  assert_success
  assert_stub_called_with 'update-ip-set --name example-infra-mywaf-waf-staging-blocked-ipv4 --region us-east-1 --scope CLOUDFRONT --id ipset-abc-123 --addresses ["192.0.2.0/24"] --lock-token lock-token-abc123'
}

@test "cf-ip-block -d against an address not in the set is a harmless no-op" {
  run run_command bin/waf/v1/cf-ip-block -i example-infra -e staging -w mywaf -b 10.0.0.0/8 -d
  assert_success
  assert_stub_called_with 'update-ip-set --name example-infra-mywaf-waf-staging-blocked-ipv4 --region us-east-1 --scope CLOUDFRONT --id ipset-abc-123 --addresses ["192.0.2.0/24","203.0.113.5/32"] --lock-token lock-token-abc123'
}

@test "cf-ip-block with no -b lists the current set and makes no write" {
  run run_command bin/waf/v1/cf-ip-block -i example-infra -e staging -w mywaf
  assert_success
  assert_output_contains "192.0.2.0/24"
  refute_stub_called_with "update-ip-set"
}

# FINDING: -w (WAF name) is validated as required by every other waf/v1
# command, but cf-ip-block's own required-argument check only tests -i and -e.
# Omitting -w silently builds a malformed IP set name (a double dash where the
# WAF name should be) and still goes ahead with a real update-ip-set call
# rather than refusing.
@test "cf-ip-block does not require -w and still attempts a mutation without it" {
  run run_command bin/waf/v1/cf-ip-block -i example-infra -e staging -b 198.51.100.10/32
  assert_success
  assert_stub_called_with "list-ip-sets --scope CLOUDFRONT"
  assert_stub_called_with "--name example-infra--waf-staging-blocked-ipv4"
}
