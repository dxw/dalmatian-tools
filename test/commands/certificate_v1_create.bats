#!/usr/bin/env bats

load ../test_helper

# certificate/v1/create requests a cert in both eu-west-2 (for ALBs) and
# us-east-1 (for CloudFront), then polls describe-certificate until DNS
# validation records are available. The describe-certificate stub below
# always answers with real records so the poll loop exits on its first pass
# instead of sleeping.
setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  export AWS_DEFAULT_REGION=eu-west-2

  stub_response 'aws-acm-describe_certificate' <<'EOF'
{
  "Certificate": {
    "DomainValidationOptions": [
      {"ResourceRecord": {"Name": "_abc123.example.com.", "Value": "_xyz789.acm-validations.aws."}}
    ]
  }
}
EOF
}

@test "create prints usage with no arguments" {
  run --separate-stderr run_command bin/certificate/v1/create
  assert_failure 1
  assert_stderr_contains "Usage: create"
  assert_output_contains "-i <infrastructure>"
}

@test "create requires an infrastructure" {
  run --separate-stderr run_command bin/certificate/v1/create -d example.com
  assert_failure 1
  assert_stderr_contains "Usage: create"
}

@test "create -h shows usage" {
  run --separate-stderr run_command bin/certificate/v1/create -h
  assert_failure 1
  assert_stderr_contains "Usage: create"
}

# FINDING: unlike -i, the -d <domain> flag is never checked for emptiness, so
# an invocation missing it is not sent to usage() -- it falls straight through
# to `aws acm request-certificate --domain-name ""`.
@test "create does not validate that a domain was given, and proceeds with an empty domain name" {
  stub_response 'aws-acm-request_certificate' '{"CertificateArn": "arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"}'

  run --separate-stderr run_command bin/certificate/v1/create -i example-infra
  assert_success
  refute_output_line "Usage: create"
  assert_stub_called_with 'request-certificate --domain-name  --subject-alternative-names'
}

@test "create requests a cert in both eu-west-2 and us-east-1, defaulting the SAN list to the domain" {
  stub_response 'aws-acm-request_certificate-domain_name-example_com-subject_alternative_names-example_com-validation_method-DNS-region-eu_west_2' \
    '{"CertificateArn": "arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"}'
  stub_response 'aws-acm-request_certificate-domain_name-example_com-subject_alternative_names-example_com-validation_method-DNS-region-us_east_1' \
    '{"CertificateArn": "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000001"}'

  run run_command bin/certificate/v1/create -i example-infra -d example.com
  assert_success
  assert_stub_called_with "request-certificate --domain-name example.com --subject-alternative-names example.com --validation-method DNS --region eu-west-2"
  assert_stub_called_with "request-certificate --domain-name example.com --subject-alternative-names example.com --validation-method DNS --region us-east-1"
  assert_output_contains "Load balancer SSL cert is arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  assert_output_contains "CloudFront SSL cert is arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000001"
  assert_output_contains "_abc123.example.com. CNAME _xyz789.acm-validations.aws."
}

@test "create passes each quoted SAN through as a separate value on both requests" {
  stub_response 'aws-acm-request_certificate' '{"CertificateArn": "arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"}'

  run run_command bin/certificate/v1/create -i example-infra -d example.com -s "www.example.com other.example.com"
  assert_success
  assert_stub_called_with "request-certificate --domain-name example.com --subject-alternative-names www.example.com other.example.com --validation-method DNS --region eu-west-2"
}
