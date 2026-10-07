#!/usr/bin/env bats

load ../test_helper

LOG_GROUP="example-project-example-infra-staging-infrastructure-ecs-cluster-service-logs-example-service"

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-describe_services v2-ecs-describe-services.json
  stub_response_file dalmatian-aws-run_command-p-example_account-ecs-describe_task_definition v2-ecs-describe-task-definition-awslogs.json
  stub_response_file dalmatian-aws-run_command-p-example_account-logs-filter_log_events v2-logs-filter-log-events.json
}

@test "logs prints usage with no arguments" {
  run --separate-stderr run_command bin/service/v2/logs
  assert_failure 1
  assert_stderr_contains "Usage: logs"
  assert_output_contains "-s <service_name>"
}

@test "logs requires an infrastructure" {
  run --separate-stderr run_command bin/service/v2/logs -e "staging" -s "example-service"
  assert_failure 1
  assert_stderr_contains "Usage: logs"
}

@test "logs requires an environment" {
  run --separate-stderr run_command bin/service/v2/logs -i "example-infra" -s "example-service"
  assert_failure 1
  assert_stderr_contains "Usage: logs"
}

@test "logs requires a service" {
  run --separate-stderr run_command bin/service/v2/logs -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: logs"
}

@test "logs -h shows usage" {
  run --separate-stderr run_command bin/service/v2/logs -h
  assert_failure 1
  assert_stderr_contains "Usage: logs"
}

@test "logs reads the log group from the container named after the service" {
  # The task definition fixture lists a sidecar with its own log group first
  run run_command bin/service/v2/logs -i "example-infra" -e "staging" -s "example-service"
  assert_success
  assert_stub_called_with "ecs describe-services --cluster example-project-example-infra-staging-infrastructure --services example-service"
  assert_stub_called_with "ecs describe-task-definition --task-definition arn:aws:ecs:eu-west-2:123456789012:task-definition/example-project-example-infra-staging-example-service:3"
  assert_stub_called_with "logs filter-log-events --log-group-name $LOG_GROUP"
  refute_stub_called_with "example-sidecar-log-group"
}

@test "logs fetches the requested window and formats each event on one line" {
  run run_command bin/service/v2/logs -i "example-infra" -e "staging" -s "example-service" \
    -S "2026-10-01T09:00:00Z" -U "2026-10-01T10:00:00Z"
  assert_success
  assert_stub_called_with "--start-time 1790845200000 --end-time 1790848800000"
  assert_line 0 "2026-10-01T09:00:01Z example-service/task-abc123 GET /healthcheck 200"
  assert_line 1 "2026-10-01T09:01:02Z example-service/task-def456 ERROR something broke"
  [ "${#lines[@]}" -eq 2 ]
}

@test "logs prints a multiline message verbatim, as aws logs tail does" {
  stub_response dalmatian-aws-run_command-p-example_account-logs-filter_log_events <<'JSON'
{ "events": [{ "logStreamName": "example-service/task-abc123", "timestamp": 1790845201000, "message": "Traceback:\n  frame one\n" }] }
JSON

  run run_command bin/service/v2/logs -i "example-infra" -e "staging" -s "example-service"
  assert_success
  assert_line 0 "2026-10-01T09:00:01Z example-service/task-abc123 Traceback:"
  assert_line 1 "  frame one"
  [ "${#lines[@]}" -eq 2 ]
}

@test "logs accepts a relative age for -S" {
  run run_command bin/service/v2/logs -i "example-infra" -e "staging" -s "example-service" -S "2h"
  assert_success

  local start_ms now_ms
  start_ms="$(grep -o -- '--start-time [0-9]*' "$DALMATIAN_STUB_LOG" | awk '{ print $2 }')"
  now_ms="$(gdate +%s%3N)"
  [ $(( now_ms - start_ms )) -ge 7200000 ]
  [ $(( now_ms - start_ms )) -lt 7260000 ]
}

@test "logs passes a filter pattern through" {
  run run_command bin/service/v2/logs -i "example-infra" -e "staging" -s "example-service" -p "ERROR"
  assert_success
  assert_stub_called_with "--filter-pattern ERROR"
}

