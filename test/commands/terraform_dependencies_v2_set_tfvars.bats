#!/usr/bin/env bats

load ../test_helper

WORKSPACE="123456789012-eu-west-2-example-account-example-infra-staging"

# These cover the prompt set-tfvars shows when the remote tfvars file differs
# from the locally cached copy. The aws shim serves the "remote" copy by
# writing it to wherever `aws s3 cp` is asked to put it, then hands the call to
# the usual stub so it is still logged. The editor is a shim that records the
# file it was opened on, and the plan and deploy go to the CLI stub.
setup() {
  setup_sandbox
  use_stubs
  stub_cli
  export QUIET_MODE=1
  export CONFIG_CACHE_DIR="$CONFIG_INSTALLATION_DIR/.cache"
  export CONFIG_TFVARS_DIR="$CONFIG_CACHE_DIR/tfvars"
  export CONFIG_TFVARS_PATHS_FILE="$CONFIG_CACHE_DIR/tfvars-paths.json"
  cat > "$CONFIG_SETUP_JSON_FILE" <<'JSON'
{
  "project_name": "example-project",
  "main_dalmatian_account_id": "123456789012",
  "default_region": "eu-west-2"
}
JSON
  mkdir -p "$CONFIG_TFVARS_DIR"
  printf '{}\n' > "$CONFIG_TFVARS_PATHS_FILE"

  LOCAL_TFVARS="$CONFIG_TFVARS_DIR/200-$WORKSPACE.tfvars"
  REMOTE_TFVARS="$SANDBOX/remote.tfvars"
  printf 'instance_count = 2\n' > "$LOCAL_TFVARS"
  printf 'instance_count = 3\n' > "$REMOTE_TFVARS"

  cat > "$SANDBOX/bin/aws" <<SHIM
#!/usr/bin/env bash
if [ "\$1" = s3 ] && [ "\$2" = cp ]
then
  cp "$REMOTE_TFVARS" "\$4"
fi
exec "$DALMATIAN_ROOT/test/stubs/aws" "\$@"
SHIM
  chmod +x "$SANDBOX/bin/aws"

  EDITOR_LOG="$SANDBOX/editor.log"
  cat > "$SANDBOX/bin/fake-editor" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$EDITOR_LOG"
SHIM
  chmod +x "$SANDBOX/bin/fake-editor"
  export EDITOR="$SANDBOX/bin/fake-editor"
}

set_tfvars() {
  run --separate-stderr run_command bin/terraform-dependencies/v2/set-tfvars -i "$WORKSPACE" <<< "$1"
}

assert_editor_opened() {
  [ -f "$EDITOR_LOG" ] || fail "expected the editor to be opened"
  run cat "$EDITOR_LOG"
  assert_output "$LOCAL_TFVARS"
}

refute_editor_opened() {
  [ ! -f "$EDITOR_LOG" ] || fail "expected the editor not to be opened, but it was: $(cat "$EDITOR_LOG")"
}

assert_temp_removed() {
  local leftover
  leftover="$(find "$CONFIG_TFVARS_DIR" -name 'temp-diff-check.*' ! -name 'temp-diff-check.tfvars')"
  [ -z "$leftover" ] || fail "expected the temporary remote copy to be removed, found: $leftover"
}

@test "set-tfvars opens the editor without prompting when the remote matches the local copy" {
  cp "$LOCAL_TFVARS" "$REMOTE_TFVARS"
  set_tfvars "n"
  assert_success
  refute_output_line "6) Abort"
  assert_editor_opened
  assert_temp_removed
}

@test "set-tfvars offers to apply either copy or abort when the copies differ" {
  set_tfvars "6"
  assert_success
  assert_line 0 "1) Edit my local copy"
  assert_line 1 "2) Use the remote copy and edit"
  assert_line 2 "3) Show the diff"
  assert_line 3 "4) Apply my local copy"
  assert_line 4 "5) Apply the remote copy"
  assert_line 5 "6) Abort"
}

@test "set-tfvars shows a labelled diff and then asks again" {
  set_tfvars $'3\n6'
  assert_success
  assert_output_contains "--- remote"
  assert_output_contains "+++ local"
  assert_output_contains "-instance_count = 3"
  assert_output_contains "+instance_count = 2"
  run grep -c '^6) Abort$' <<< "$output"
  assert_output "2"
}

@test "set-tfvars carries on after the diff with the copy then chosen" {
  set_tfvars $'3\n4\nn'
  assert_success
  assert_stub_called_with "dalmatian deploy infrastructure -w $WORKSPACE -p"
  assert_temp_removed
}

@test "set-tfvars edits the local copy for option 1" {
  set_tfvars $'1\nn'
  assert_success
  assert_editor_opened
  run cat "$LOCAL_TFVARS"
  assert_output "instance_count = 2"
  assert_temp_removed
}

@test "set-tfvars replaces the local copy with the remote and edits it for option 2" {
  set_tfvars $'2\nn'
  assert_success
  assert_editor_opened
  run cat "$LOCAL_TFVARS"
  assert_output "instance_count = 3"
  assert_temp_removed
}

@test "set-tfvars plans the local copy without editing it for option 4" {
  set_tfvars $'4\nn'
  assert_success
  refute_editor_opened
  run cat "$LOCAL_TFVARS"
  assert_output "instance_count = 2"
  assert_stub_called_with "dalmatian deploy infrastructure -w $WORKSPACE -p"
  assert_temp_removed
}

@test "set-tfvars plans the remote copy without editing it for option 5" {
  set_tfvars $'5\nn'
  assert_success
  refute_editor_opened
  run cat "$LOCAL_TFVARS"
  assert_output "instance_count = 3"
  assert_stub_called_with "dalmatian deploy infrastructure -w $WORKSPACE -p"
  assert_temp_removed
}

@test "set-tfvars deploys the applied copy when the deploy is confirmed" {
  set_tfvars $'4\ny'
  assert_success
  assert_call_args dalmatian deploy infrastructure -w "$WORKSPACE"
}

@test "set-tfvars aborts without editing, planning or changing anything for option 6" {
  set_tfvars "6"
  assert_success
  refute_editor_opened
  refute_stub_called_with "dalmatian deploy"
  run cat "$LOCAL_TFVARS"
  assert_output "instance_count = 2"
  assert_temp_removed
}

@test "set-tfvars asks again after an unrecognised answer" {
  set_tfvars $'9\n6'
  assert_success
  assert_stderr_contains "Invalid selection"
  refute_stub_called_with "dalmatian deploy"
  assert_temp_removed
}

@test "set-tfvars fails and removes the remote copy when the prompt gets no answer" {
  run --separate-stderr run_command bin/terraform-dependencies/v2/set-tfvars -i "$WORKSPACE" < /dev/null
  assert_failure 1
  assert_stderr_contains "No selection made"
  refute_editor_opened
  refute_stub_called_with "dalmatian deploy"
  assert_temp_removed
}

@test "set-tfvars uses the remote copy without prompting when there is no local copy" {
  rm "$LOCAL_TFVARS"
  set_tfvars "n"
  assert_success
  refute_output_line "6) Abort"
  assert_editor_opened
  run cat "$LOCAL_TFVARS"
  assert_output "instance_count = 3"
  assert_temp_removed
}

@test "set-tfvars leaves another run's temporary copy alone" {
  printf 'other run\n' > "$CONFIG_TFVARS_DIR/temp-diff-check.tfvars"
  set_tfvars "6"
  assert_success
  run cat "$CONFIG_TFVARS_DIR/temp-diff-check.tfvars"
  assert_output "other run"
  assert_temp_removed
}
