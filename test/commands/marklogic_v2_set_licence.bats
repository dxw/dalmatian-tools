#!/usr/bin/env bats

load ../test_helper

# Chosen per test so a tunnel left open on the machine cannot collide
ML_PORT="$(free_local_port)"

# marklogic/v2/set-licence posts a new licence key and licensee to each host's
# Admin API, one host at a time, then hands over to licence-status for the
# final report.
#
# The licence key is only ever read from a file or the prompt and handed to
# curl through a file, so the tests check the recorded argv never contains it.

NEW_KEY="1111-2222-3333-4444-5555-6000"
KEY_PREFIX="dalmatian-aws-run_command-p-example_account"
KEY_SESSION_B="$KEY_PREFIX-ssm-start_session-document_name-AWS_StartPortForwardingSession-target-i_0bbbbbbbbbbbbbbbb"
KEY_SESSION="$KEY_PREFIX-ssm-start_session"
STACK_KEY_VALUE="AAAA-BBBB-CCCC-DDDD-EEEE-3000"
CURL_INIT="curl-request-POST-url-http___localhost_${ML_PORT}_admin_v1_init"
CURL_TIMESTAMP="curl-request-GET-url-http___localhost_${ML_PORT}_admin_v1_timestamp"

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

  stub_hold "$KEY_SESSION"
  stub_response_file "$KEY_PREFIX-ec2-describe_instances" marklogic-describe-instances.json
  stub_response_file "$KEY_PREFIX-cloudformation-describe_stacks" marklogic-describe-stacks.json
  printf '204\n' > "$DALMATIAN_STUB_RESPONSES/$CURL_INIT.out"
  printf '2026-09-30T10:00:00Z\n200\n' > "$DALMATIAN_STUB_RESPONSES/$CURL_TIMESTAMP.out"

  printf '%s\n' "$NEW_KEY" > "$SANDBOX/new.key"
}

set_licence() {
  run_command bin/marklogic/v2/set-licence -i "example-infra" -e "staging" -s "marklogic-cluster" "$@"
}

@test "set-licence prints usage with no arguments" {
  run --separate-stderr run_command bin/marklogic/v2/set-licence
  assert_failure 1
  assert_stderr_contains "Usage: set-licence"
  assert_output_contains "-f <key_file>"
  assert_output_contains "-S "
  assert_output_contains "-L <licensee>"
}

@test "set-licence requires the stack key" {
  run --separate-stderr run_command bin/marklogic/v2/set-licence -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: set-licence"
}

@test "set-licence applies the key from a file to every host with the stack's licensee, then reports" {
  run --separate-stderr set_licence -f "$SANDBOX/new.key" -y
  assert_success

  assert_stub_called_with "--target i-0aaaaaaaaaaaaaaaa --parameters portNumber=8001,localPortNumber=${ML_PORT}"
  assert_stub_called_with "--target i-0bbbbbbbbbbbbbbbb --parameters portNumber=8001,localPortNumber=${ML_PORT}"
  assert_stub_called_with "--target i-0ccccccccccccccccc --parameters portNumber=8001,localPortNumber=${ML_PORT}"
  assert_stub_called_with "--data-urlencode licensee=Example Licensee - Unrestricted"
  assert_stub_called_with "--data-urlencode license-key@/dev/fd/"
  assert_stub_called_with "--header Accept: application/json"
  refute_stub_called_with "$NEW_KEY"
  refute_stub_called_with "examplepassword"

  assert_output_contains "i-0aaaaaaaaaaaaaaaa (marklogic-1): licence updated"
  assert_output_contains "i-0bbbbbbbbbbbbbbbb (No Name): licence updated"
  assert_output_contains "i-0ccccccccccccccccc (marklogic-3): licence updated"

  # The final report is licence-status itself, run through the CLI
  assert_stub_called_with "dalmatian marklogic licence-status -i example-infra -e staging -s marklogic-cluster -p example-account -u example-user"
  assert_stderr_contains "Update the LicenseKey parameter for stack 'marklogic-cluster' in the infrastructure tfvars"
}

@test "set-licence reads the key from the prompt when no file is given" {
  run --separate-stderr set_licence -y <<< "$NEW_KEY"
  assert_success
  assert_output_contains "licence updated"
  refute_stub_called_with "$NEW_KEY"
}

@test "set-licence rejects a key that does not look like a licence key" {
  printf 'not a key\n' > "$SANDBOX/bad.key"

  run --separate-stderr set_licence -f "$SANDBOX/bad.key" -y
  assert_failure 1
  assert_stderr_contains "does not look like a MarkLogic licence key"
  refute_stub_called_with "start-session"
}

@test "set-licence -S takes the key from the stack's LicenseKey parameter" {
  run --separate-stderr set_licence -S -y
  assert_success
  assert_output_contains "licence updated"
  assert_stub_called_with "--data-urlencode license-key@/dev/fd/"
  refute_stub_called_with "$STACK_KEY_VALUE"
}

@test "set-licence -A uses the stack's admin user, with a warning, and reports as it" {
  unset MARKLOGIC_USER

  run --separate-stderr set_licence -f "$SANDBOX/new.key" -A -y
  assert_success
  assert_stderr_contains "Using the stack's admin user 'example-marklogic-admin'"
  assert_stub_called_with "marklogic licence-status -i example-infra -e staging -s marklogic-cluster -p example-account -u example-marklogic-admin"
}

@test "set-licence refuses to run with no username" {
  unset MARKLOGIC_USER

  run --separate-stderr set_licence -f "$SANDBOX/new.key" -y < /dev/null
  assert_failure 1
  assert_stderr_contains "No MarkLogic username given"
  refute_stub_called_with "start-session"
}