@test "logs writes to a file with -o" {
  run run_command bin/service/v2/logs -i "example-infra" -e "staging" -s "example-service" -o "$SANDBOX/service.log"
  assert_success
  assert_output ""
  grep -qF "example-service/task-def456 ERROR something broke" "$SANDBOX/service.log"
}

@test "logs -f tails the log group with aws logs tail" {
  run run_command bin/service/v2/logs -i "example-infra" -e "staging" -s "example-service" -f -S "2026-10-01T09:00:00Z" -p "ERROR"
  assert_success
  assert_stub_called_with "logs tail $LOG_GROUP --follow --since 2026-10-01T09:00:00Z --filter-pattern ERROR"
  refute_stub_called_with "filter-log-events"
}

@test "logs refuses -f with -U or -o" {
  run --separate-stderr run_command bin/service/v2/logs -i "example-infra" -e "staging" -s "example-service" -f -o "$SANDBOX/x.log"
  assert_failure 1
  assert_stderr_contains "-f cannot be combined with -U or -o"
  refute_stub_called_with "ecs describe-services"
}

@test "logs rejects an unparseable time" {
  run --separate-stderr run_command bin/service/v2/logs -i "example-infra" -e "staging" -s "example-service" -S "not a date"
  assert_failure 1
  assert_stderr_contains "Could not parse -S 'not a date'"
  refute_stub_called_with "ecs describe-services"
}

@test "logs rejects a window that ends before it starts" {
  run --separate-stderr run_command bin/service/v2/logs -i "example-infra" -e "staging" -s "example-service" \
    -S "2026-10-01T10:00:00Z" -U "2026-10-01T09:00:00Z"
  assert_failure 1
  assert_stderr_contains "must be before its end"
}

@test "logs fails when the service does not exist" {
  stub_response dalmatian-aws-run_command-p-example_account-ecs-describe_services '{ "services": [] }'

  run --separate-stderr run_command bin/service/v2/logs -i "example-infra" -e "staging" -s "example-service"
  assert_failure 1
  assert_stderr_contains "Service example-service not found in cluster example-project-example-infra-staging-infrastructure"
  refute_stub_called_with "ecs describe-task-definition"
}

@test "logs fails when the task definition has no container named after the service" {
  stub_response dalmatian-aws-run_command-p-example_account-ecs-describe_task_definition '{ "taskDefinition": { "containerDefinitions": [{ "name": "gotenberg" }] } }'

  run --separate-stderr run_command bin/service/v2/logs -i "example-infra" -e "staging" -s "example-service"
  assert_failure 1
  assert_stderr_contains "No container named example-service found in task definition"
  refute_stub_called_with "logs filter-log-events"
}

@test "logs explains when the service does not log to CloudWatch" {
  stub_response dalmatian-aws-run_command-p-example_account-ecs-describe_task_definition '{ "taskDefinition": { "containerDefinitions": [{ "name": "example-service", "logConfiguration": { "logDriver": "syslog", "options": {} } }] } }'

  run --separate-stderr run_command bin/service/v2/logs -i "example-infra" -e "staging" -s "example-service"
  assert_failure 1
  assert_stderr_contains "Service example-service logs with the 'syslog' driver, not to CloudWatch Logs"
  refute_stub_called_with "logs filter-log-events"
}

@test "logs targets resources using the terraform project name override" {
  jq '.terraform_project_name = .project_name | .project_name = "installation-project"' "$CONFIG_SETUP_JSON_FILE" > "$SANDBOX/override.json"
  mv "$SANDBOX/override.json" "$CONFIG_SETUP_JSON_FILE"
  run run_command bin/service/v2/logs -i "example-infra" -e "staging" -s "example-service"
  assert_success
  assert_stub_called_with "ecs describe-services --cluster example-project-example-infra-staging-infrastructure --services example-service"
}

@test "logs creates the -o file readable only by its owner" {
  run run_command bin/service/v2/logs -i "example-infra" -e "staging" -s "example-service" -o "$SANDBOX/service.log"
  assert_success
  [ -n "$(find "$SANDBOX/service.log" -perm 600)" ]
}
