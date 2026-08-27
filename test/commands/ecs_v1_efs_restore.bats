#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "ecs efs-restore prints usage with no arguments" {
  run --separate-stderr run_command bin/ecs/v1/efs-restore
  assert_failure 1
  assert_stderr_contains "Usage: efs-restore"
  assert_output_contains "full file path from root of the mount"
}

@test "ecs efs-restore requires an environment" {
  run --separate-stderr run_command bin/ecs/v1/efs-restore -i "example-infra" -f "/wp-uploads/example/example-file.jpg"
  assert_failure 1
  assert_stderr_contains "Usage: efs-restore"
}

@test "ecs efs-restore requires a file path" {
  run --separate-stderr run_command bin/ecs/v1/efs-restore -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: efs-restore"
}

@test "ecs efs-restore builds the file system query and restore job from -i/-e/-f" {
  stub_response aws-efs-describe_file_systems "fs-0123456789abcdef0"
  stub_response aws-sts-get_caller_identity "123456789012"
  stub_response_file aws-backup-list_recovery_points_by_resource ecs-more-recovery-points.json

  run run_command bin/ecs/v1/efs-restore -i "example-infra" -e "staging" -f "/wp-uploads/example/example-file.jpg"
  assert_success
  assert_stub_called_with "FileSystems[?Name=='example-infra-staging-shared-storage-efs']"
  assert_stub_called_with "arn:aws:elasticfilesystem:eu-west-2:123456789012:file-system/fs-0123456789abcdef0"
  # The restore always targets the first (latest) recovery point in the list
  assert_stub_called_with "--recovery-point-arn arn:aws:backup:eu-west-2:123456789012:recovery-point:example-recovery-point-1"
  assert_stub_called_with "--iam-role-arn arn:aws:iam::123456789012:role/service-role/AWSBackupDefaultServiceRole"
  assert_stub_called_with "--resource-type EFS"
}

@test "ecs efs-restore errors and does not start a restore job when no file system is found" {
  # aws-efs-describe_file_systems is left unstubbed, so the fake `aws`
  # succeeds silently with no output -- exactly what an empty --output text
  # result looks like.
  run --separate-stderr run_command bin/ecs/v1/efs-restore -i "example-infra" -e "staging" -f "/wp-uploads/example/example-file.jpg"
  assert_failure 1
  assert_stderr_contains "No file system found for the specified name."
  refute_stub_called_with "start-restore-job"
}

@test "ecs efs-restore reports 'no latest recovery point' rather than 'no recovery points' for an empty result" {
  # `RECOVERY_POINTS` only trips the `-z` check on a truly empty string, but a
  # well-formed `--output json` response for zero recovery points is the text
  # "[]" -- non-empty. So an empty result set actually falls through to the
  # `jq '.[0]' == "null"` branch and its different message, not the
  # "No recovery points found" one the empty-array case looks like it should
  # hit. Documenting the actual (only reachable) message here.
  stub_response aws-efs-describe_file_systems "fs-0123456789abcdef0"
  stub_response aws-sts-get_caller_identity "123456789012"
  stub_response_file aws-backup-list_recovery_points_by_resource ecs-more-recovery-points-empty.json

  run --separate-stderr run_command bin/ecs/v1/efs-restore -i "example-infra" -e "staging" -f "/wp-uploads/example/example-file.jpg"
  assert_failure 1
  assert_stderr_contains "No latest recovery point found for the specified file system."
  refute_stub_called_with "start-restore-job"
}
