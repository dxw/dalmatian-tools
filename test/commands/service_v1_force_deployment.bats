#!/usr/bin/env bats

load ../test_helper

# The -w path polls with a real `sleep 10` between iterations (see the loop
# in bin/service/v1/force-deployment). A fake `sleep` is put ahead of the
# real one on PATH -- via $SANDBOX/bin, which use_stubs already puts first --
# so the loop's termination logic (it stops once the stubbed
# describe-services response reports rolloutState "COMPLETED") can be
# exercised without a real 10-second wait per test.
fake_instant_sleep() {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/bin/sleep"
  chmod +x "$SANDBOX/bin/sleep"
}

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "force-deployment prints usage with no arguments" {
  run --separate-stderr run_command bin/service/v1/force-deployment
  assert_failure 1
  assert_stderr_contains "Usage: force-deployment"
  assert_output_contains "-i <infrastructure>"
}

@test "force-deployment -h shows usage" {
  run --separate-stderr run_command bin/service/v1/force-deployment -h
  assert_failure 1
  assert_stderr_contains "Usage: force-deployment"
}

@test "force-deployment requires infrastructure, service and environment" {
  run --separate-stderr run_command bin/service/v1/force-deployment -i example-infra
  assert_failure 1
  assert_stderr_contains "Usage: force-deployment"
  refute_stub_called_with "update-service"
}

@test "force-deployment forces a new deployment on the service/task-definition/cluster built from -i/-s/-e" {
  QUIET_MODE=0 run run_command bin/service/v1/force-deployment -i example-infra -s example-service -e staging
  assert_success
  assert_stub_called_with "ecs update-service --service example-service --task-definition staging-example-infra-example-service --cluster example-infra-staging --force-new-deployment"
  assert_output_contains "Deployment started."
  refute_stub_called_with "describe-services"
}

@test "force-deployment propagates a failing update-service call" {
  stub_exit aws-ecs-update_service 1

  run --separate-stderr run_command bin/service/v1/force-deployment -i example-infra -s example-service -e staging
  assert_failure
}

@test "force-deployment -w polls describe-services until rolloutState is COMPLETED" {
  fake_instant_sleep
  stub_response_file aws-ecs-update_service service-deploy-ecs-update-service.json
  stub_response_file aws-ecs-describe_services service-deploy-ecs-describe-services.json

  QUIET_MODE=0 run run_command bin/service/v1/force-deployment -i example-infra -s example-service -e staging -w
  assert_success
  assert_stub_called_with "ecs describe-services --cluster example-infra-staging --services example-service"
  assert_output_contains "New event message"
  assert_output_contains "COMPLETED - Desired: 2, Pending: 0, Running: 2"
  assert_output_contains "Deployment complete."
}
