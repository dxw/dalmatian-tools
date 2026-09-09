#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "aurora set-root-password prints usage with no arguments" {
  run --separate-stderr run_command bin/aurora/v1/set-root-password
  assert_failure 1
  assert_stderr_contains "Usage: dalmatian v1 set-root-password"
  assert_output_contains "-P <new_password>"
}

@test "aurora set-root-password requires a new password and does not write anything without one" {
  run --separate-stderr run_command bin/aurora/v1/set-root-password -i "example-infra" -r "example-rds" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: dalmatian v1 set-root-password"
  refute_stub_called_with "ssm put-parameter"
}

@test "aurora set-root-password -h prints usage and does not write anything" {
  run --separate-stderr run_command bin/aurora/v1/set-root-password -h
  assert_failure 1
  refute_stub_called_with "ssm put-parameter"
}

# Diverges from the rds twin in the KMS alias, not just a word swap: rds uses
# "alias/<infra>-<rds_name>-<env>-rds-values-ssm" (one "-rds-" segment), but
# aurora inserts "-aurora-" TWICE -- once after RDS_NAME and again before
# "-values-ssm" -- giving
# "alias/<infra>-<rds_name>-aurora-<env>-aurora-values-ssm". The SSM parameter
# path itself follows the expected "-aurora" suffix pattern. Verified directly
# against both scripts.
@test "aurora set-root-password writes the new password under the identifier built from infra+rds+env" {
  run run_command bin/aurora/v1/set-root-password -i "example-infra" -r "example-rds" -e "staging" -P "NewP4ssw0rd!"
  assert_success
  assert_stub_called_with "ssm put-parameter --name /example-infra/exampleinfraexamplerdsstaging-aurora/password --value NewP4ssw0rd! --type SecureString --key-id alias/example-infra-example-rds-aurora-staging-aurora-values-ssm --overwrite"
}

# Diverges from the rds twin: aurora's redeploy instructions list an extra
# leading "rds," service before the rest of the (otherwise identical)
# service list. rds's own list has no such entry. Verified directly against
# both scripts.
@test "aurora set-root-password prints the redeploy instructions with the right infra and environment" {
  run run_command bin/aurora/v1/set-root-password -i "example-infra" -r "example-rds" -e "staging" -P "NewP4ssw0rd!"
  assert_success
  assert_output_contains "./scripts/bin/deploy -i example-infra -e staging -S rds,hosted-zone,vpn-customer-gateway,ecs,ecs-services,elasticache-cluster,shared-loadbalancer,waf"
}

@test "aurora set-root-password fails and prints no deploy instructions when the write fails" {
  stub_exit aws-ssm-put_parameter 1
  run --separate-stderr run_command bin/aurora/v1/set-root-password -i "example-infra" -r "example-rds" -e "staging" -P "NewP4ssw0rd!"
  assert_failure
  refute_output_line "==> For this change to take effect, run the following from dalmatian core to deploy:"
}
