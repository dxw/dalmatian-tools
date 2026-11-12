#!/usr/bin/env bats

load ../test_helper

# Chosen per test so a tunnel left open on the machine cannot collide
ML_PORT="$(free_local_port)"

# marklogic_tunnel_open starts an SSM port-forwarding session to a MarkLogic
# host in the background and waits for the local port to answer;
# marklogic_tunnel_request runs one curl through it; marklogic_tunnel_close
# ends the session and everything it started.
#
# The session runs as `"$APP_ROOT/bin/dalmatian" aws run-command ... ssm
# start-session`, which stub_dalmatian intercepts. A live session is a
# process that stays up until it is killed, so the reachable cases hold the
# stub open (stub_hold); an unreachable host is a session that exits
# non-zero, which stub_exit reproduces. curl is stubbed too, so the port
# answers on the first probe.

KEY_SESSION="dalmatian-aws-run_command-p-example_account-ssm-start_session"

setup() {
  setup_sandbox
  use_stubs
  stub_dalmatian
  load_all_functions
  export QUIET_MODE=1
  export DALMATIAN_MARKLOGIC_LOCAL_PORT=${ML_PORT}
  export DALMATIAN_MARKLOGIC_TUNNEL_ATTEMPTS=3
  stub_hold "$KEY_SESSION"
}

teardown() {
  marklogic_tunnel_close
}

@test "marklogic_tunnel_open rejects missing arguments" {
  run --separate-stderr marklogic_tunnel_open -p example-account -I i-0aaaaaaaaaaaaaaaa
  assert_failure
  assert_stderr_contains "Invalid \`marklogic_tunnel_open\` function usage"
}

@test "marklogic_tunnel_open starts a port-forwarding session to the host's port" {
  marklogic_tunnel_open -p example-account -I i-0aaaaaaaaaaaaaaaa -P 8002
  assert_call_args dalmatian aws run-command -p example-account ssm start-session --document-name AWS-StartPortForwardingSession --target i-0aaaaaaaaaaaaaaaa --parameters "portNumber=8002,localPortNumber=${ML_PORT}"
  assert_stub_called_with "curl --silent --output /dev/null --max-time 2 --url http://localhost:${ML_PORT}/"
  [ -n "$MARKLOGIC_TUNNEL_PID" ] || fail "expected the tunnel pid to be recorded"
  kill -0 "$MARKLOGIC_TUNNEL_PID" || fail "expected the session to still be running after open"
}

@test "marklogic_tunnel_open reports a host that Systems Manager cannot reach" {
  stub_exit "$KEY_SESSION" 1

  run --separate-stderr marklogic_tunnel_open -p example-account -I i-0aaaaaaaaaaaaaaaa -P 8002
  assert_failure 2
  assert_stderr_contains "i-0aaaaaaaaaaaaaaaa is not reachable through Systems Manager"
}

@test "marklogic_tunnel_open treats a session that ends cleanly before the port answers as a failure" {
  rm -f "$DALMATIAN_STUB_RESPONSES/$KEY_SESSION.hold"
  stub_exit curl-silent-output 7

  run --separate-stderr marklogic_tunnel_open -p example-account -I i-0aaaaaaaaaaaaaaaa -P 8002
  assert_failure 2
  assert_stderr_contains "session to i-0aaaaaaaaaaaaaaaa ended before port 8002 answered"
}

@test "marklogic_tunnel_open does not trust a port that answers after the session has gone" {
  # Something else is listening on the port: the probe succeeds but the
  # session is no longer running, so the answer cannot be the host's
  rm -f "$DALMATIAN_STUB_RESPONSES/$KEY_SESSION.hold"

  run --separate-stderr marklogic_tunnel_open -p example-account -I i-0aaaaaaaaaaaaaaaa -P 8002
  assert_failure 2
  assert_stderr_contains "ended before port 8002 answered"
}

@test "marklogic_tunnel_open gives up when the port never answers" {
  stub_exit curl-silent-output 7

  run --separate-stderr marklogic_tunnel_open -p example-account -I i-0aaaaaaaaaaaaaaaa -P 8002
  assert_failure 2
  assert_stderr_contains "port 8002 on i-0aaaaaaaaaaaaaaaa did not answer"
}

