#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  export AWS_DEFAULT_REGION=eu-west-2

  stub_response_file aws-acm-list_certificates cdn-cert-list-lb.json
  stub_response_file aws-acm-list_certificates-region-us_east_1 cdn-cert-list-cf.json
  stub_response_file aws-acm-describe_certificate-certificate_arn-arn_aws_acm_eu_west_2_123456789012_certificate_00000000_0000_0000_0000_000000000000-region-eu_west_2 \
    cdn-cert-describe-example-lb.json
  stub_response_file aws-acm-describe_certificate-certificate_arn-arn_aws_acm_us_east_1_123456789012_certificate_00000000_0000_0000_0000_000000000001-region-us_east_1 \
    cdn-cert-describe-example-cf.json
  stub_response_file aws-acm-describe_certificate-certificate_arn-arn_aws_acm_eu_west_2_123456789012_certificate_00000000_0000_0000_0000_000000000002-region-eu_west_2 \
    cdn-cert-describe-other-lb.json
}

@test "list prints usage with no arguments" {
  run --separate-stderr run_command bin/certificate/v1/list
  assert_failure 1
  assert_stderr_contains "Usage: list"
  assert_output_contains "-i <infrastructure>"
}

@test "list requires an infrastructure" {
  run --separate-stderr run_command bin/certificate/v1/list -d example.com
  assert_failure 1
  assert_stderr_contains "Usage: list"
}

@test "list -h shows usage" {
  run --separate-stderr run_command bin/certificate/v1/list -h
  assert_failure 1
  assert_stderr_contains "Usage: list"
}

# FINDING: getopts registers -s as a valid option (taking an argument, per the
# "i:d:s:Dh" optstring) but the case statement has no `s)` branch for it, so it
# falls into the `*)` catch-all and always shows usage -- even though -s looks
# like a legitimate, silently-accepted flag from the getopts string alone.
@test "list -s is accepted by getopts but always falls through to usage" {
  run --separate-stderr run_command bin/certificate/v1/list -i example-infra -s ignored
  assert_failure 1
  assert_stderr_contains "Usage: list"
}

@test "list lists every LB and CloudFront certificate when no domain filter is given" {
  run run_command bin/certificate/v1/list -i example-infra
  assert_success
  assert_output_contains "arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000 example.com ISSUED"
  assert_output_contains "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000001 example.com ISSUED"
  assert_output_contains "arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000002 other.example.com EXPIRED"
}

@test "list -d filters to only the matching domain's certificates" {
  run run_command bin/certificate/v1/list -i example-infra -d example.com
  assert_success
  assert_output_contains "arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000 example.com ISSUED"
  assert_output_contains "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000001 example.com ISSUED"
  refute_output_line "arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000002 other.example.com EXPIRED"
}

@test "list -D prints the real DNS validation record for a certificate that has one" {
  run run_command bin/certificate/v1/list -i example-infra -D
  assert_success
  assert_output_contains "_abc123.example.com. CNAME _xyz789.acm-validations.aws."
}

@test "list -D reports validation records unavailable for a certificate with a null ResourceRecord" {
  run run_command bin/certificate/v1/list -i example-infra -D
  assert_success
  assert_output_contains "Validation records unavailable"
}
