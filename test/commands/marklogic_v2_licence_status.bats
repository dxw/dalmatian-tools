#!/usr/bin/env bats

load ../test_helper

# Chosen per test so a tunnel left open on the machine cannot collide
ML_PORT="$(free_local_port)"

# marklogic/v2/licence-status opens one SSM tunnel to a reachable node, reads
# the cluster's host list and each host's status from the Manage API, and
# compares every host's licence with the stack's parameters.
#
# curl is stubbed. Responses are keyed by the request's method and URL, which
# the tunnel helper puts first so that the trailing --config path (a temp
# file) never has to be known here. Each response ends with the HTTP status
# line curl's --write-out would append.

STACK="cf-ccb69c87-marklogic-cluster"
KEY_PREFIX="dalmatian-aws-run_command-p-example_account"
KEY_SESSION_A="$KEY_PREFIX-ssm-start_session-document_name-AWS_StartPortForwardingSession-target-i_0aaaaaaaaaaaaaaaa"
KEY_SESSION_B="$KEY_PREFIX-ssm-start_session-document_name-AWS_StartPortForwardingSession-target-i_0bbbbbbbbbbbbbbbb"
KEY_SESSION_C="$KEY_PREFIX-ssm-start_session-document_name-AWS_StartPortForwardingSession-target-i_0ccccccccccccccccc"
KEY_SESSION="$KEY_PREFIX-ssm-start_session"
CURL_HOSTS="curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_hosts_format_json"
CURL_STATUS_1="curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_hosts_ip_10_0_1_10_eu_west_2_compute_internal_view_status_format_json"
CURL_STATUS_2="curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_hosts_ip_10_0_2_10_eu_west_2_compute_internal_view_status_format_json"
CURL_STATUS_3="curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_hosts_ip_10_0_3_10_eu_west_2_compute_internal_view_status_format_json"

# Stage a curl response: a fixture body followed by the status code line
stub_curl() {
  local key=$1 fixture=$2 status=${3:-200}
  { cat "$DALMATIAN_ROOT/test/fixtures/$fixture"; printf '%s\n' "$status"; } > "$DALMATIAN_STUB_RESPONSES/$key.out"
}

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  export DALMATIAN_MARKLOGIC_LOCAL_PORT=${ML_PORT}
  export DALMATIAN_MARKLOGIC_TUNNEL_ATTEMPTS=3
  export MARKLOGIC_PASSWORD="examplepassword"
  # The operator's own MarkLogic user, not the stack's admin user
  export MARKLOGIC_USER="example-user"

  # A reachable session stays up until closed; see test/lib/marklogic_tunnel.bats
  stub_hold "$KEY_SESSION"
  stub_response_file "$KEY_PREFIX-ec2-describe_instances" marklogic-describe-instances.json
  stub_response_file "$KEY_PREFIX-cloudformation-describe_stacks" marklogic-describe-stacks.json
  stub_curl "$CURL_HOSTS" marklogic-manage-hosts.json
  stub_curl "$CURL_STATUS_1" marklogic-manage-host-status-1.json
  stub_curl "$CURL_STATUS_2" marklogic-manage-host-status-2.json
  stub_curl "$CURL_STATUS_3" marklogic-manage-host-status-3.json
}

status() {
  run_command bin/marklogic/v2/licence-status -i "example-infra" -e "staging" -s "marklogic-cluster" "$@"
}

@test "licence-status prints usage with no arguments" {
  run --separate-stderr run_command bin/marklogic/v2/licence-status
  assert_failure 1
  assert_stderr_contains "Usage: licence-status"
  assert_output_contains "-s <stack>"
  assert_output_contains "-A "
  assert_output_contains "-k "
}

@test "licence-status requires the stack key" {
  run --separate-stderr run_command bin/marklogic/v2/licence-status -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: licence-status"
}

@test "licence-status reports every host's licence through one tunnel, masked, and matched against the stack" {
  run --separate-stderr status
  assert_success

  assert_stub_called_with "cloudformation describe-stacks --stack-name $STACK"
  assert_call_args dalmatian aws run-command -p example-account ssm start-session --document-name AWS-StartPortForwardingSession --target i-0aaaaaaaaaaaaaaaa --parameters "portNumber=8002,localPortNumber=${ML_PORT}"
  refute_stub_called_with "--target i-0bbbbbbbbbbbbbbbb"

  assert_output_contains "ip-10-0-1-10.eu-west-2.compute.internal | i-0aaaaaaaaaaaaaaaa (marklogic-1) | Example Licensee - Unrestricted | ****-3000 | 2027-06-30T00:00:00Z | matches stack"
  assert_output_contains "ip-10-0-2-10.eu-west-2.compute.internal | i-0bbbbbbbbbbbbbbbb (No Name) | Example Licensee - Unrestricted | ****-3000 | 2027-06-30T00:00:00Z | matches stack"
  assert_output_contains "ip-10-0-3-10.eu-west-2.compute.internal | i-0ccccccccccccccccc (marklogic-3)"
  case "$output" in
    *AAAA-BBBB*) fail "expected the licence key to be masked in the output" ;;
  esac
}

