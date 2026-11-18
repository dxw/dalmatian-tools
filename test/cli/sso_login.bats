#!/usr/bin/env bats
#
# An expired AWS SSO session is refreshed by the dispatcher before a command
# runs. `aws sso login` prints its browser prompt to stdout, so if that ever
# reaches a caller's stdout it corrupts whatever the caller is capturing --
# resolve_aws_profile's `dalmatian deploy list-infrastructures` JSON, for one.

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  use_test_app_root
  login_sandbox
  printf '{"version": "v2"}\n' > "$CONFIG_DIR/version.json"

  mkdir -p "$SANDBOX/app/bin/deploy/v2"
  printf '#!/usr/bin/env bash\ncat "%s"\n' "$DALMATIAN_ROOT/test/fixtures/list-infrastructures.json" \
    > "$SANDBOX/app/bin/deploy/v2/list-infrastructures"
  chmod +x "$SANDBOX/app/bin/deploy/v2/list-infrastructures"

  stub_response aws-configure-list_profiles <<'PROFILES'
dalmatian-main
example-account
PROFILES

  expire_sso_session
}

# Backdate the cached session, and put an `aws` ahead of the stubs that answers
# `aws sso login` the way the real one does: prompt on stdout, fresh cache file.
# Everything else falls through to the ordinary stub.
expire_sso_session() {
  printf '{"startUrl": "https://example.awsapps.com/start", "expiresAt": "2000-01-01T00:00:00Z"}\n' \
    > "$HOME/.aws/sso/cache/session.json"

  cat > "$SANDBOX/bin/aws" <<STUB
#!/usr/bin/env bash
if [ "\$1 \$2" = "sso login" ]
then
  printf 'aws %s\n' "\$*" >> "\$DALMATIAN_STUB_LOG"
  printf 'Attempting to automatically open the SSO authorization page in your default browser.\n'
  printf '{"startUrl": "https://example.awsapps.com/start", "expiresAt": "%s"}\n' \
    "\$(gdate -u -d '+8 hours' '+%Y-%m-%dT%H:%M:%SZ')" > "\$HOME/.aws/sso/cache/session.json"
  exit 0
fi
exec "$DALMATIAN_ROOT/test/stubs/aws" "\$@"
STUB
  chmod +x "$SANDBOX/bin/aws"
}

@test "aws login keeps the aws sso login prompt off stdout" {
  run --separate-stderr "$TEST_DALMATIAN" aws login -q
  assert_success
  assert_stub_called_with "aws sso login"
  assert_output ""
  assert_stderr_contains "Attempting to automatically open the SSO authorization page"
}

@test "resolve_aws_profile resolves the profile on an expired session" {
  load_all_functions
  export APP_ROOT="$SANDBOX/app"

  run --separate-stderr resolve_aws_profile -i "example-infra" -e "staging"
  assert_success
  assert_stub_called_with "aws sso login"
  assert_output "example-account"
}
