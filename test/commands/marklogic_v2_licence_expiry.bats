#!/usr/bin/env bats

load ../test_helper

# Chosen per test so a tunnel left open on the machine cannot collide
ML_PORT="$(free_local_port)"

# marklogic/v2/licence-expiry reads every host's licence through one tunnel,
# as licence-status does, and reports the expiry date and days left.
#
# Expiry dates are generated relative to the moment the test runs, with an
# hour's margin so the whole-day count cannot tip over during the run.

STACK="cf-ccb69c87-marklogic-cluster"
KEY_PREFIX="dalmatian-aws-run_command-p-example_account"
KEY_SESSION="$KEY_PREFIX-ssm-start_session"
CURL_BASE="curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_hosts"

# Stage host N's status with the given expiry ("" for no licence at all)
stub_host_expiry() {
  local n=$1 expires=$2
  if [ -n "$expires" ]
  then
    jq --arg e "$expires" '.["host-status"]["status-properties"]["status-detail"]["license-key-expires"].value = $e' \
      "$DALMATIAN_ROOT/test/fixtures/marklogic-manage-host-status-$n.json" > "$SANDBOX/status-$n.json"
  else
    jq '.["host-status"]["status-properties"]["status-detail"] |= del(.["license-key"], .licensee, .["license-key-expires"])' \
      "$DALMATIAN_ROOT/test/fixtures/marklogic-manage-host-status-$n.json" > "$SANDBOX/status-$n.json"
  fi
  { cat "$SANDBOX/status-$n.json"; echo 200; } \
    > "$DALMATIAN_STUB_RESPONSES/${CURL_BASE}_ip_10_0_${n}_10_eu_west_2_compute_internal_view_status_format_json.out"
}

in_days() {
  gdate -u -d "+$1 days +1 hour" '+%Y-%m-%dT%H:%M:%SZ'
}

date_in_days() {
  gdate -u -d "+$1 days +1 hour" '+%Y-%m-%d'
}

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  export DALMATIAN_MARKLOGIC_LOCAL_PORT="$ML_PORT"
  export DALMATIAN_MARKLOGIC_TUNNEL_ATTEMPTS=3
  export MARKLOGIC_PASSWORD="examplepassword"
  # The operator's own MarkLogic user, not the stack's admin user
  export MARKLOGIC_USER="example-user"

  stub_hold "$KEY_SESSION"
  stub_response_file "$KEY_PREFIX-ec2-describe_instances" marklogic-describe-instances.json
  stub_response_file "$KEY_PREFIX-cloudformation-describe_stacks" marklogic-describe-stacks.json
  { fixture_json marklogic-manage-hosts.json; echo 200; } > "$DALMATIAN_STUB_RESPONSES/${CURL_BASE}_format_json.out"

  stub_host_expiry 1 "$(in_days 200)"
  stub_host_expiry 2 "$(in_days 200)"
  stub_host_expiry 3 "$(in_days 200)"
}

expiry() {
  run_command bin/marklogic/v2/licence-expiry -i "example-infra" -e "staging" -s "marklogic-cluster" "$@"
}

@test "licence-expiry prints usage with no arguments" {
  run --separate-stderr run_command bin/marklogic/v2/licence-expiry
  assert_failure 1
  assert_stderr_contains "Usage: licence-expiry"
  assert_output_contains "-w <days>"
}

@test "licence-expiry requires the stack key" {
  run --separate-stderr run_command bin/marklogic/v2/licence-expiry -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: licence-expiry"
}

@test "licence-expiry rejects a warning window that is not a whole number of days" {
  run --separate-stderr expiry -w "30; echo"
  assert_failure 1
  assert_stderr_contains "-w must be a whole number of days"
  refute_stub_called_with "describe-instances"
}

