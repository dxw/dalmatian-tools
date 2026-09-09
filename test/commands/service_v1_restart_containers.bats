#!/usr/bin/env bats

load ../test_helper

# restart-containers has no -w flag: it always polls `aws ecs
# describe-services` in a `while [ "$STATUS" != "COMPLETED" ]` loop with a
# real `sleep 10` between iterations, so every successful run goes through at
# least one such wait. A fake instant `sleep` is put ahead of the real one on
# PATH (via $SANDBOX/bin, which use_stubs already puts first) so the loop's
# termination logic can be exercised without a real 10-second wait per test.
fake_instant_sleep() {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/bin/sleep"
  chmod +x "$SANDBOX/bin/sleep"
}

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "restart-containers prints usage with no arguments" {
  run --separate-stderr run_command bin/service/v1/restart-containers
  assert_failure 1
  assert_stderr_contains "Usage: restart-containers"
  assert_output_contains "-i <infrastructure>"
}

@test "restart-containers -h shows usage" {
  run --separate-stderr run_command bin/service/v1/restart-containers -h
  assert_failure 1
  assert_stderr_contains "Usage: restart-containers"
}

@test "restart-containers requires infrastructure, service and environment" {
  run --separate-stderr run_command bin/service/v1/restart-containers -i example-infra
  assert_failure 1
  assert_stderr_contains "Usage: restart-containers"
  refute_stub_called_with "update-service"
}

@test "restart-containers forces a new deployment on the service/task-definition/cluster built from -i/-s/-e" {
  fake_instant_sleep
  stub_response_file aws-ecs-update_service service-deploy-ecs-update-service.json
  stub_response_file aws-ecs-describe_services service-deploy-ecs-describe-services.json

  run run_command bin/service/v1/restart-containers -i example-infra -s example-service -e staging
  assert_success
  assert_stub_called_with "ecs update-service --service example-service --task-definition staging-example-infra-example-service --cluster example-infra-staging --force-new-deployment"
  assert_stub_called_with "ecs describe-services --cluster example-infra-staging --services example-service"
}

@test "restart-containers polls until rolloutState is COMPLETED and prints the rollout counts" {
  fake_instant_sleep
  stub_response_file aws-ecs-update_service service-deploy-ecs-update-service.json
  stub_response_file aws-ecs-describe_services service-deploy-ecs-describe-services.json

  run run_command bin/service/v1/restart-containers -i example-infra -s example-service -e staging
  assert_success
  assert_output_contains "New event message"
  assert_output_contains "COMPLETED - Desired: 2, Pending: 0, Running: 2"
}

@test "restart-containers propagates a failing update-service call and never polls" {
  stub_exit aws-ecs-update_service 1

  run --separate-stderr run_command bin/service/v1/restart-containers -i example-infra -s example-service -e staging
  assert_failure
  refute_stub_called_with "describe-services"
}