@test "marklogic_tunnel_open refuses a local port that something else already listens on" {
  command -v python3 > /dev/null || skip "python3 is needed to hold a listening socket"
  # Accepts and closes every connection, so the readiness probe below cannot
  # fill the queue and make the port look free to the code under test
  python3 -c 'import socket, sys
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(16); s.settimeout(20)
while True:
    c, _ = s.accept(); c.close()' "$ML_PORT" &
  local listener=$!
  local tries=0
  until (exec 3<> "/dev/tcp/127.0.0.1/$ML_PORT") 2> /dev/null || [ "$tries" -ge 50 ]
  do
    tries=$(( tries + 1 ))
    /bin/sleep 0.1
  done

  run --separate-stderr marklogic_tunnel_open -p example-account -I i-0aaaaaaaaaaaaaaaa -P 8002
  kill "$listener" 2> /dev/null || true

  assert_failure 2
  assert_stderr_contains "local port ${ML_PORT} is already in use"
  refute_stub_called_with "start-session"
}

@test "marklogic_tunnel_open fails without the session-manager-plugin" {
  local original_path="$PATH"
  PATH="/usr/bin:/bin:/usr/sbin:/sbin"

  run --separate-stderr marklogic_tunnel_open -p example-account -I i-0aaaaaaaaaaaaaaaa -P 8002

  PATH="$original_path"

  assert_failure
  assert_stderr_contains "requires the \`session-manager-plugin\` to be installed"
}

@test "marklogic_tunnel_close ends the session and every process it started" {
  # The real CLI is a chain: bin/dalmatian runs run-command, which runs aws,
  # which runs the plugin, none of them via exec. Killing only the first
  # would orphan the rest, and the listening tunnel with them. A tagged
  # chain stands in for it here
  local marker="dalmatian-tunnel-test-$$-$RANDOM"
  rm -f "$SANDBOX/app/bin/dalmatian"
  printf '#!/usr/bin/env bash\nbash -c "/bin/sleep 30; : %s"\n' "$marker" > "$SANDBOX/app/bin/dalmatian"
  chmod +x "$SANDBOX/app/bin/dalmatian"

  marklogic_tunnel_open -p example-account -I i-0aaaaaaaaaaaaaaaa -P 8002
  pgrep -f "$marker" > /dev/null || fail "expected the tagged child process to be running"

  marklogic_tunnel_close
  /bin/sleep 0.2

  run pgrep -f "$marker"
  assert_failure
  [ -z "$MARKLOGIC_TUNNEL_PID" ] || fail "expected the tunnel pid to be cleared"
}

@test "marklogic_tunnel_request sends the request through the tunnel with the credentials file and prints the status last" {
  printf 'body-from-host\n200\n' > "$DALMATIAN_STUB_RESPONSES/curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_hosts_format_json.out"
  printf 'user = "example:secretpassword"\n' > "$SANDBOX/curl.cfg"

  marklogic_tunnel_open -p example-account -I i-0aaaaaaaaaaaaaaaa -P 8002
  run marklogic_tunnel_request -X GET -u "/manage/v2/hosts?format=json" -K "$SANDBOX/curl.cfg"

  assert_success
  assert_line 0 "body-from-host"
  assert_line 1 "200"
  assert_call_args curl --request GET --url "http://localhost:${ML_PORT}/manage/v2/hosts?format=json" --silent --show-error --anyauth --write-out $'\n%{http_code}' --config "$SANDBOX/curl.cfg"
  refute_stub_called_with "secretpassword"
}

@test "marklogic_tunnel_request passes extra curl arguments through" {
  printf '204\n' > "$DALMATIAN_STUB_RESPONSES/curl-request-POST-url-http___localhost_${ML_PORT}_admin_v1_init.out"
  printf 'user = "example:secretpassword"\n' > "$SANDBOX/curl.cfg"

  marklogic_tunnel_open -p example-account -I i-0aaaaaaaaaaaaaaaa -P 8002
  run marklogic_tunnel_request -X POST -u "/admin/v1/init" -K "$SANDBOX/curl.cfg" -- --data-urlencode "licensee=Example"

  assert_success
  assert_output "204"
  assert_stub_called_with "--data-urlencode licensee=Example"
}

@test "marklogic_tunnel_request refuses to run with no tunnel open" {
  run --separate-stderr marklogic_tunnel_request -X GET -u "/manage/v2/hosts" -K "$SANDBOX/curl.cfg"
  assert_failure
  assert_stderr_contains "No MarkLogic tunnel is open"
}

@test "marklogic_tunnel_settle pauses for about the requested time without calling sleep" {
  local before after elapsed_ms
  before="$(gdate +%s%N)"
  run marklogic_tunnel_settle 0.2
  after="$(gdate +%s%N)"
  assert_success
  elapsed_ms=$(( (after - before) / 1000000 ))
  [ "$elapsed_ms" -ge 150 ] || fail "expected a pause of at least 150ms, got ${elapsed_ms}ms"
  refute_stub_called_with "sleep"
}
