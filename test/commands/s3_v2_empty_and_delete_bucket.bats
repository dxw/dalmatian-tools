#!/usr/bin/env bats

load ../test_helper

# empty-and-delete-bucket is the most dangerous command under test in this
# suite: it recursively empties and then deletes an S3 bucket. Every test
# here either proves the destructive calls target exactly the bucket named on
# the command line, or proves that no destructive call happens at all
# (validation failure, or a declined confirmation prompt).

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  # Answers every list-object-versions call with no versions and no delete
  # markers, so a confirmed run reaches delete-bucket without needing the
  # paginated delete-objects loop.
  stub_response_file dalmatian-aws-run_command-p-example_account-s3api-list_object_versions v2-s3-object-versions-empty.json
}

@test "empty-and-delete-bucket prints usage with no arguments" {
  # usage() sends only its first line to stderr; the option list (lines
  # 9-12 of the script) is plain \`echo\`, so it lands on stdout.
  run --separate-stderr run_command bin/s3/v2/empty-and-delete-bucket
  assert_failure 1
  assert_stderr_contains "Usage: empty-and-delete-bucket"
  assert_output_contains "-b <bucket_name>"
}

@test "empty-and-delete-bucket requires an infrastructure, performing no delete" {
  run --separate-stderr run_command bin/s3/v2/empty-and-delete-bucket -e "staging" -b "example-bucket"
  assert_failure 1
  assert_stderr_contains "Usage: empty-and-delete-bucket"
  refute_stub_called_with "s3 rm"
  refute_stub_called_with "delete-bucket"
}

@test "empty-and-delete-bucket requires an environment, performing no delete" {
  run --separate-stderr run_command bin/s3/v2/empty-and-delete-bucket -i "example-infra" -b "example-bucket"
  assert_failure 1
  assert_stderr_contains "Usage: empty-and-delete-bucket"
  refute_stub_called_with "s3 rm"
  refute_stub_called_with "delete-bucket"
}

@test "empty-and-delete-bucket -h shows usage, performing no delete" {
  run --separate-stderr run_command bin/s3/v2/empty-and-delete-bucket -h
  assert_failure 1
  assert_stderr_contains "Usage: empty-and-delete-bucket"
  refute_stub_called_with "s3 rm"
  refute_stub_called_with "delete-bucket"
}

@test "empty-and-delete-bucket fails when no AWS profile matches, performing no delete" {
  stub_response aws-configure-list_profiles "dalmatian-main"

  run --separate-stderr run_command bin/s3/v2/empty-and-delete-bucket -i "example-infra" -e "staging" -b "example-bucket" <<< "y"
  assert_failure
  assert_stderr_contains "Profile does not exist for example-infra staging"
  refute_stub_called_with "s3 rm"
  refute_stub_called_with "delete-bucket"
}

@test "declining the confirmation prompt performs no delete at all" {
  run run_command bin/s3/v2/empty-and-delete-bucket -i "example-infra" -e "staging" -b "example-bucket" <<< "n"
  assert_success
  refute_stub_called_with "s3 rm"
  refute_stub_called_with "s3api delete-bucket"
  refute_stub_called_with "s3api list-object-versions"
  refute_stub_called_with "s3api delete-objects"
}

@test "confirming empties and deletes exactly the named bucket, and no other" {
  run run_command bin/s3/v2/empty-and-delete-bucket -i "example-infra" -e "staging" -b "example-bucket" <<< "y"
  assert_success
  assert_stub_called_with "s3 rm s3://example-bucket --recursive"
  assert_stub_called_with "s3api list-object-versions --bucket example-bucket"
  assert_stub_called_with "s3api delete-bucket --bucket example-bucket"
  refute_stub_called_with "example-bucket-two"
  refute_stub_called_with "example-bucket/"
}

@test "confirming with a similarly-named bucket does not touch the original" {
  run run_command bin/s3/v2/empty-and-delete-bucket -i "example-infra" -e "staging" -b "example-bucket-two" <<< "y"
  assert_success
  assert_stub_called_with "s3 rm s3://example-bucket-two --recursive"
  assert_stub_called_with "s3api delete-bucket --bucket example-bucket-two"
  refute_stub_called_with "s3 rm s3://example-bucket --recursive"
  refute_stub_called_with "delete-bucket --bucket example-bucket "
}

@test "removes a page of object versions before deleting the bucket" {
  stub_response_file dalmatian-aws-run_command-p-example_account-s3api-list_object_versions v2-s3-object-versions-two.json

  run run_command bin/s3/v2/empty-and-delete-bucket -i "example-infra" -e "staging" -b "example-bucket" <<< "y"
  assert_success
  assert_stub_called_with "s3api delete-objects --bucket example-bucket"
  assert_stub_called_with "s3api delete-bucket --bucket example-bucket"
}

@test "aborts before deleting the bucket when emptying it fails" {
  stub_exit dalmatian-aws-run_command-p-example_account-s3-rm 1

  run --separate-stderr run_command bin/s3/v2/empty-and-delete-bucket -i "example-infra" -e "staging" -b "example-bucket" <<< "y"
  assert_failure
  assert_stub_called_with "s3 rm s3://example-bucket --recursive"
  refute_stub_called_with "delete-bucket"
}

# --- SECURITY: BUCKET_NAME (-b) is never validated as required ------------
#
# Unlike -i and -e, whose absence is caught by the `-z` check before the
# script does anything, -b is entirely optional (per its own usage text,
# copied verbatim from list-bucket-properties -- "optional, by default goes
# through all s3 buckets"). But unlike list-bucket-properties, this script
# has no "loop over every bucket" fallback for an empty BUCKET_NAME: with -b
# omitted (or given as an empty string), $BUCKET_NAME is simply "", and every
# destructive call below is built directly from it with no non-empty check:
#   "$APP_ROOT/bin/dalmatian" aws run-command -p "$PROFILE" \
#     s3 rm "s3://$BUCKET_NAME" --recursive
#   ... s3api delete-bucket --bucket "$BUCKET_NAME"
# That constructs `s3 rm s3:// --recursive` and, ultimately,
# `s3api delete-bucket --bucket ""` -- a real `aws` CLI would very likely
# reject `s3://` as a malformed URI, but nothing in *this script* stops it
# from being sent. There is no local guard against an empty or partial
# bucket name reaching the delete path. This is flagged here, not fixed.

@test "SECURITY: omitting -b does not fail validation, and the empty name reaches the delete calls" {
  run run_command bin/s3/v2/empty-and-delete-bucket -i "example-infra" -e "staging" <<< "y"
  refute_output_line "Usage: empty-and-delete-bucket"
  assert_call_args dalmatian aws run-command -p example-account s3 rm "s3://" --recursive
  assert_call_args dalmatian aws run-command -p example-account s3api delete-bucket --bucket ""
}

@test "SECURITY: an explicit empty -b '' behaves identically to omitting -b" {
  run run_command bin/s3/v2/empty-and-delete-bucket -i "example-infra" -e "staging" -b "" <<< "y"
  refute_output_line "Usage: empty-and-delete-bucket"
  assert_call_args dalmatian aws run-command -p example-account s3 rm "s3://" --recursive
  assert_call_args dalmatian aws run-command -p example-account s3api delete-bucket --bucket ""
}
