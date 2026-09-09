#!/usr/bin/env bats

load ../test_helper

# delete-ip-rule is the counterpart to set-ip-rule: it removes the
# Custom<Action><ip-label> rule from a REGIONAL Web ACL's rule list, then
# deletes the dedicated IP set that backed it.
setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-wafv2-list_web_acls waf-v1-list-web-acls.json
}

@test "delete-ip-rule prints usage with no arguments" {
  run --separate-stderr run_command bin/waf/v1/delete-ip-rule
  assert_failure 1
  assert_stderr_contains "Usage: delete-ip-rule"
  assert_output_contains "-u <ip_address>"
}

@test "delete-ip-rule requires an infrastructure" {
  run --separate-stderr run_command bin/waf/v1/delete-ip-rule -e staging -w mywaf -u 198.51.100.10/32
  assert_failure 1
  assert_stderr_contains "Usage: delete-ip-rule"
}

@test "delete-ip-rule requires a WAF name" {
  run --separate-stderr run_command bin/waf/v1/delete-ip-rule -i example-infra -e staging -u 198.51.100.10/32
  assert_failure 1
  assert_stderr_contains "Usage: delete-ip-rule"
}

@test "delete-ip-rule refuses to mutate an IP address given without a subnet mask" {
  stub_response_file aws-wafv2-get_web_acl waf-v1-web-acl-with-target-rule.json

  run --separate-stderr run_command bin/waf/v1/delete-ip-rule -i example-infra -e staging -w mywaf -u 198.51.100.10
  assert_failure 1
  assert_stderr_contains "Please include a subnet mask"
  refute_stub_called_with "update-web-acl"
  refute_stub_called_with "delete-ip-set"
}

@test "delete-ip-rule removes only the targeted rule and keeps the other rules" {
  stub_response_file aws-wafv2-get_web_acl waf-v1-web-acl-with-target-rule.json
  stub_response_file aws-wafv2-list_ip_sets waf-v1-list-ip-sets-regional.json

  run run_command bin/waf/v1/delete-ip-rule -i example-infra -e staging -w mywaf -u 198.51.100.10/32 -a Block
  assert_success
  assert_stub_called_with '--rules [{"Name":"KeepThisRule","Priority":0}]'
  refute_stub_called_with "CustomDalmatianBlock198-51-100-10-32"
}

@test "delete-ip-rule deletes the matching IP set, not the decoy, using its own lock token" {
  stub_response_file aws-wafv2-get_web_acl waf-v1-web-acl-with-target-rule.json
  stub_response_file aws-wafv2-list_ip_sets waf-v1-list-ip-sets-regional.json

  run run_command bin/waf/v1/delete-ip-rule -i example-infra -e staging -w mywaf -u 198.51.100.10/32 -a Block
  assert_success
  assert_stub_called_with "delete-ip-set --scope REGIONAL --name DalmatianBlock198-51-100-10-32 --id target-ipset-id --lock-token target-ipset-lock"
  refute_stub_called_with "--id decoy-ipset-id"
}

@test "delete-ip-rule targets the Captcha-named rule and IP set for a Captcha action" {
  stub_response_file aws-wafv2-get_web_acl waf-v1-web-acl-with-captcha-target-rule.json
  stub_response 'aws-wafv2-list_ip_sets' <<'EOF'
{"IPSets":[{"Name":"DalmatianCaptcha198-51-100-10-32","Id":"captcha-ipset-id","LockToken":"captcha-ipset-lock"}]}
EOF

  run run_command bin/waf/v1/delete-ip-rule -i example-infra -e staging -w mywaf -u 198.51.100.10/32 -a captcha
  assert_success
  assert_stub_called_with '--rules [{"Name":"KeepThisRule","Priority":0}]'
  assert_stub_called_with "delete-ip-set --scope REGIONAL --name DalmatianCaptcha198-51-100-10-32 --id captcha-ipset-id --lock-token captcha-ipset-lock"
}

# FINDING: neither -u (the address) nor the rule/IP-set actually existing is
# validated before mutating. A rule name that doesn't match any existing rule
# is a silent no-op on the ACL (the rules list is just written back
# unchanged) rather than a refusal, and the delete-ip-set call still goes
# ahead even when the IP set lookup found nothing -- with an EMPTY --id and
# --lock-token. In this test suite that only proves harmless, because the
# stub for an unmatched call succeeds silently; against the real AWS API an
# empty --id would presumably be rejected, but the script itself has no
# pre-flight check and relies entirely on that.
@test "delete-ip-rule with no matching rule or IP set still calls delete-ip-set with an empty id" {
  stub_response_file aws-wafv2-get_web_acl waf-v1-web-acl-one-rule.json
  stub_response 'aws-wafv2-list_ip_sets' <<'EOF'
{"IPSets":[{"Name":"SomeOtherIPSet","Id":"unrelated-id","LockToken":"unrelated-lock"}]}
EOF

  run run_command bin/waf/v1/delete-ip-rule -i example-infra -e staging -w mywaf -u 198.51.100.10/32 -a Block
  assert_success
  assert_stub_called_with '--rules [{"Name":"KeepThisRule","Priority":0}]'
  assert_stub_called_with "delete-ip-set --scope REGIONAL --name DalmatianBlock198-51-100-10-32 --id  --lock-token"
}

@test "delete-ip-rule round-trips the ACL's own lock token on the update call" {
  stub_response_file aws-wafv2-get_web_acl waf-v1-web-acl-with-target-rule.json
  stub_response_file aws-wafv2-list_ip_sets waf-v1-list-ip-sets-regional.json

  run run_command bin/waf/v1/delete-ip-rule -i example-infra -e staging -w mywaf -u 198.51.100.10/32 -a Block
  assert_success
  assert_stub_called_with "update-web-acl --scope REGIONAL --name example-infra-mywaf-waf-staging-mywaf-acl --id acl-id-123"
  assert_stub_called_with "--lock-token acl-lock-1"
}
