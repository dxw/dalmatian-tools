#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  stub_response_file dalmatian-service-list_services v2-service-details.json
  stub_response dalmatian-aws-run_command-p-example_account-s3api-head_object '{"ContentLength": 42}'

  # CI has no colordiff; plain diff is all the script needs from it
  printf '#!/usr/bin/env bash\nexec diff "$@"\n' > "$SANDBOX/bin/colordiff"
  chmod +x "$SANDBOX/bin/colordiff"

  # `aws s3 cp` moves real files, which the stub cannot: download writes the
  # remote content to the local path, upload keeps a copy to assert on. The
  # call is still passed to the stub so it is logged
  printf 'EXISTING_VAR=1\n' > "$SANDBOX/remote.env"
  # _dispatch keys its responses by the name it is invoked as
  mkdir -p "$SANDBOX/stub-cli"
  ln -sfn "$DALMATIAN_ROOT/test/stubs/_dispatch" "$SANDBOX/stub-cli/dalmatian"
  rm "$SANDBOX/cli/bin/dalmatian"
  cat > "$SANDBOX/cli/bin/dalmatian" <<SHIM
#!/usr/bin/env bash
if [ "\$1 \$2" == "aws run-command" ] && [ "\$5 \$6" == "s3 cp" ]
then
  case "\$7" in
    s3://*) cp "$SANDBOX/remote.env" "\$8" ;;
    *) cp "\$7" "$SANDBOX/uploaded.env" ;;
  esac
fi
exec "$SANDBOX/stub-cli/dalmatian" "\$@"
SHIM
  chmod +x "$SANDBOX/cli/bin/dalmatian"

  # The editor appends a line unless told not to, and records where it was
  # pointed and how private that directory was
  cat > "$SANDBOX/bin/editor" <<EDITOR
#!/usr/bin/env bash
printf '%s\n' "\$1" > "$SANDBOX/edited-path"
ls -ld "\$(dirname "\$1")" | cut -c1-10 > "$SANDBOX/edited-dir-mode"
ls -l "\$1" | cut -c1-10 > "$SANDBOX/edited-file-mode"
[ -n "\${EDITOR_NO_CHANGE:-}" ] || printf 'NEW_VAR=2\n' >> "\$1"
EDITOR
  chmod +x "$SANDBOX/bin/editor"
  export EDITOR="$SANDBOX/bin/editor"
}

edited_path() {
  cat "$SANDBOX/edited-path"
}

@test "set-environment-variables prints usage with no arguments" {
  run --separate-stderr run_command bin/service/v2/set-environment-variables
  assert_failure 1
  assert_stderr_contains "Usage: set-environment-variables"
}

@test "set-environment-variables edits a private copy outside the checkout and uploads the change" {
  # Upload yes, redeploy no
  run run_command bin/service/v2/set-environment-variables -i "example-infra" -e "staging" -s "example-service" < <(printf 'y\nn\n')
  assert_success

  case "$(edited_path)" in
    "$DALMATIAN_ROOT"/*) fail "edited inside the checkout: $(edited_path)" ;;
  esac
  [ "$(basename "$(edited_path)")" == "example-infra-staging-example-service.env" ]
  [ "$(cat "$SANDBOX/edited-dir-mode")" == "drwx------" ]
  [ "$(cat "$SANDBOX/edited-file-mode")" == "-rw-------" ]
  [ "$(cat "$SANDBOX/uploaded.env")" == "$(printf 'EXISTING_VAR=1\nNEW_VAR=2')" ]
  assert_stub_called_with "s3 cp $(edited_path) s3://example-bucket/example-service.env"
}

@test "set-environment-variables leaves nothing behind after uploading" {
  run run_command bin/service/v2/set-environment-variables -i "example-infra" -e "staging" -s "example-service" < <(printf 'y\nn\n')
  assert_success
  [ ! -e "$(dirname "$(edited_path)")" ] || fail "work directory left behind"
}

@test "set-environment-variables leaves nothing behind when the change is declined" {
  run run_command bin/service/v2/set-environment-variables -i "example-infra" -e "staging" -s "example-service" < <(printf 'n\n')
  assert_success
  refute_stub_called_with "s3 cp $(edited_path)"
  [ ! -e "$(dirname "$(edited_path)")" ] || fail "work directory left behind"
}

@test "set-environment-variables leaves nothing behind when nothing changed" {
  EDITOR_NO_CHANGE=1 run run_command bin/service/v2/set-environment-variables -i "example-infra" -e "staging" -s "example-service" < /dev/null
  assert_success
  refute_stub_called_with "s3 cp $(edited_path)"
  [ ! -e "$(dirname "$(edited_path)")" ] || fail "work directory left behind"
}

@test "set-environment-variables leaves nothing behind when the upload fails" {
  # Make only the upload fail: it is the s3 cp whose source is local
  rm "$SANDBOX/cli/bin/dalmatian"
  cat > "$SANDBOX/cli/bin/dalmatian" <<SHIM
#!/usr/bin/env bash
if [ "\$1 \$2" == "aws run-command" ] && [ "\$5 \$6" == "s3 cp" ]
then
  case "\$7" in
    s3://*) cp "$SANDBOX/remote.env" "\$8" ;;
    *) exit 1 ;;
  esac
fi
exec "$SANDBOX/stub-cli/dalmatian" "\$@"
SHIM
  chmod +x "$SANDBOX/cli/bin/dalmatian"

  run run_command bin/service/v2/set-environment-variables -i "example-infra" -e "staging" -s "example-service" < <(printf 'y\n')
  assert_failure
  [ ! -e "$(dirname "$(edited_path)")" ] || fail "work directory left behind"
}

@test "set-environment-variables creates a new env file when none exists and the user agrees" {
  rm "$DALMATIAN_STUB_RESPONSES/dalmatian-aws-run_command-p-example_account-s3api-head_object.out"

  # Create yes, upload yes, redeploy no
  run run_command bin/service/v2/set-environment-variables -i "example-infra" -e "staging" -s "example-service" < <(printf 'y\ny\nn\n')
  assert_success
  [ "$(cat "$SANDBOX/uploaded.env")" == "NEW_VAR=2" ]
  refute_stub_called_with "s3 cp s3://example-bucket/example-service.env"
}

@test "set-environment-variables does nothing when no env file exists and the user declines" {
  rm "$DALMATIAN_STUB_RESPONSES/dalmatian-aws-run_command-p-example_account-s3api-head_object.out"

  run run_command bin/service/v2/set-environment-variables -i "example-infra" -e "staging" -s "example-service" < <(printf 'n\n')
  assert_success
  [ ! -e "$SANDBOX/edited-path" ] || fail "the editor was opened"
  refute_stub_called_with "s3 cp"
}

@test "set-environment-variables offers to redeploy after uploading" {
  run run_command bin/service/v2/set-environment-variables -i "example-infra" -e "staging" -s "example-service" < <(printf 'y\ny\n')
  assert_success
  assert_stub_called_with "dalmatian service deploy -i example-infra -e staging -s example-service"
}