@test "set-licence -S fails when the stack has no LicenseKey parameter" {
  jq '.Stacks[0].Parameters |= map(select(.ParameterKey != "LicenseKey"))' \
    "$DALMATIAN_ROOT/test/fixtures/marklogic-describe-stacks.json" > "$DALMATIAN_STUB_RESPONSES/$KEY_PREFIX-cloudformation-describe_stacks.out"

  run --separate-stderr set_licence -S -y
  assert_failure 1
  assert_stderr_contains "has no LicenseKey parameter"
  refute_stub_called_with "start-session"
}

@test "set-licence refuses -S together with -f" {
  run --separate-stderr set_licence -S -f "$SANDBOX/new.key" -y
  assert_failure 1
  assert_stderr_contains "-S and -f cannot be used together"
}

@test "set-licence rejects an instance id that is not a node of the stack" {
  run --separate-stderr set_licence -f "$SANDBOX/new.key" -I "i-00000000000000000" -y
  assert_failure 1
  assert_stderr_contains "is not a running node of stack"
  refute_stub_called_with "start-session"
}

@test "set-licence uses the -L licensee instead of the stack's" {
  run set_licence -f "$SANDBOX/new.key" -L "Other Licensee" -y
  assert_success
  assert_stub_called_with "--data-urlencode licensee=Other Licensee"
  refute_stub_called_with "licensee=Example Licensee"
}

@test "set-licence aborts before touching any host when the confirmation is declined" {
  run --separate-stderr set_licence -f "$SANDBOX/new.key" <<< "n"
  assert_failure 1
  assert_stderr_contains "Aborted"
  refute_stub_called_with "start-session"
}

@test "set-licence waits for a restarting host's startup timestamp to move on before the next host" {
  # The 202 body carries the startup time before the restart; the host is
  # back once the timestamp endpoint answers with a later one
  printf '{"restart": {"last-startup": [{"value": "2026-09-30T09:00:00Z"}]}}\n202\n' > "$DALMATIAN_STUB_RESPONSES/$CURL_INIT.out"

  run --separate-stderr set_licence -f "$SANDBOX/new.key" -y
  assert_success
  assert_output_contains "i-0aaaaaaaaaaaaaaaa (marklogic-1): licence updated, MarkLogic restarting"
  assert_output_contains "i-0aaaaaaaaaaaaaaaa (marklogic-1): back"
  assert_stub_called_with "--url http://localhost:${ML_PORT}/admin/v1/timestamp"
}

@test "set-licence stops when a restarting host does not come back with a new startup timestamp" {
  # Same startup time before and after: the host never restarted, or never
  # came back. Either way the next host must not be touched
  printf '{"restart": {"last-startup": [{"value": "2026-09-30T10:00:00Z"}]}}\n202\n' > "$DALMATIAN_STUB_RESPONSES/$CURL_INIT.out"
  export DALMATIAN_MARKLOGIC_RESTART_ATTEMPTS=2

  run --separate-stderr set_licence -f "$SANDBOX/new.key" -y
  assert_failure 1
  assert_stderr_contains "i-0aaaaaaaaaaaaaaaa (marklogic-1) did not come back from its restart"
  assert_stub_called_with "--target i-0aaaaaaaaaaaaaaaa"
  refute_stub_called_with "--target i-0bbbbbbbbbbbbbbbb"
}

@test "set-licence stops when the Admin API refuses the credentials" {
  printf '401\n' > "$DALMATIAN_STUB_RESPONSES/$CURL_INIT.out"

  run --separate-stderr set_licence -f "$SANDBOX/new.key" -y
  assert_failure 1
  assert_stderr_contains "refused user 'example-user' (HTTP 401)"
  refute_stub_called_with "--target i-0bbbbbbbbbbbbbbbb"
  refute_stub_called_with "marklogic licence-status"
}

@test "set-licence stops at the first host when the key is rejected" {
  printf '{"errorResponse": {"message": "Invalid license key"}}\n400\n' > "$DALMATIAN_STUB_RESPONSES/$CURL_INIT.out"

  run --separate-stderr set_licence -f "$SANDBOX/new.key" -y
  assert_failure 1
  assert_stderr_contains "rejected the licence (HTTP 400): Invalid license key"
  assert_stub_called_with "--target i-0aaaaaaaaaaaaaaaa"
  refute_stub_called_with "--target i-0bbbbbbbbbbbbbbbb"
  # No host was changed, so there is nothing to report or warn about
  refute_stub_called_with "marklogic licence-status"
}

@test "set-licence reports an unreachable host and carries on with the rest" {
  stub_exit "$KEY_SESSION_B" 1

  run --separate-stderr set_licence -f "$SANDBOX/new.key" -y
  assert_failure 1
  assert_output_contains "i-0aaaaaaaaaaaaaaaa (marklogic-1): licence updated"
  assert_output_contains "i-0bbbbbbbbbbbbbbbb (No Name): not reachable through Systems Manager, licence not set"
  assert_output_contains "i-0ccccccccccccccccc (marklogic-3): licence updated"
  assert_stderr_contains "1 host(s) were not updated"
}

@test "set-licence applies to only the given node with -I" {
  run set_licence -f "$SANDBOX/new.key" -I "i-0ccccccccccccccccc" -y
  assert_success
  assert_stub_called_with "--target i-0ccccccccccccccccc"
  refute_stub_called_with "--target i-0aaaaaaaaaaaaaaaa"
}
