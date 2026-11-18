#!/usr/bin/env bats

load ../test_helper

# list-rate-limited-ips makes no direct `aws` calls: everything goes through
# "$APP_ROOT/bin/dalmatian" aws run-command, so stub_cli fakes the CLI. The
# infrastructure Terraform names its CLOUDFRONT-scoped Web ACLs
# "<project>-<infra>-<env>-<waf key>", reachable only through us-east-1.
MANAGED_KEYS='dalmatian-aws-run_command-i-example_infra-e-staging-wafv2-get_rate_based_statement_managed_keys'

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-aws-run_command-i-example_infra-e-staging-wafv2-list_web_acls waf-v2-list-web-acls.json
  stub_response_file dalmatian-aws-run_command-i-example_infra-e-staging-wafv2-get_web_acl waf-web-acl-rate-rules.json
  stub_response_file "$MANAGED_KEYS" waf-managed-keys-empty.json
}

@test "list-rate-limited-ips prints usage with no arguments" {
  run --separate-stderr run_command bin/waf/v2/list-rate-limited-ips
  assert_failure 1
  assert_stderr_contains "Usage: list-rate-limited-ips"
  assert_output_contains "-w <waf_name>"
}

@test "list-rate-limited-ips requires an environment" {
  run --separate-stderr run_command bin/waf/v2/list-rate-limited-ips -i example-infra
  assert_failure 1
  assert_stderr_contains "Usage: list-rate-limited-ips"
}

@test "list-rate-limited-ips requires an infrastructure" {
  run --separate-stderr run_command bin/waf/v2/list-rate-limited-ips -e staging
  assert_failure 1
  assert_stderr_contains "Usage: list-rate-limited-ips"
}

@test "list-rate-limited-ips queries CLOUDFRONT scope in us-east-1" {
  run run_command bin/waf/v2/list-rate-limited-ips -i example-infra -e staging
  assert_success
  assert_stub_called_with "aws run-command -i example-infra -e staging wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1"
}

@test "list-rate-limited-ips checks every WAF on the environment, not other infrastructures" {
  run run_command bin/waf/v2/list-rate-limited-ips -i example-infra -e staging
  assert_success
  assert_stub_called_with "get-web-acl --name example-project-example-infra-staging-main --id acl-main"
  assert_stub_called_with "get-web-acl --name example-project-example-infra-staging-admin --id acl-admin"
  refute_stub_called_with "acl-decoy"
}

@test "list-rate-limited-ips -w narrows to one WAF" {
  run run_command bin/waf/v2/list-rate-limited-ips -i example-infra -e staging -w admin
  assert_success
  assert_stub_called_with "get-web-acl --name example-project-example-infra-staging-admin --id acl-admin"
  refute_stub_called_with "acl-main"
}

@test "list-rate-limited-ips lists IPv4 and IPv6 addresses per WAF and IP-keyed rate rule" {
  stub_response_file "$MANAGED_KEYS-web_acl_name-example_project_example_infra_staging_main-web_acl_id-acl_main-rule_name-RateLogin" \
    waf-managed-keys-ipv4-and-ipv6.json

  run run_command bin/waf/v2/list-rate-limited-ips -i example-infra -e staging
  assert_success
  assert_output "main RateLogin 192.0.2.10/32
main RateLogin 198.51.100.7/32
main RateLogin 2001:db8::1/128"
  assert_stub_called_with "--rule-name RateLimit"
  refute_stub_called_with "--rule-name RateByHeader"
  refute_stub_called_with "--rule-name AWSManagedRulesCommonRuleSet"
}

@test "list-rate-limited-ips honours terraform_project_name over project_name" {
  printf '{"project_name": "ignored", "terraform_project_name": "example-project"}\n' > "$CONFIG_SETUP_JSON_FILE"

  run run_command bin/waf/v2/list-rate-limited-ips -i example-infra -e staging -w main
  assert_success
  assert_stub_called_with "get-web-acl --name example-project-example-infra-staging-main --id acl-main"
}

@test "list-rate-limited-ips reports when nothing is rate limited" {
  QUIET_MODE=0 run run_command bin/waf/v2/list-rate-limited-ips -i example-infra -e staging
  assert_success
  assert_output_contains "No IP addresses are currently rate limited"
}

@test "list-rate-limited-ips reports a WAF with no rate-based rules" {
  stub_response_file dalmatian-aws-run_command-i-example_infra-e-staging-wafv2-get_web_acl waf-web-acl-no-rate-rules.json

  QUIET_MODE=0 run run_command bin/waf/v2/list-rate-limited-ips -i example-infra -e staging -w main
  assert_success
  assert_output_contains "example-project-example-infra-staging-main has no IP rate-based rules"
  refute_stub_called_with "get-rate-based-statement-managed-keys"
}

@test "list-rate-limited-ips fails when the named WAF does not exist" {
  run --separate-stderr run_command bin/waf/v2/list-rate-limited-ips -i example-infra -e staging -w missing
  assert_failure 1
  assert_stderr_contains "Could not find Web ACL 'example-project-example-infra-staging-missing'"
  refute_stub_called_with "get-web-acl"
}

@test "list-rate-limited-ips fails when the environment has no WAFs" {
  stub_response_file dalmatian-aws-run_command-i-example_infra-e-staging-wafv2-list_web_acls waf-v1-cf-list-web-acls.json

  run --separate-stderr run_command bin/waf/v2/list-rate-limited-ips -i example-infra -e staging
  assert_failure 1
  assert_stderr_contains "Could not find any Web ACLs named 'example-project-example-infra-staging-*'"
}
