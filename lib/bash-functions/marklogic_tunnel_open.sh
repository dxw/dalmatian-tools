#!/usr/bin/env bash
set -e
set -o pipefail

# An SSM port-forwarding tunnel to a port on a MarkLogic host, for talking to
# the Admin (8001) and Manage (8002) APIs that only listen locally.
#
# Going through a tunnel and running curl here, rather than running curl on
# the host through Run Command, is what keeps the admin password and licence
# key out of the Systems Manager command history: they travel inside the
# tunnel to localhost and nowhere else.
#
# One tunnel is open at a time, tracked in MARKLOGIC_TUNNEL_PID and
# MARKLOGIC_TUNNEL_PORT. Opening another closes the first. The other halves
# are marklogic_tunnel_request and marklogic_tunnel_close.
#
# The local port is random unless DALMATIAN_MARKLOGIC_LOCAL_PORT is set, and
# is refused if something already listens on it: a request must never reach
# a listener that is not this tunnel. For the same reason the tunnel counts
# as open only while its session process is alive, so an answer from the
# port after the session has gone is treated as a failure, not a success.
# DALMATIAN_MARKLOGIC_TUNNEL_ATTEMPTS (default 30, one per second) bounds
# the wait for the port.
#
# @usage marklogic_tunnel_open -p "$PROFILE" -I "$INSTANCE_ID" -P 8002
# @param -p <profile>      AWS profile
# @param -I <instance_id>  Host to tunnel to
# @param -P <remote_port>  Port on the host
# @return 0 when the port answers, 2 when the host is unreachable, the port
#         is taken or the port never answers, 1 on bad usage
function marklogic_tunnel_open {
  local PROFILE=""
  local INSTANCE_ID=""
  local REMOTE_PORT=""
  local ATTEMPT
  local MAX_ATTEMPTS
  local PICK
  local TUNNEL_STATUS

  OPTIND=1
  while getopts "p:I:P:" opt; do
    case $opt in
      p)
        PROFILE="$OPTARG"
        ;;
      I)
        INSTANCE_ID="$OPTARG"
        ;;
      P)
        REMOTE_PORT="$OPTARG"
        ;;
      *)
        echo "Invalid \`marklogic_tunnel_open\` function usage" >&2
        return 1
        ;;
    esac
  done

  if [[ -z "$PROFILE" || -z "$INSTANCE_ID" || -z "$REMOTE_PORT" ]]
  then
    echo "Invalid \`marklogic_tunnel_open\` function usage" >&2
    return 1
  fi

  if ! command -v session-manager-plugin > /dev/null
  then
    err "This command requires the \`session-manager-plugin\` to be installed"
    log_msg -l "https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html" -q "$QUIET_MODE"
    return 1
  fi

  if [ -n "${MARKLOGIC_TUNNEL_PID:-}" ]
  then
    marklogic_tunnel_close
  fi

  MAX_ATTEMPTS="${DALMATIAN_MARKLOGIC_TUNNEL_ATTEMPTS:-30}"

  # A port with a listener already on it is never used: connecting to it is
  # the test, since a listener accepts and a free port refuses
  if [ -n "${DALMATIAN_MARKLOGIC_LOCAL_PORT:-}" ]
  then
    MARKLOGIC_TUNNEL_PORT="$DALMATIAN_MARKLOGIC_LOCAL_PORT"
    if (exec 3<> "/dev/tcp/127.0.0.1/$MARKLOGIC_TUNNEL_PORT") 2> /dev/null
    then
      err "The local port $MARKLOGIC_TUNNEL_PORT is already in use"
      MARKLOGIC_TUNNEL_PORT=""
      return 2
    fi
  else
    MARKLOGIC_TUNNEL_PORT=""
    for (( PICK = 1; PICK <= 10; PICK++ ))
    do
      MARKLOGIC_TUNNEL_PORT=$(( 10000 + RANDOM % 20000 ))
      if ! (exec 3<> "/dev/tcp/127.0.0.1/$MARKLOGIC_TUNNEL_PORT") 2> /dev/null
      then
        break
      fi
      MARKLOGIC_TUNNEL_PORT=""
    done
    if [ -z "$MARKLOGIC_TUNNEL_PORT" ]
    then
      err "Could not find a free local port for the tunnel"
      return 2
    fi
  fi

  "$APP_ROOT/bin/dalmatian" aws run-command \
    -p "$PROFILE" \
    ssm start-session \
    --document-name AWS-StartPortForwardingSession \
    --target "$INSTANCE_ID" \
    --parameters "portNumber=$REMOTE_PORT,localPortNumber=$MARKLOGIC_TUNNEL_PORT" \
    > /dev/null 2>&1 &
  MARKLOGIC_TUNNEL_PID=$!

  # A session to an unmanaged host fails within moments of starting. Give it
  # that moment before the first probe, so its exit is what gets seen
  marklogic_tunnel_settle 0.3

  for (( ATTEMPT = 1; ATTEMPT <= MAX_ATTEMPTS; ATTEMPT++ ))
  do
    if ! kill -0 "$MARKLOGIC_TUNNEL_PID" 2> /dev/null
    then
      TUNNEL_STATUS=0
      wait "$MARKLOGIC_TUNNEL_PID" || TUNNEL_STATUS=$?
      MARKLOGIC_TUNNEL_PID=""
      if [ "$TUNNEL_STATUS" -ne 0 ]
      then
        err "$INSTANCE_ID is not reachable through Systems Manager (the port-forwarding session exited with status $TUNNEL_STATUS)"
      else
        err "The session to $INSTANCE_ID ended before port $REMOTE_PORT answered"
      fi
      return 2
    fi
    if curl --silent --output /dev/null --max-time 2 --url "http://localhost:$MARKLOGIC_TUNNEL_PORT/"
    then
      # Only the session's own listener counts, so the session must still
      # be running now that something has answered
      if kill -0 "$MARKLOGIC_TUNNEL_PID" 2> /dev/null
      then
        return 0
      fi
      continue
    fi
    # The per-second wait between probes; sleep is fine here because a
    # probe that fails is never mistaken for one that succeeds
    sleep 1
  done

  marklogic_tunnel_close
  err "port $REMOTE_PORT on $INSTANCE_ID did not answer through the tunnel after $MAX_ATTEMPTS attempts"
  return 2
}