@test "licence-status keeps a host's row whole when its stored key ends in a newline" {
  jq '.["host-status"]["status-properties"]["status-detail"]["license-key"] = "AAAA-BBBB-CCCC-DDDD-EEEE-3000\n"' \
    "$DALMATIAN_ROOT/test/fixtures/marklogic-manage-host-status-1.json" > "$SANDBOX/status-1.json"
  { cat "$SANDBOX/status-1.json"; echo 200; } > "$DALMATIAN_STUB_RESPONSES/$CURL_STATUS_1.out"

  run --separate-stderr status
  assert_success
  assert_output_contains "ip-10-0-1-10.eu-west-2.compute.internal | i-0aaaaaaaaaaaaaaaa (marklogic-1) | Example Licensee - Unrestricted | ****-3000 | 2027-06-30T00:00:00Z | matches stack"
  [ "${#lines[@]}" -eq 4 ] || fail "expected a header and three host rows, got ${#lines[@]} lines"
}

@test "licence-status -k shows the full licence keys" {
  run status -k
  assert_success
  assert_output_contains "| AAAA-BBBB-CCCC-DDDD-EEEE-3000 |"
}

@test "licence-status never puts the admin password on a command line or on disk" {
  run status
  assert_success
  refute_stub_called_with "examplepassword"
  # The credentials reach curl through a process substitution, not a file
  assert_stub_called_with "--config /dev/fd/"
}

@test "licence-status rejects an instance id that is not a node of the stack" {
  run --separate-stderr status -I "i-00000000000000000"
  assert_failure 1
  assert_stderr_contains "is not a running node of stack '$STACK'"
  refute_stub_called_with "start-session"
}

@test "licence-status fails when a host's status cannot be read" {
  printf '{}\n500\n' > "$DALMATIAN_STUB_RESPONSES/$CURL_STATUS_2.out"

  run --separate-stderr status
  assert_failure 1
  assert_stderr_contains "HTTP 500 for the status of host 'ip-10-0-2-10.eu-west-2.compute.internal'"
}

@test "licence-status says so when the stack has no LicenseKey to compare with" {
  jq '.Stacks[0].Parameters |= map(select(.ParameterKey != "LicenseKey"))' \
    "$DALMATIAN_ROOT/test/fixtures/marklogic-describe-stacks.json" > "$DALMATIAN_STUB_RESPONSES/$KEY_PREFIX-cloudformation-describe_stacks.out"

  run --separate-stderr status
  assert_success
  assert_output_contains "| ****-3000 | 2027-06-30T00:00:00Z | stack has no LicenseKey parameter"
}

@test "licence-status shows an unlicensed host as such" {
  jq '.["host-status"]["status-properties"]["status-detail"]["license-key"] = "" | .["host-status"]["status-properties"]["status-detail"]["licensee"] = ""' \
    "$DALMATIAN_ROOT/test/fixtures/marklogic-manage-host-status-3.json" > "$SANDBOX/status-3.json"
  { cat "$SANDBOX/status-3.json"; echo 200; } > "$DALMATIAN_STUB_RESPONSES/$CURL_STATUS_3.out"

  run --separate-stderr status
  assert_failure 1
  assert_output_contains "ip-10-0-3-10.eu-west-2.compute.internal | i-0ccccccccccccccccc (marklogic-3) | (none) | (none) | 2027-06-30T00:00:00Z | MISMATCH: stack has ****-3000"
}

@test "licence-status flags a host whose licence differs from the stack and exits non-zero" {
  jq '.["host-status"]["status-properties"]["status-detail"]["license-key"] = "FFFF-FFFF-FFFF-FFFF-FFFF-9999"' \
    "$DALMATIAN_ROOT/test/fixtures/marklogic-manage-host-status-2.json" > "$SANDBOX/status-2.json"
  { cat "$SANDBOX/status-2.json"; echo 200; } > "$DALMATIAN_STUB_RESPONSES/$CURL_STATUS_2.out"

  run --separate-stderr status
  assert_failure 1
  assert_output_contains "ip-10-0-2-10.eu-west-2.compute.internal | i-0bbbbbbbbbbbbbbbb (No Name) | Example Licensee - Unrestricted | ****-9999 | 2027-06-30T00:00:00Z | MISMATCH: stack has ****-3000"
  assert_stderr_contains "1 host(s) do not match the stack's licence"
}

