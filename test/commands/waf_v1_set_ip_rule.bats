#!/usr/bin/env bats

load ../test_helper

# set-ip-rule creates a brand-new, dedicated IP set for a single address, then
# appends a new Custom<Action><ip-label> rule referencing it onto an existing
# REGIONAL Web ACL's rule list.
setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-wafv2-create_ip_set waf-v1-create-ip-set.json
  stub_response_file aws-wafv2-list_web_acls waf-v1-list-web-acls.json
}

@test "set-ip-rule prints usage with no arguments" {
  run --separate-stderr run_command bin/waf/v1/set-ip-rule
  assert_failure 1
  assert_stderr_contains "Usage: set-ip-rule"
  assert_output_contains "-b <ip_address>"
}

@test "set-ip-rule requires an infrastructure" {
  run --separate-stderr run_command bin/waf/v1/set-ip-rule -e staging -w mywaf -b 198.51.100.10/32
  assert_failure 1
  assert_stderr_contains "Usage: set-ip-rule"
}

@test "set-ip-rule requires a WAF name" {
  run --separate-stderr run_command bin/waf/v1/set-ip-rule -i example-infra -e staging -b 198.51.100.10/32
  assert_failure 1
  assert_stderr_contains "Usage: set-ip-rule"
}

@test "set-ip-rule requires an environment" {
  run --separate-stderr run_command bin/waf/v1/set-ip-rule -i example-infra -w mywaf -b 198.51.100.10/32
  assert_failure 1
  assert_stderr_contains "Usage: set-ip-rule"
}

@test "set-ip-rule refuses to mutate an IP address given without a subnet mask" {
  stub_response_file aws-wafv2-get_web_acl waf-v1-web-acl-one-rule.json

  run --separate-stderr run_command bin/waf/v1/set-ip-rule -i example-infra -e staging -w mywaf -b 198.51.100.10
  assert_failure 1
  assert_stderr_contains "Please include a subnet mask"
  refute_stub_called_with "create-ip-set"
  refute_stub_called_with "update-web-acl"
}

# FINDING: -b (the address itself) is not in the required-argument check, and
# the subnet-mask validation only runs `if [[ -n "$SOURCE_IP" ]]`, so it is
# skipped entirely when -b is omitted. The script goes ahead and creates an IP
# set named "DalmatianBlock" with an EMPTY --addresses value, and wires a new
# ACL rule to it -- a silent "block nothing, successfully" rule rather than a
# refusal.
@test "set-ip-rule with no -b still creates an IP set and rule with an empty address" {
  stub_response_file aws-wafv2-get_web_acl waf-v1-web-acl-one-rule.json

  run run_command bin/waf/v1/set-ip-rule -i example-infra -e staging -w mywaf
  assert_success
  # trailing space after --addresses: the value is the empty string, not a
  # real CIDR
  # argv-exact: the old substring form ended at "--addresses ", which is a
  # prefix of any populated address and so passed either way
  assert_call_args aws wafv2 create-ip-set --scope REGIONAL --name DalmatianBlock \
    --ip-address-version IPV4 --addresses ""
}

@test "set-ip-rule appends the new rule and keeps the existing rule, at the next priority" {
  stub_response_file aws-wafv2-get_web_acl waf-v1-web-acl-one-rule.json

  run run_command bin/waf/v1/set-ip-rule -i example-infra -e staging -w mywaf -b 198.51.100.10/32 -a Block
  assert_success
  assert_stub_called_with 'update-web-acl --scope REGIONAL --name example-infra-mywaf-waf-staging-mywaf-acl --id acl-id-123 --default-action {"Allow":{}} --visibility-config {"SampledRequestsEnabled":true,"CloudWatchMetricsEnabled":true,"MetricName":"example-metric"} --lock-token acl-lock-1 --rules [{"Name":"KeepThisRule","Priority":0},{"Name":"CustomDalmatianBlock198-51-100-10-32","Priority":2,"Statement":{"IPSetReferenceStatement":{"ARN":"arn:aws:wafv2:eu-west-2:123456789012:regional/ipset/DalmatianBlock198-51-100-10-32/new-ipset-id"'
  assert_stub_called_with '"Action":{"Block":{}}'
}

@test "set-ip-rule titlecases the action, e.g. CAPTCHA becomes Captcha" {
  stub_response_file aws-wafv2-get_web_acl waf-v1-web-acl-one-rule.json

  run run_command bin/waf/v1/set-ip-rule -i example-infra -e staging -w mywaf -b 198.51.100.10/32 -a CAPTCHA
  assert_success
  assert_output_contains "Action to be taken: Captcha"
  assert_stub_called_with "create-ip-set --scope REGIONAL --name DalmatianCaptcha198-51-100-10-32"
  assert_stub_called_with '"Action":{"Captcha":{}}'
}

@test "set-ip-rule defaults the action to Block when -a is omitted" {
  stub_response_file aws-wafv2-get_web_acl waf-v1-web-acl-one-rule.json

  run run_command bin/waf/v1/set-ip-rule -i example-infra -e staging -w mywaf -b 198.51.100.10/32
  assert_success
  assert_output_contains "Action to be taken: Block"
}

@test "set-ip-rule gives priority 1 to the first rule on an ACL with none yet" {
  stub_response_file aws-wafv2-get_web_acl waf-v1-web-acl-empty-rules.json

  run run_command bin/waf/v1/set-ip-rule -i example-infra -e staging -w mywaf -b 198.51.100.10/32
  assert_success
  assert_output_contains "New rule will be given Priority 1"
  assert_stub_called_with '"Priority":1'
}
