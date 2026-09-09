#!/usr/bin/env bats

load ../test_helper

# list-blocked-requests looks up a Web ACL, then polls
# `aws wafv2 get-sampled-requests` once per rule on that ACL and reports only
# the BLOCK-actioned samples, newest first. It is read-only -- no IP set or
# ACL rule is ever mutated -- so these tests focus on output correctness
# rather than write-call assertions.
setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-wafv2-list_web_acls waf-v1-list-web-acls.json
}

@test "list-blocked-requests prints usage with no arguments" {
  run --separate-stderr run_command bin/waf/v1/list-blocked-requests
  assert_failure 1
  assert_stderr_contains "Usage: list-blocked-requests"
  assert_output_contains "-t <time_frame>"
}

@test "list-blocked-requests requires an infrastructure" {
  run --separate-stderr run_command bin/waf/v1/list-blocked-requests -e staging -w mywaf
  assert_failure 1
  assert_stderr_contains "Usage: list-blocked-requests"
}

@test "list-blocked-requests requires a WAF name" {
  run --separate-stderr run_command bin/waf/v1/list-blocked-requests -i example-infra -e staging
  assert_failure 1
  assert_stderr_contains "Usage: list-blocked-requests"
}

@test "list-blocked-requests rejects -H without a matching -v" {
  run --separate-stderr run_command bin/waf/v1/list-blocked-requests -i example-infra -e staging -w mywaf -H Host
  assert_failure 1
  assert_stderr_contains "Usage: list-blocked-requests"
}

@test "list-blocked-requests rejects -v without a matching -H" {
  run --separate-stderr run_command bin/waf/v1/list-blocked-requests -i example-infra -e staging -w mywaf -v example.com
  assert_failure 1
  assert_stderr_contains "Usage: list-blocked-requests"
}

@test "list-blocked-requests shows only BLOCK actions, newest first" {
  stub_response_file aws-wafv2-get_web_acl waf-v1-web-acl-one-rule.json
  stub_response_file aws-wafv2-get_sampled_requests waf-v1-sampled-requests.json

  run run_command bin/waf/v1/list-blocked-requests -i example-infra -e staging -w mywaf
  assert_success
  assert_line 0 "2026-08-27T09:05:00.000Z - rule-a - POST - /blocked-path-two"
  assert_line 1 "2026-08-27T09:00:00.000Z - rule-a - GET - /blocked-path-one"
  refute_output_line "2026-08-27T09:10:00.000Z - rule-a - GET - /allowed-path"
}

@test "list-blocked-requests -H/-v narrows to a matching header" {
  stub_response_file aws-wafv2-get_web_acl waf-v1-web-acl-one-rule.json
  stub_response_file aws-wafv2-get_sampled_requests waf-v1-sampled-requests.json

  run run_command bin/waf/v1/list-blocked-requests -i example-infra -e staging -w mywaf -H Host -v example.com
  assert_success
  assert_output "2026-08-27T09:00:00.000Z - rule-a - GET - /blocked-path-one"
}

@test "list-blocked-requests -V prints the full sampled request JSON" {
  stub_response_file aws-wafv2-get_web_acl waf-v1-web-acl-one-rule.json
  stub_response_file aws-wafv2-get_sampled_requests waf-v1-sampled-requests.json

  run run_command bin/waf/v1/list-blocked-requests -i example-infra -e staging -w mywaf -V
  assert_success
  assert_output_contains '"Action": "BLOCK"'
  assert_output_contains '"URI": "/blocked-path-two"'
  refute_output_line '    "Action": "ALLOW",'
}

@test "list-blocked-requests reports nothing for a Web ACL with no rules, rather than erroring" {
  stub_response_file aws-wafv2-get_web_acl waf-v1-web-acl-empty-rules.json

  run run_command bin/waf/v1/list-blocked-requests -i example-infra -e staging -w mywaf
  assert_success
  assert_output ""
}

# FINDING: an infrastructure/environment/waf-name combination that doesn't
# match any real Web ACL is not treated as an error. ACL_ID ends up empty,
# the subsequent get-web-acl call (unstubbed here, so it answers empty) yields
# no rules to iterate over, and the script exits 0 having printed nothing --
# the same output as "no blocked requests right now". An operator who
# mistypes -w has no way to tell those two cases apart from this command's
# output alone.
@test "list-blocked-requests exits successfully with no output when the WAF name doesn't match any ACL" {
  stub_response_file aws-wafv2-list_web_acls waf-v1-list-web-acls-no-match.json

  run run_command bin/waf/v1/list-blocked-requests -i example-infra -e staging -w mywaf
  assert_success
  assert_output ""
}

@test "list-blocked-requests passes a custom time frame through to the time window" {
  stub_response_file aws-wafv2-get_web_acl waf-v1-web-acl-one-rule.json
  stub_response_file aws-wafv2-get_sampled_requests waf-v1-sampled-requests.json

  run run_command bin/waf/v1/list-blocked-requests -i example-infra -e staging -w mywaf -t 45
  assert_success
  assert_stub_called_with "get-sampled-requests --web-acl-arn"
  assert_stub_called_with "--rule-metric-name example-metric-KeepThisRule"
}
