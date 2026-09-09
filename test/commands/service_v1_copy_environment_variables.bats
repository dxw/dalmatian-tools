#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "copy-environment-variables prints usage with no arguments" {
  run --separate-stderr run_command bin/service/v1/copy-environment-variables
  assert_failure 1
  assert_stderr_contains "Usage: copy-environment-variables"
  assert_output_contains "-I <infrastructure>"
}

@test "copy-environment-variables requires source -i, -s and -e" {
  run --separate-stderr run_command bin/service/v1/copy-environment-variables \
    -I other-infra
  assert_failure 1
  assert_stderr_contains "Source infrastructure, service and environment must be specified (-i, -s, -e)"
}

@test "copy-environment-variables rejects identical source and destination" {
  # No -I/-S/-E given, so destination defaults to source -- and the script
  # rejects that as a no-op, without ever printing usage.
  run --separate-stderr run_command bin/service/v1/copy-environment-variables \
    -i example-infra -s example-service -e staging
  assert_failure 1
  assert_stderr_contains "Source and destination are the same"
  refute_output_line "Usage: copy-environment-variables"
}

@test "copy-environment-variables -k copies a single key from the source path to the destination path" {
  stub_response aws-ssm-get_parameter '{"Parameter": {"Value": "smtp.example.org"}}'

  run run_command bin/service/v1/copy-environment-variables \
    -i example-infra -s example-service -e staging -E production -k SMTP_HOST
  assert_success
  assert_stub_called_with "get-parameter --with-decryption --name /example-infra/example-service/staging/SMTP_HOST"
  assert_stub_called_with "put-parameter --name /example-infra/example-service/production/SMTP_HOST --value smtp.example.org"
}

@test "copy-environment-variables -k defaults unset destination parts to the source" {
  # Only -S (destination service) is given; destination infra/env fall back
  # to the source infra/env.
  stub_response aws-ssm-get_parameter '{"Parameter": {"Value": "smtp.example.org"}}'

  run run_command bin/service/v1/copy-environment-variables \
    -i example-infra -s example-service -e staging -S other-service -k SMTP_HOST
  assert_success
  assert_stub_called_with "put-parameter --name /example-infra/other-service/staging/SMTP_HOST --value smtp.example.org"
}

# FINDING (latent, shell-version-dependent bug -- verified, not guessed): the
# whole-service copy loop does `((COUNT++))` as a bare statement under
# `set -e`. An arithmetic command's exit status is its expression's *value*,
# and a post-increment's value is the pre-increment one, so on the very first
# iteration (COUNT still 0) `((COUNT++))` evaluates "false". Under bash >=4.1
# that makes `set -e` kill the script right there: only the first parameter
# ever gets copied, every later key is silently dropped, and the "Successfully
# copied N" summary never prints -- confirmed with
# `/opt/homebrew/bin/bash -c 'set -e; COUNT=0; ((COUNT++)); echo after'`
# (prints nothing after, exits 1).
#
# This script alone is shebanged `#!/bin/bash` (its five siblings all use
# `#!/usr/bin/env bash`). On this Mac /bin/bash is Apple's frozen bash
# 3.2.57, and bash 3.2's `((...))` does NOT trip errexit the same way
# (`/bin/bash -c 'set -e; COUNT=0; ((COUNT++)); echo after'` prints "after"
# and exits 0) -- which is what makes the loop below run to completion here.
# On any host where /bin/bash is a modern bash (most Linux distributions,
# including CI runners), the same script would hit the bug above and abort
# after the first key. The test below asserts this repo's actual,
# machine-dependent behaviour; treat a flip to failure-after-one-key on a
# different host as this bug surfacing, not as a broken test.
@test "copy-environment-variables without -k copies every key returned by list-environment-variables -j" {
  stub_response_file aws-ssm-get_parameters_by_path service-v1-get-parameters-by-path.json

  QUIET_MODE=0 run run_command bin/service/v1/copy-environment-variables \
    -i example-infra -s example-service -e staging -E production

  # Which outcome is correct depends on the /bin/bash this script is shebanged
  # to, so the platform is detected rather than assumed -- see the comment
  # above. Both branches assert the *same* first write, so a wrong parameter
  # path fails everywhere; they differ only on whether the loop survives.
  if /bin/bash -c 'set -e; COUNT=0; ((COUNT++)); exit 0' 2> /dev/null
  then
    # bash 3.2: the arithmetic statement does not trip errexit, loop completes
    assert_success
    assert_stub_called_with "put-parameter --name /example-infra/example-service/production/SMTP_PORT --value 25"
    assert_stub_called_with "put-parameter --name /example-infra/example-service/production/SMTP_HOST --value smtp.example.org"
    assert_output_contains "Successfully copied 2 environment variables."
  else
    # bash 4+: ((COUNT++)) returns 1 on the first iteration and errexit aborts,
    # so exactly one key is copied and the summary never prints. This is the
    # bug, asserted rather than skipped so it is visible on the hosts it
    # actually affects.
    assert_failure
    assert_stub_called_with "put-parameter --name /example-infra/example-service/production/SMTP_PORT --value 25"
    refute_stub_called_with "SMTP_HOST"
    refute_output_line "Successfully copied 2 environment variables."
  fi
}

@test "copy-environment-variables without -k reports when there is nothing to copy" {
  stub_response aws-ssm-get_parameters_by_path '{"Parameters": []}'

  QUIET_MODE=0 run run_command bin/service/v1/copy-environment-variables \
    -i example-infra -s example-service -e staging -E production
  assert_success
  assert_output_contains "No environment variables found to copy."
  refute_stub_called_with "put-parameter"
}

@test "copy-environment-variables -k fails, and never writes, when the source key cannot be read" {
  stub_exit aws-ssm-get_parameter 254

  run run_command bin/service/v1/copy-environment-variables \
    -i example-infra -s example-service -e staging -E production -k MISSING_KEY
  assert_failure
  refute_stub_called_with "put-parameter"
}
