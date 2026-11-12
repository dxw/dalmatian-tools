#!/usr/bin/env bats

load ../test_helper

# Chosen per test so a tunnel left open on the machine cannot collide
ML_PORT="$(free_local_port)"

# The fixtures follow the real Manage API layout, captured from a staging
# host: the licence sits under status-properties.status-detail, with the key
# and licensee as plain strings and the expiry wrapped as {units, value}

setup() {
  setup_sandbox
  use_stubs
  stub_dalmatian
  load_all_functions
  export QUIET_MODE=1
  export DALMATIAN_MARKLOGIC_LOCAL_PORT="$ML_PORT"
  export DALMATIAN_MARKLOGIC_TUNNEL_ATTEMPTS=3
  stub_hold dalmatian-aws-run_command-p-example_account-ssm-start_session

  local base="curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_hosts"
  { fixture_json marklogic-manage-hosts.json; echo 200; } > "$DALMATIAN_STUB_RESPONSES/${base}_format_json.out"
  local n
  for n in 1 2 3
  do
    { fixture_json "marklogic-manage-host-status-$n.json"; echo 200; } \
      > "$DALMATIAN_STUB_RESPONSES/${base}_ip_10_0_${n}_10_eu_west_2_compute_internal_view_status_format_json.out"
  done

  marklogic_tunnel_open -p example-account -I i-0aaaaaaaaaaaaaaaa -P 8002
}

teardown() {
  marklogic_tunnel_close
}

licences() {
  marklogic_host_licences -j "$(fixture_json marklogic-describe-instances.json)" -u example-admin -c 'user = "example-admin:examplepassword"'
}

@test "marklogic_host_licences reads each host's licence from status-detail" {
  run licences
  assert_success
  assert_line 0 '{"host":"ip-10-0-1-10.eu-west-2.compute.internal","instance":"i-0aaaaaaaaaaaaaaaa (marklogic-1)","licensee":"Example Licensee - Unrestricted","key":"AAAA-BBBB-CCCC-DDDD-EEEE-3000","expires":"2027-06-30T00:00:00Z"}'
  assert_line 1 '{"host":"ip-10-0-2-10.eu-west-2.compute.internal","instance":"i-0bbbbbbbbbbbbbbbb (No Name)","licensee":"Example Licensee - Unrestricted","key":"AAAA-BBBB-CCCC-DDDD-EEEE-3000","expires":"2027-06-30T00:00:00Z"}'
}

@test "marklogic_host_licences ties a host to its instance through the managed network interface" {
  # The MarkLogic template gives each node a second, managed interface, and
  # MarkLogic names the host after that, not the instance's primary address
  run licences
  assert_success
  assert_output_contains '"host":"ip-10-0-1-10.eu-west-2.compute.internal","instance":"i-0aaaaaaaaaaaaaaaa (marklogic-1)"'
}

@test "marklogic_host_licences trims whitespace a host has stored with its licence" {
  # The documented curl for setting a licence closes its quote on the next
  # line, so hosts licensed that way store the key with a trailing newline
  jq '.["host-status"]["status-properties"]["status-detail"]["license-key"] = "AAAA-BBBB-CCCC-DDDD-EEEE-3000\n"' \
    "$DALMATIAN_ROOT/test/fixtures/marklogic-manage-host-status-1.json" > "$SANDBOX/status-1.json"
  { cat "$SANDBOX/status-1.json"; echo 200; } \
    > "$DALMATIAN_STUB_RESPONSES/curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_hosts_ip_10_0_1_10_eu_west_2_compute_internal_view_status_format_json.out"

  run licences
  assert_success
  assert_output_contains '"key":"AAAA-BBBB-CCCC-DDDD-EEEE-3000","expires"'
}

@test "marklogic_host_licences gives empty fields for a host with no licence" {
  jq '.["host-status"]["status-properties"]["status-detail"] |= del(.["license-key"], .licensee, .["license-key-expires"])' \
    "$DALMATIAN_ROOT/test/fixtures/marklogic-manage-host-status-3.json" > "$SANDBOX/status-3.json"
  { cat "$SANDBOX/status-3.json"; echo 200; } \
    > "$DALMATIAN_STUB_RESPONSES/curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_hosts_ip_10_0_3_10_eu_west_2_compute_internal_view_status_format_json.out"

  run licences
  assert_success
  assert_line 2 '{"host":"ip-10-0-3-10.eu-west-2.compute.internal","instance":"i-0ccccccccccccccccc (marklogic-3)","licensee":"","key":"","expires":""}'
}

@test "marklogic_host_licences fails when the host list is refused" {
  printf '{}\n401\n' > "$DALMATIAN_STUB_RESPONSES/curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_hosts_format_json.out"

  run --separate-stderr licences
  assert_failure
  assert_stderr_contains "Manage API returned HTTP 401 for user 'example-admin' when listing hosts"
}

@test "marklogic_host_licences rejects missing arguments" {
  run --separate-stderr marklogic_host_licences -j '{}'
  assert_failure
  assert_stderr_contains "Invalid \`marklogic_host_licences\` function usage"
}
