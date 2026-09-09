#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  export AWS_DEFAULT_REGION=eu-west-2
}

@test "delete prints usage with no arguments" {
  run --separate-stderr run_command bin/certificate/v1/delete
  assert_failure 1
  assert_stderr_contains "Usage: delete"
  assert_output_contains "-c <certificate arn>"
}

@test "delete requires an infrastructure" {
  run --separate-stderr run_command bin/certificate/v1/delete -c "arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  assert_failure 1
  assert_stderr_contains "Infrastructure name is a required option"
}

@test "delete requires either a certificate ARN or a domain" {
  run --separate-stderr run_command bin/certificate/v1/delete -i example-infra
  assert_failure 1
  assert_stderr_contains "At least one Certificate ARN"
}

@test "delete -h shows usage" {
  run --separate-stderr run_command bin/certificate/v1/delete -h
  assert_failure 1
  assert_stderr_contains "Usage: delete"
}

@test "delete -c deletes exactly the ARN given, resolving eu-west-2 from AWS_DEFAULT_REGION" {
  run run_command bin/certificate/v1/delete -i example-infra -c "arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  assert_success
  assert_stub_called_with "delete-certificate --certificate-arn arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000 --region eu-west-2"
  assert_output_contains "Deleted: arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"
}

@test "delete -c resolves us-east-1 from the ARN itself, not AWS_DEFAULT_REGION" {
  run run_command bin/certificate/v1/delete -i example-infra -c "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000001"
  assert_success
  assert_stub_called_with "delete-certificate --certificate-arn arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000001 --region us-east-1"
}

@test "delete -c -d performs a dry run: prints the command but never calls delete-certificate" {
  run run_command bin/certificate/v1/delete -i example-infra -d -c "arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  assert_success
  assert_output_contains "aws acm delete-certificate --certificate-arn arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000 --region eu-west-2"
  refute_stub_called_with "delete-certificate"
}

@test "delete -D leaves ISSUED certificates alone" {
  stub_response_file aws-acm-list_certificates cdn-cert-list-lb.json
  stub_response_file aws-acm-list_certificates-region-us_east_1 cdn-cert-list-cf.json
  stub_response_file aws-acm-describe_certificate-certificate_arn-arn_aws_acm_eu_west_2_123456789012_certificate_00000000_0000_0000_0000_000000000000-region-eu_west_2 \
    cdn-cert-describe-example-lb.json
  stub_response_file aws-acm-describe_certificate-certificate_arn-arn_aws_acm_us_east_1_123456789012_certificate_00000000_0000_0000_0000_000000000001-region-us_east_1 \
    cdn-cert-describe-example-cf.json

  run run_command bin/certificate/v1/delete -i example-infra -D example.com
  assert_success
  refute_stub_called_with "delete-certificate"
}

# example.com has both an eu-west-2 (LB) and a us-east-1 (CloudFront) match,
# but other.example.com only has the eu-west-2 one. That asymmetry matters:
# see the FINDING test below.
@test "delete -D deletes exactly the non-ISSUED certificate for the given domain" {
  stub_response_file aws-acm-list_certificates cdn-cert-list-lb.json
  stub_response_file aws-acm-list_certificates-region-us_east_1 cdn-cert-list-cf.json
  stub_response_file aws-acm-describe_certificate-certificate_arn-arn_aws_acm_eu_west_2_123456789012_certificate_00000000_0000_0000_0000_000000000002-region-eu_west_2 \
    cdn-cert-describe-other-lb.json

  run run_command bin/certificate/v1/delete -i example-infra -D other.example.com
  assert_success
  assert_stub_called_with "delete-certificate --certificate-arn arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000002 --region eu-west-2"
  assert_output_contains "Deleted: arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000002"
}

# FINDING: when a -D domain matches in only one of the two regions, the other
# region's `jq -r ... | .CertificateArn` produces an empty string, but
# `echo "$EMPTY" | while read` still yields one iteration with cert="" rather
# than zero. That phantom empty ARN is appended to ALL_CERTIFICATES, so the
# script goes on to call describe-certificate with an empty --certificate-arn,
# treats the empty Status as "not ISSUED/PENDING", and calls delete-certificate
# with a completely empty --certificate-arn. Confirmed directly against the
# real jq/read behaviour (see investigation), not a stub artefact -- reproduced
# here with the same -D case as the test above.
@test "delete -D also fires a spurious delete-certificate call with an empty ARN when only one region matched" {
  stub_response_file aws-acm-list_certificates cdn-cert-list-lb.json
  stub_response_file aws-acm-list_certificates-region-us_east_1 cdn-cert-list-cf.json
  stub_response_file aws-acm-describe_certificate-certificate_arn-arn_aws_acm_eu_west_2_123456789012_certificate_00000000_0000_0000_0000_000000000002-region-eu_west_2 \
    cdn-cert-describe-other-lb.json

  run run_command bin/certificate/v1/delete -i example-infra -D other.example.com
  assert_success
  assert_stub_called_with "delete-certificate --certificate-arn  --region eu-west-2"
}