@test "licence-status flags a licensee that differs from the stack" {
  jq '.["host-status"]["status-properties"]["status-detail"]["licensee"] = "Someone Else"' \
    "$DALMATIAN_ROOT/test/fixtures/marklogic-manage-host-status-3.json" > "$SANDBOX/status-3.json"
  { cat "$SANDBOX/status-3.json"; echo 200; } > "$DALMATIAN_STUB_RESPONSES/$CURL_STATUS_3.out"

  run --separate-stderr status
  assert_failure 1
  assert_output_contains "| Someone Else | ****-3000 | 2027-06-30T00:00:00Z | MISMATCH: stack licensee is 'Example Licensee - Unrestricted'"
}

@test "licence-status tunnels through the next node when the first is unreachable" {
  stub_exit "$KEY_SESSION_A" 1

  run --separate-stderr status
  assert_success
  assert_stub_called_with "--target i-0aaaaaaaaaaaaaaaa"
  assert_stub_called_with "--target i-0bbbbbbbbbbbbbbbb"
  assert_stderr_contains "i-0aaaaaaaaaaaaaaaa is not reachable through Systems Manager"
  assert_output_contains "ip-10-0-1-10.eu-west-2.compute.internal | i-0aaaaaaaaaaaaaaaa (marklogic-1)"
}

@test "licence-status uses only the given node with -I" {
  run status -I "i-0ccccccccccccccccc"
  assert_success
  assert_stub_called_with "--target i-0ccccccccccccccccc"
  refute_stub_called_with "--target i-0aaaaaaaaaaaaaaaa"
}

@test "licence-status exits 2 when no node is reachable" {
  stub_exit "$KEY_SESSION_A" 1
  stub_exit "$KEY_SESSION_B" 1
  stub_exit "$KEY_SESSION_C" 1

  run --separate-stderr status
  assert_failure 2
  assert_stderr_contains "No node of stack '$STACK' is reachable through Systems Manager"
}

@test "licence-status fails when the Manage API rejects the credentials" {
  printf '{}\n401\n' > "$DALMATIAN_STUB_RESPONSES/$CURL_HOSTS.out"

  run --separate-stderr status
  assert_failure 1
  assert_stderr_contains "Manage API returned HTTP 401 for user 'example-user'"
}

@test "licence-status closes the tunnel on the way out" {
  run status
  assert_success
  # The held session stub would still be running if close had not reached it
  run pgrep -f "AWS-StartPortForwardingSession --target i-0aaaaaaaaaaaaaaaa --parameters portNumber=8002,localPortNumber=${ML_PORT}"
  assert_failure
}

@test "licence-status prompts for the password when it is not in the environment" {
  unset MARKLOGIC_PASSWORD

  run status <<< "examplepassword"
  assert_success
  assert_output_contains "matches stack"
}

@test "licence-status authenticates as the operator's own user, not the stack's admin user" {
  local QUIET_MODE=0

  run status
  assert_success
  assert_output_contains "as 'example-user'"
  case "$output" in
    *example-marklogic-admin*) fail "expected the stack's admin user not to be used" ;;
  esac
}

@test "licence-status prompts for the username when none is given" {
  unset MARKLOGIC_USER
  local QUIET_MODE=0

  run status <<< "typed-user"
  assert_success
  assert_output_contains "as 'typed-user'"
}

@test "licence-status refuses to run with no username" {
  unset MARKLOGIC_USER

  run --separate-stderr status < /dev/null
  assert_failure 1
  assert_stderr_contains "No MarkLogic username given"
  refute_stub_called_with "start-session"
}

@test "licence-status -A uses the stack's admin user, with a warning" {
  unset MARKLOGIC_USER
  local QUIET_MODE=0

  run --separate-stderr status -A
  assert_success
  assert_stderr_contains "Using the stack's admin user 'example-marklogic-admin'"
  assert_output_contains "as 'example-marklogic-admin'"
}

@test "licence-status refuses -A together with -u" {
  run --separate-stderr status -A -u "other-user"
  assert_failure 1
  assert_stderr_contains "-A and -u cannot be used together"
}

@test "licence-status authenticates as the -u user instead of the stack's admin user" {
  local QUIET_MODE=0

  run status -u "other-admin"
  assert_success
  assert_output_contains "as 'other-admin'"
}
