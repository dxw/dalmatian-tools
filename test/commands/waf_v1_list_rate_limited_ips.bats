#!/usr/bin/env bats

load ../test_helper

# list-rate-limited-ips finds the CloudFront-scoped Web ACL
# "<infra>-<env>-cf-web-acl" (the only v1 ACL carrying a rate-based rule) and
# asks WAF which addresses each IP-keyed rate-based rule is currently limiting.
# CLOUDFRONT-scoped ACLs are only reachable through us-east-1.
MANAGED_KEYS='aws-wafv2-get_rate_based_statement_managed_keys-scope-CLOUDFRONT-region-us_east_1-web_acl_name-example_infra_staging_cf_web_acl-web_acl_id-cf_acl_1-rule_name'

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-wafv2-list_web_acls waf-v1-cf-list-web-acls.json
  stub_response_file aws-wafv2-get_web_acl waf-web-acl-rate-rules.json
  stub_response_file aws-wafv2-get_rate_based_statement_managed_keys waf-managed-keys-empty.json
}

@test "list-rate-limited-ips prints usage with no arguments" {
  run --separate-stderr run_command bin/waf/v1/list-rate-limited-ips
  assert_failure 1
  assert_stderr_contains "Usage: list-rate-limited-ips"
  assert_output_contains "-e <environment>"
}

@test "list-rate-limited-ips requires an environment" {
  run --separate-stderr run_command bin/waf/v1/list-rate-limited-ips -i example-infra
  assert_failure 1
  assert_stderr_contains "Usage: list-rate-limited-ips"
}

@test "list-rate-limited-ips requires an infrastructure" {
  run --separate-stderr run_command bin/waf/v1/list-rate-limited-ips -e staging
  assert_failure 1
  assert_stderr_contains "Usage: list-rate-limited-ips"
}

@test "list-rate-limited-ips queries the CloudFront ACL in us-east-1" {
  run run_command bin/waf/v1/list-rate-limited-ips -i example-infra -e staging
  assert_success
  assert_stub_called_with "aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1"
  assert_stub_called_with "aws wafv2 get-web-acl --scope CLOUDFRONT --region us-east-1 --name example-infra-staging-cf-web-acl --id cf-acl-1"
  refute_stub_called_with "cf-acl-decoy"
}

@test "list-rate-limited-ips lists IPv4 and IPv6 addresses per IP-keyed rate rule" {
  stub_response_file "$MANAGED_KEYS-RateLimit" waf-managed-keys-ipv4-and-ipv6.json

  run run_command bin/waf/v1/list-rate-limited-ips -i example-infra -e staging
  assert_success
  assert_output "RateLimit 192.0.2.10/32
RateLimit 198.51.100.7/32
RateLimit 2001:db8::1/128"
  assert_stub_called_with "--rule-name RateLogin"
  refute_stub_called_with "--rule-name RateByHeader"
  refute_stub_called_with "--rule-name AWSManagedRulesCommonRuleSet"
}

@test "list-rate-limited-ips reports when nothing is rate limited" {
  QUIET_MODE=0 run run_command bin/waf/v1/list-rate-limited-ips -i example-infra -e staging
  assert_success
  assert_output_contains "No IP addresses are currently rate limited"
}

@test "list-rate-limited-ips reports an ACL with no rate-based rules" {
  stub_response_file aws-wafv2-get_web_acl waf-web-acl-no-rate-rules.json

  QUIET_MODE=0 run run_command bin/waf/v1/list-rate-limited-ips -i example-infra -e staging
  assert_success
  assert_output_contains "has no IP rate-based rules"
  refute_stub_called_with "get-rate-based-statement-managed-keys"
}

@test "list-rate-limited-ips fails when the CloudFront ACL does not exist" {
  run --separate-stderr run_command bin/waf/v1/list-rate-limited-ips -i missing-infra -e staging
  assert_failure 1
  assert_stderr_contains "Could not find Web ACL 'missing-infra-staging-cf-web-acl'"
  refute_stub_called_with "get-web-acl"
}
