#!/usr/bin/env bats

load ../test_helper

# generate-basic-auth-password-hash is pure local computation: it reads a
# password silently from stdin (no terminal under bats, so `read -rs` just
# consumes whatever is piped in) and prints `<sha256-hex-salt><pbkdf2-sha512-hex>`
# via lib/pbkdf2-hmac-hash.py. HASH_RE below pins that exact shape: 64 lowercase
# hex characters of salt (a sha256 hexdigest) followed by 128 lowercase hex
# characters of digest (a 64-byte pbkdf2_hmac('sha512', ...) output).
#
# shellcheck disable=SC2030,SC2031
# HASH_RE is assigned in setup() and read back inside @test bodies, which run
# as separate bats processes -- shellcheck can't see that the value survives.
HASH_RE='^[0-9a-f]{192}$'

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "generate-basic-auth-password-hash -h shows usage" {
  run --separate-stderr run_command bin/cloudfront/v1/generate-basic-auth-password-hash -h
  assert_failure 1
  assert_stderr_contains "Usage: generate-basic-auth-password-hash"
}

@test "generate-basic-auth-password-hash rejects an unknown flag with usage" {
  run --separate-stderr run_command bin/cloudfront/v1/generate-basic-auth-password-hash -x
  assert_failure 1
  assert_stderr_contains "Usage: generate-basic-auth-password-hash"
}

@test "generate-basic-auth-password-hash prompts, then prints a 64-hex-salt + 128-hex-digest hash" {
  run run_command bin/cloudfront/v1/generate-basic-auth-password-hash <<< "ExamplePlaceholderPassword"
  assert_success
  assert_line 0 "New basic auth password: "
  [[ "${lines[1]}" =~ $HASH_RE ]] || fail "expected line 2 to match a 192-char hex hash, got: ${lines[1]}"
}

@test "generate-basic-auth-password-hash still produces a well-formed hash for an empty password" {
  run run_command bin/cloudfront/v1/generate-basic-auth-password-hash <<< ""
  assert_success
  [[ "${lines[1]}" =~ $HASH_RE ]] || fail "expected line 2 to match a 192-char hex hash, got: ${lines[1]}"
}

# The salt is drawn from os.urandom, so the same placeholder password produces
# a different hash on every run -- this is the "salted, not deterministic"
# behaviour the task asks to confirm.
@test "generate-basic-auth-password-hash salts: the same password hashes differently each run" {
  run run_command bin/cloudfront/v1/generate-basic-auth-password-hash <<< "ExamplePlaceholderPassword"
  assert_success
  first="${lines[1]}"

  run run_command bin/cloudfront/v1/generate-basic-auth-password-hash <<< "ExamplePlaceholderPassword"
  assert_success
  second="${lines[1]}"

  [ "$first" != "$second" ] || fail "expected two runs of the same password to produce different (salted) hashes"
}
