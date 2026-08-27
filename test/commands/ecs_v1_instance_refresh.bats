#!/usr/bin/env bats

load ../test_helper

# The polling loop calls a real `sleep 30` between non-Successful iterations
# (see bin/ecs/v1/instance-refresh). Every test here stubs the very first
# describe-instance-refreshes response as already Successful, so no test
# should ever reach a sleep -- this is a defensive no-op fallback in case
# that assumption is ever violated, following the pattern already used in
# test/commands/service_v1_force_deployment.bats.
fake_instant_sleep() {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/bin/sleep"
  chmod +x "$SANDBOX/bin/sleep"
}

# assert_stub_called_with does a substring match, which would let an
# ASG name like "asg-ecs-example-infra-staging-abc123-wrong" pass an
# assertion for "asg-ecs-example-infra-staging-abc123" -- exactly the
# "picks the wrong target" failure mode this file most wants to catch. This
# checks a whole stub-log line matches exactly instead.
setup() {
  setup_sandbox
  use_stubs
  fake_instant_sleep
  export QUIET_MODE=1
  stub_response_file aws-autoscaling-describe_auto_scaling_groups ecs-more-asg-describe-auto-scaling-groups.json
  stub_response_file aws-autoscaling-start_instance_refresh ecs-more-start-instance-refresh.json
  stub_response_file aws-autoscaling-describe_instance_refreshes ecs-more-describe-instance-refreshes-successful.json
}

@test "ecs instance-refresh prints usage with no arguments" {
  run --separate-stderr run_command bin/ecs/v1/instance-refresh
  assert_failure 1
  assert_stderr_contains "Usage: instance-refresh"
  assert_output_contains "-e <environment>"
}

@test "ecs instance-refresh requires an environment" {
  run --separate-stderr run_command bin/ecs/v1/instance-refresh -i "example-infra"
  assert_failure 1
  assert_stderr_contains "Usage: instance-refresh"
}

@test "ecs instance-refresh starts a refresh on the ASG matching infrastructure and environment" {
  QUIET_MODE=0 run run_command bin/ecs/v1/instance-refresh -i "example-infra" -e "staging"
  assert_success
  # The ASG list has both a staging and a prod ASG for the same
  # infrastructure -- confirms the regex selects only the matching one.
  # assert_call_args (not assert_stub_called_with's substring match) is
  # used here so a name with an extra suffix, e.g.
  # "asg-ecs-example-infra-staging-abc123-decoy", cannot slip past as a match
  assert_call_args aws autoscaling start-instance-refresh --auto-scaling-group-name asg-ecs-example-infra-staging-abc123
  assert_call_args aws autoscaling describe-instance-refreshes --auto-scaling-group-name asg-ecs-example-infra-staging-abc123
  refute_stub_called_with "asg-ecs-example-infra-prod-def456"
  assert_output_contains "Status: Successful, Percent Complete: 100, Instances to update: 0"
}

@test "ecs instance-refresh starts a refresh with an empty ASG name when nothing matches" {
  # No `-z "$AUTO_SCALING_GROUP_NAME"` guard exists: when the jq select finds
  # no matching ASG, AUTO_SCALING_GROUP_NAME is simply empty, and the script
  # still calls start-instance-refresh with an empty
  # --auto-scaling-group-name rather than failing with a clear error.
  run run_command bin/ecs/v1/instance-refresh -i "example-infra" -e "qa"
  assert_success
  assert_call_args aws autoscaling start-instance-refresh --auto-scaling-group-name ""
  refute_stub_called_with "--auto-scaling-group-name asg-ecs-example-infra-staging-abc123"
  refute_stub_called_with "--auto-scaling-group-name asg-ecs-example-infra-prod-def456"
}

@test "ecs instance-refresh logs a non-null status reason once" {
  stub_response_file aws-autoscaling-describe_instance_refreshes ecs-more-describe-instance-refreshes-successful-with-reason.json

  QUIET_MODE=0 run run_command bin/ecs/v1/instance-refresh -i "example-infra" -e "staging"
  assert_success
  assert_output_contains "Refresh finished successfully"
}
