# shellcheck shell=bash
#
# The single file every .bats file loads. Provides a sandboxed HOME, a loader
# for lib/bash-functions, the PATH-stub controls, and assertion helpers.
#
# The assertion helpers deliberately take the names and argument shapes of their
# bats-assert equivalents. bats-support/bats-assert are not vendored in this
# repo, so if that changes, these can be deleted and the test bodies left alone.
#
# SC2154 is disabled for the whole file because bats' `run` is what assigns
# $status, $output, $lines and $stderr, and shellcheck cannot see that.
# shellcheck disable=SC2154

# `run --separate-stderr`, which the tests use to assert on stderr separately
# from stdout, is a 1.5.0 feature. Declaring it here rather than in each .bats
# file means a new test file gets it by loading this helper.
bats_require_minimum_version 1.5.0

DALMATIAN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export DALMATIAN_ROOT

# Point HOME and the Dalmatian config paths at a throwaway directory.
#
# bin/dalmatian and bin/configure-commands/v2/version both derive their
# configuration from $HOME/.config/dalmatian, and bin/aws/v1/login reads
# ~/.aws/sso/cache, so overriding HOME is what keeps a test run away from the
# developer's real configuration. CONFIG_* are exported as well because the
# functions read them directly when sourced outside bin/dalmatian.
setup_sandbox() {
  SANDBOX="$BATS_TEST_TMPDIR/sandbox"
  export SANDBOX
  export HOME="$SANDBOX/home"
  export APP_ROOT="$DALMATIAN_ROOT"
  export CONFIG_DIR="$HOME/.config/dalmatian"
  export CONFIG_SETUP_JSON_FILE="$CONFIG_DIR/setup.json"
  export CONFIG_AWS_SSO_FILE="$CONFIG_DIR/dalmatian-sso.config"
  export DALMATIAN_SKIP_UPDATE_CHECK=1
  export DALMATIAN_FZF_ENABLED=0
  export QUIET_MODE=0
  mkdir -p "$CONFIG_DIR" "$SANDBOX/bin"
}

# Source files from lib/bash-functions and restore the shell options they set.
#
# Each of those files runs `set -e` and `set -o pipefail` at file scope, so
# sourcing one enables errexit in the test shell. Functions that return non-zero
# by contract -- yes_no, is_installed, dalmatian_v1_sso_available, the pickers --
# would then abort the test rather than be asserted on.
load_function() {
  local name errexit_was pipefail_was

  case "$-" in
    *e*) errexit_was=1 ;;
    *) errexit_was=0 ;;
  esac
  if shopt -qo pipefail
  then
    pipefail_was=1
  else
    pipefail_was=0
  fi

  for name in "$@"
  do
    # shellcheck disable=SC1090
    source "$DALMATIAN_ROOT/lib/bash-functions/$name.sh"
  done

  if [ "$errexit_was" -eq 0 ]
  then
    set +e
  fi
  if [ "$pipefail_was" -eq 0 ]
  then
    set +o pipefail
  fi
}

