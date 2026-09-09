#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "rds set-root-password prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v1/set-root-password
  assert_failure 1
  assert_stderr_contains "Usage: dalmatian v1 set-root-password"
  assert_output_contains "-P <new_password>"
}

@test "rds set-root-password requires a new password and does not write anything without one" {
  run --separate-stderr run_command bin/rds/v1/set-root-password -i "example-infra" -r "example-rds" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: dalmatian v1 set-root-password"
  refute_stub_called_with "ssm put-parameter"
}

@test "rds set-root-password -h prints usage and does not write anything" {
  run --separate-stderr run_command bin/rds/v1/set-root-password -h
  assert_failure 1
  refute_stub_called_with "ssm put-parameter"
}

@test "rds set-root-password writes the new password under the identifier built from infra+rds+env" {
  run run_command bin/rds/v1/set-root-password -i "example-infra" -r "example-rds" -e "staging" -P "NewP4ssw0rd!"
  assert_success
  assert_stub_called_with "ssm put-parameter --name /example-infra/exampleinfraexamplerdsstaging-rds/password --value NewP4ssw0rd! --type SecureString --key-id alias/example-infra-example-rds-rds-staging-rds-values-ssm --overwrite"
}

@test "rds set-root-password prints the redeploy instructions with the right infra and environment" {
  run run_command bin/rds/v1/set-root-password -i "example-infra" -r "example-rds" -e "staging" -P "NewP4ssw0rd!"
  assert_success
  assert_output_contains "./scripts/bin/deploy -i example-infra -e staging -S hosted-zone,vpn-customer-gateway,ecs,ecs-services,elasticache-cluster,shared-loadbalancer,waf"
}

@test "rds set-root-password fails and prints no deploy instructions when the write fails" {
  stub_exit aws-ssm-put_parameter 1
  run --separate-stderr run_command bin/rds/v1/set-root-password -i "example-infra" -r "example-rds" -e "staging" -P "NewP4ssw0rd!"
  assert_failure
  refute_output_line "==> For this change to take effect, run the following from dalmatian core to deploy:"
}
