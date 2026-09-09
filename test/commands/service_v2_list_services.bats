#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-describe_services v2-ecs-describe-services.json
  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-describe_task_definition v2-ecs-describe-task-definition.json
}

@test "list-services prints usage with no arguments" {
  # usage() sends only its first line to stderr; the option list (lines
  # 9-12 of the script) is plain \`echo\`, so it lands on stdout.
  run --separate-stderr run_command bin/service/v2/list-services
  assert_failure 1
  assert_stderr_contains "Usage: list-services"
  assert_output_contains "-s <service_name>"
}

@test "list-services requires an infrastructure" {
  run --separate-stderr run_command bin/service/v2/list-services -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: list-services"
}

@test "list-services requires an environment" {
  run --separate-stderr run_command bin/service/v2/list-services -i "example-infra"
  assert_failure 1
  assert_stderr_contains "Usage: list-services"
}

@test "list-services -h shows usage" {
  run --separate-stderr run_command bin/service/v2/list-services -h
  assert_failure 1
  assert_stderr_contains "Usage: list-services"
}

@test "list-services queries the cluster named from project, infrastructure and environment" {
  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-list_services v2-ecs-list-services-one.json

  run run_command bin/service/v2/list-services -i "example-infra" -e "staging"
  assert_success
  assert_stub_called_with "ecs list-services --cluster example-project-example-infra-staging-infrastructure"
}

@test "list-services shapes a single service's output from the fixture data" {
  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-list_services v2-ecs-list-services-one.json

  run run_command bin/service/v2/list-services -i "example-infra" -e "staging"
  assert_success

  local result
  result="$(echo "$output" | jq -c '.services["example-service"]')"
  [ "$result" = '{"desired_containers":"2","running_containers":"1","environment_file_bucket":"example-bucket","environment_file_key":"example-service.env"}' ]
}

@test "list-services filters to the given service name, describing only the matching one" {
  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-list_services v2-ecs-list-services-two.json

  run run_command bin/service/v2/list-services -i "example-infra" -e "staging" -s "example-service"
  assert_success
  assert_stub_called_with "ecs describe-services --cluster example-project-example-infra-staging-infrastructure --services arn:aws:ecs:eu-west-2:123456789012:service/example-cluster/example-service"
  refute_stub_called_with "arn:aws:ecs:eu-west-2:123456789012:service/example-cluster/other-service"

  local result
  result="$(echo "$output" | jq -r '.services | keys | length')"
  [ "$result" = "1" ]
}

@test "list-services still issues one spurious describe-services call when the filter matches nothing" {
  # SERVICE_ARNS is reduced to an empty string by the `select(endswith(...))`
  # filter, but the loop at the bottom of the script reads it via
  # `< <(echo "$SERVICE_ARNS")`, which yields one blank line rather than zero
  # lines. So the for loop still runs once with an empty ARN and issues one
  # `ecs describe-services --services ""` call instead of skipping the loop
  # entirely -- existing (buggy) behaviour of the script under test, not
  # something to fix here. Because setup() stubs describe-services broadly
  # (matching any --services value), that phantom call returns the fixture's
  # service data rather than nothing, so the "no match" filter still reports
  # a service in its output.
  stub_response dalmatian-aws-run_command-p-example_account-ecs-list_services '{ "serviceArns": [] }'

  run run_command bin/service/v2/list-services -i "example-infra" -e "staging" -s "no-such-service"
  assert_success
  # argv-exact: "--services " is a prefix of any real service ARN, so the
  # substring form could not tell an empty loop iteration from a real one
  assert_call_args dalmatian aws run-command -p example-account \
    ecs describe-services \
    --cluster example-project-example-infra-staging-infrastructure --services ""

  local result
  result="$(echo "$output" | jq -r '.services | keys | length')"
  [ "$result" = "1" ]
}

@test "list-services fails when no AWS profile matches the infrastructure/environment" {
  stub_response aws-configure-list_profiles "dalmatian-main"

  run --separate-stderr run_command bin/service/v2/list-services -i "example-infra" -e "staging"
  assert_failure
  assert_stderr_contains "Profile does not exist for example-infra staging"
  refute_stub_called_with "ecs list-services"
}