@test "licence-expiry reports each host's expiry date and days left" {
  run --separate-stderr expiry
  assert_success
  assert_line 0 "HOST | INSTANCE | EXPIRES | DAYS LEFT | STATUS"
  assert_output_contains "ip-10-0-1-10.eu-west-2.compute.internal | i-0aaaaaaaaaaaaaaaa (marklogic-1) | $(date_in_days 200) | 200 | ok"
  assert_output_contains "ip-10-0-2-10.eu-west-2.compute.internal | i-0bbbbbbbbbbbbbbbb (No Name) | $(date_in_days 200) | 200 | ok"
  assert_call_args dalmatian aws run-command -p example-account ssm start-session --document-name AWS-StartPortForwardingSession --target i-0aaaaaaaaaaaaaaaa --parameters "portNumber=8002,localPortNumber=${ML_PORT}"
}

@test "licence-expiry flags a host inside the default 30-day window and exits non-zero" {
  stub_host_expiry 2 "$(in_days 20)"

  run --separate-stderr expiry
  assert_failure 1
  assert_output_contains "ip-10-0-2-10.eu-west-2.compute.internal | i-0bbbbbbbbbbbbbbbb (No Name) | $(date_in_days 20) | 20 | expiring"
  assert_stderr_contains "1 host(s) need attention"
}

@test "licence-expiry -w widens the warning window" {
  run --separate-stderr expiry -w 365
  assert_failure 1
  assert_output_contains "| 200 | expiring"
}

@test "licence-expiry -w narrows the warning window" {
  stub_host_expiry 2 "$(in_days 20)"

  run --separate-stderr expiry -w 7
  assert_success
  assert_output_contains "| 20 | ok"
}

@test "licence-expiry reports an expired licence with negative days" {
  stub_host_expiry 3 "$(gdate -u -d '-5 days -1 hour' '+%Y-%m-%dT%H:%M:%SZ')"

  run --separate-stderr expiry
  assert_failure 1
  assert_output_contains "ip-10-0-3-10.eu-west-2.compute.internal | i-0ccccccccccccccccc (marklogic-3) | $(gdate -u -d '-5 days -1 hour' '+%Y-%m-%d') | -6 | expired"
}

@test "licence-expiry reports a host with no licence" {
  stub_host_expiry 3 ""

  run --separate-stderr expiry
  assert_failure 1
  assert_output_contains "ip-10-0-3-10.eu-west-2.compute.internal | i-0ccccccccccccccccc (marklogic-3) | - | - | unlicensed"
}

@test "licence-expiry reports an expiry it cannot read rather than guessing" {
  stub_host_expiry 1 "not-a-date"

  run --separate-stderr expiry
  assert_failure 1
  assert_output_contains "ip-10-0-1-10.eu-west-2.compute.internal | i-0aaaaaaaaaaaaaaaa (marklogic-1) | not-a-date | - | unknown"
}

@test "licence-expiry refuses to run with no username" {
  unset MARKLOGIC_USER

  run --separate-stderr expiry < /dev/null
  assert_failure 1
  assert_stderr_contains "No MarkLogic username given"
  refute_stub_called_with "start-session"
}

@test "licence-expiry -A uses the stack's admin user, with a warning" {
  unset MARKLOGIC_USER

  run --separate-stderr expiry -A
  assert_success
  assert_stderr_contains "Using the stack's admin user 'example-marklogic-admin'"
  assert_stub_called_with "cloudformation describe-stacks --stack-name $STACK"
}

@test "licence-expiry does not read the stack without -A" {
  run expiry
  assert_success
  refute_stub_called_with "cloudformation describe-stacks"
}

@test "licence-expiry exits 2 when no node is reachable" {
  stub_exit "$KEY_SESSION" 1

  run --separate-stderr expiry
  assert_failure 2
  assert_stderr_contains "No node of stack '$STACK' is reachable through Systems Manager"
}

@test "licence-expiry never puts the admin password on a command line" {
  run expiry
  assert_success
  refute_stub_called_with "examplepassword"
  assert_stub_called_with "--config /dev/fd/"
}

@test "licence-expiry rejects an instance id that is not a node of the stack" {
  run --separate-stderr expiry -I "i-00000000000000000"
  assert_failure 1
  assert_stderr_contains "is not a running node of stack '$STACK'"
  refute_stub_called_with "start-session"
}