# Source everything in lib/bash-functions. Most functions call at least one
# other -- esc_msg needs log_msg, die needs err, the pickers need
# ec2_instance_lines and err -- so this is usually what a test wants.
load_all_functions() {
  local names=() file

  for file in "$DALMATIAN_ROOT"/lib/bash-functions/*.sh
  do
    [ -f "$file" ] || continue
    names+=("$(basename "$file" .sh)")
  done

  load_function "${names[@]}"
}

fail() {
  printf '%s\n' "$1" >&2
  return 1
}

assert_success() {
  if [ "$status" -ne 0 ]
  then
    fail "$(printf 'expected success, got exit status %s\noutput:\n%s' "$status" "$output")"
  fi
}

assert_failure() {
  local expected=${1-}

  if [ "$status" -eq 0 ]
  then
    fail "$(printf 'expected failure, got exit status 0\noutput:\n%s' "$output")"
    return 1
  fi
  if [ -n "$expected" ] && [ "$status" -ne "$expected" ]
  then
    fail "$(printf 'expected exit status %s, got %s\noutput:\n%s' "$expected" "$status" "$output")"
  fi
}

assert_output() {
  if [ "$output" != "$1" ]
  then
    fail "$(printf 'expected output:\n%s\nactual output:\n%s' "$1" "$output")"
  fi
}

assert_output_contains() {
  case "$output" in
    *"$1"*) ;;
    *) fail "$(printf 'expected output to contain:\n%s\nactual output:\n%s' "$1" "$output")" ;;
  esac
}

assert_stderr_contains() {
  case "$stderr" in
    *"$1"*) ;;
    *) fail "$(printf 'expected stderr to contain:\n%s\nactual stderr:\n%s' "$1" "$stderr")" ;;
  esac
}

assert_line() {
  local index=$1 expected=$2

  if [ "${lines[$index]-}" != "$expected" ]
  then
    fail "$(printf 'expected line %s to be:\n%s\nactual:\n%s' "$index" "$expected" "${lines[$index]-}")"
  fi
}

# Put the stub directory on PATH and prepare the response and log locations.
#
# $SANDBOX/bin comes first so a per-test shim can override a stub. The gdate
# shim lives there because Linux hosts have GNU date as `date`, while
# bin/aws/v1/login and bin/dalmatian both call `gdate`.
use_stubs() {
  export DALMATIAN_STUB_RESPONSES="$SANDBOX/stub-responses"
  export DALMATIAN_STUB_LOG="$SANDBOX/stub-calls.log"
  export DALMATIAN_STUB_ARGV_LOG="$SANDBOX/stub-calls-argv.log"
  mkdir -p "$DALMATIAN_STUB_RESPONSES"
  : > "$DALMATIAN_STUB_LOG"
  : > "$DALMATIAN_STUB_ARGV_LOG"

  if ! command -v gdate > /dev/null
  then
    printf '#!/usr/bin/env bash\nexec date "$@"\n' > "$SANDBOX/bin/gdate"
    chmod +x "$SANDBOX/bin/gdate"
  fi

  export PATH="$SANDBOX/bin:$DALMATIAN_ROOT/test/stubs:$PATH"
}

# Stage a stub response. With arguments, they become the body; with none, the
# body is read from stdin, which reads better for JSON heredocs.
stub_response() {
  local key=$1
  shift

  if [ "$#" -gt 0 ]
  then
    printf '%s\n' "$*" > "$DALMATIAN_STUB_RESPONSES/$key.out"
  else
    cat > "$DALMATIAN_STUB_RESPONSES/$key.out"
  fi
}

stub_response_file() {
  cp "$DALMATIAN_ROOT/test/fixtures/$2" "$DALMATIAN_STUB_RESPONSES/$1.out"
}

stub_exit() {
  printf '%s\n' "$2" > "$DALMATIAN_STUB_RESPONSES/$1.exit"
}

assert_stub_called_with() {
  if ! grep -qF -- "$1" "$DALMATIAN_STUB_LOG"
  then
    fail "$(printf 'expected a stub call matching:\n%s\ncalls recorded:\n%s' "$1" "$(cat "$DALMATIAN_STUB_LOG")")"
  fi
}

refute_stub_called_with() {
  if grep -qF -- "$1" "$DALMATIAN_STUB_LOG"
  then
    fail "$(printf 'expected no stub call matching:\n%s\ncalls recorded:\n%s' "$1" "$(cat "$DALMATIAN_STUB_LOG")")"
  fi
}

refute_output_line() {
  local line

  for line in "${lines[@]}"
  do
    if [ "$line" = "$1" ]
    then
      fail "$(printf 'expected output not to contain the line:\n%s\nactual output:\n%s' "$1" "$output")"
    fi
  done
}

install_fixture() {
  mkdir -p "$(dirname "$2")"
  cp "$DALMATIAN_ROOT/test/fixtures/$1" "$2"
}

fixture_json() {
  cat "$DALMATIAN_ROOT/test/fixtures/$1"
}

# Repoint APP_ROOT at a fake app root whose bin/dalmatian is a stub.
#
# resolve_aws_profile shells out to "$APP_ROOT/bin/dalmatian deploy
# list-infrastructures", so testing it means faking the CLI, not just the aws
# binary. lib is symlinked through so anything the code under test sources
# still resolves.
#
# Never call this in the same test as use_test_app_root: both build
# $SANDBOX/app, and they want opposite things from bin/dalmatian.
stub_dalmatian() {
  mkdir -p "$SANDBOX/app/bin"
  ln -sfn "$DALMATIAN_ROOT/lib" "$SANDBOX/app/lib"
  ln -sfn "$DALMATIAN_ROOT/data" "$SANDBOX/app/data"
  ln -sfn "$DALMATIAN_ROOT/test/stubs/_dispatch" "$SANDBOX/app/bin/dalmatian"
  export APP_ROOT="$SANDBOX/app"
}

# Build a working app root in the sandbox, with test-only subcommands.
#
# bin/dalmatian sets APP_ROOT from `dirname "${BASH_SOURCE[0]}"`, so a *copy*
# placed in the sandbox treats the sandbox as the app root with no environment
# override. That is what makes it safe to add probe subcommands: they exist only
# for the duration of the test and never touch the real bin/ tree.
#
# probe exists under both v1 and v2 so version-specific dispatch can be tested;
# only-v2 exists under v2 alone so the "not available in v1" path can be.
use_test_app_root() {
  local probe

  mkdir -p "$SANDBOX/app/bin/probe/v1" \
           "$SANDBOX/app/bin/probe/v2" \
           "$SANDBOX/app/bin/only-v2/v2"
  ln -sfn "$DALMATIAN_ROOT/lib" "$SANDBOX/app/lib"
  ln -sfn "$DALMATIAN_ROOT/data" "$SANDBOX/app/data"
  ln -sfn "$DALMATIAN_ROOT/bin/configure-commands" "$SANDBOX/app/bin/configure-commands"
  ln -sfn "$DALMATIAN_ROOT/bin/aws" "$SANDBOX/app/bin/aws"
  ln -sfn "$DALMATIAN_ROOT/terraform-project-versions.json" "$SANDBOX/app/terraform-project-versions.json"
  cp "$DALMATIAN_ROOT/bin/dalmatian" "$SANDBOX/app/bin/dalmatian"

  for probe in "$SANDBOX/app/bin/probe/v1/echo-args" \
               "$SANDBOX/app/bin/probe/v2/echo-args" \
               "$SANDBOX/app/bin/only-v2/v2/echo-args"
  do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@"\n' > "$probe"
    chmod +x "$probe"
  done

  TEST_DALMATIAN="$SANDBOX/app/bin/dalmatian"
  export TEST_DALMATIAN
}

# Stage everything the v1 AWS SSO auth path reads, so bin/dalmatian can reach a
# subcommand without network or credentials.
#
# bin/aws/v1/login reads ~/.aws/sso/cache/*.json and compares expiresAt against
# the current time, taking the "already logged in" branch when the session is
# still valid -- which is what keeps `aws sso login` from ever being reached.
# sntp is stubbed to fail so aws_epoch falls back to gdate deterministically.
#
# Call use_stubs first. This needs GNU date semantics (`-d`), and use_stubs is
# what guarantees `gdate` resolves to something that has them: real gdate from
# the coreutils formula on macOS, or its shim over `date` on Linux. Calling
# `date` directly as a fallback would be worse than no fallback, because the
# only host it could run on is one where BSD date rejects `-d` anyway.
login_sandbox() {
  local expires

  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  install_fixture dalmatian-sso.config "$CONFIG_AWS_SSO_FILE"

  expires="$(gdate -u -d '+8 hours' '+%Y-%m-%dT%H:%M:%SZ')"

  mkdir -p "$HOME/.aws/sso/cache"
  printf '{"startUrl": "https://example.awsapps.com/start", "expiresAt": "%s"}\n' \
    "$expires" > "$HOME/.aws/sso/cache/session.json"

  stub_exit sntp 1
  stub_response aws-version "aws-cli/2.36.22 Python/3.13.0 Darwin/25.6.0 source/arm64"
  stub_response aws-configure-get-sso_start_url "https://example.awsapps.com/start"
  stub_response aws-sts-get_caller_identity "arn:aws:sts::123456789012:assumed-role/admin/example.user"
  stub_response aws-configure-export_credentials <<'CREDS'
export AWS_ACCESS_KEY_ID=AKIAEXAMPLE
export AWS_SECRET_ACCESS_KEY=examplesecret
export AWS_SESSION_TOKEN=exampletoken
CREDS
}

# Run a bin/ script the way bin/dalmatian would.
#
# Command scripts call log_info, err and the pickers without sourcing anything:
# bin/dalmatian sources lib/bash-functions and `export -f`s each function before
# dispatching. Reproducing that here is what lets a command be tested without
# going through the whole dispatcher and its auth path.
#
# The script and the functions always come from the real repo. APP_ROOT is
# separate, and defaults to the same place but can be pointed elsewhere by
# stub_cli, so that a command which re-enters the CLI -- many v2 commands run
# `"$APP_ROOT/bin/dalmatian" aws run-command ...` -- reaches a stub rather than
# the real dispatcher and its login path.
run_command() {
  local script=$1 app_root
  shift

  app_root="${DALMATIAN_TEST_APP_ROOT:-$DALMATIAN_ROOT}"

  QUIET_MODE="${QUIET_MODE:-0}" \
    bash -c '
      APP_ROOT="$1"; shift
      export APP_ROOT
      repo_root="$1"; shift
      script="$1"; shift
      for f in "$repo_root"/lib/bash-functions/*.sh
      do
        [ -f "$f" ] || continue
        source "$f"
        while IFS="" read -r function_name
        do
          export -f "${function_name?}"
        done < <(grep "^function" "$f" | cut -d" " -f2)
      done
      exec "$repo_root/$script" "$@"
    ' bash "$app_root" "$DALMATIAN_ROOT" "$script" "$@"
}

# Make a command's re-entrant "$APP_ROOT/bin/dalmatian" calls hit a stub.
#
# Distinct from stub_dalmatian, which repoints APP_ROOT for a *function* under
# test. This one leaves run_command loading the script from the real repo, so
# the two compose: the command is real, the CLI it shells back into is not.
#
# Responses are keyed as `dalmatian-<subcommand>-<command>`, so
# `"$APP_ROOT/bin/dalmatian" aws run-command ...` is answered by
# `dalmatian-aws-run_command`.
stub_cli() {
  mkdir -p "$SANDBOX/cli/bin"
  ln -sfn "$DALMATIAN_ROOT/lib" "$SANDBOX/cli/lib"
  ln -sfn "$DALMATIAN_ROOT/data" "$SANDBOX/cli/data"
  ln -sfn "$DALMATIAN_ROOT/test/stubs/_dispatch" "$SANDBOX/cli/bin/dalmatian"
  # Every bin/config/v1 command opens by running this, which reaches AWS. It is
  # stubbed here rather than per-test because none of those scripts set errexit,
  # so a missing binary would fail silently and leave the test passing for the
  # wrong reason
  ln -sfn "$DALMATIAN_ROOT/test/stubs/_dispatch" "$SANDBOX/cli/bin/dalmatian-refresh-config"
  export DALMATIAN_TEST_APP_ROOT="$SANDBOX/cli"
}

# Assert a stub was called with EXACTLY this argument vector.
#
# Takes the stub name then each argument as a separate parameter, and compares
# against the argv log, so argument boundaries and empty arguments are matched
# faithfully:
#
#   assert_call_args aws s3api delete-bucket --bucket ""
#
# Use it instead of assert_stub_called_with wherever the whole value matters --
# a bucket, an autoscaling group, a certificate ARN. Substring matching is too
# weak in two ways that both produce tests which pass while proving nothing:
# "--target i-abc" matches a recorded "--target i-abc-decoy", and "--bucket "
# matches "--bucket example-bucket" because it is a prefix of it.
assert_call_args() {
  local expected

  expected="$(
    printf '%s' "$1"
    shift
    printf ' %q' "$@"
  )"

  if ! grep -qFx -- "$expected" "$DALMATIAN_STUB_ARGV_LOG"
  then
    fail "$(printf 'expected a stub call with exactly this argv:\n%s\nargv calls recorded:\n%s' \
      "$expected" "$(cat "$DALMATIAN_STUB_ARGV_LOG")")"
  fi
}
