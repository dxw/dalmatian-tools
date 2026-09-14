#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
  export QUIET_MODE=0

  cat <<'JSON' > "$CONFIG_SETUP_JSON_FILE"
{
  "project_name": "example-project",
  "backend": {
    "s3": {
      "bucket_name": "example-tfstate",
      "bucket_region": "eu-west-2"
    }
  }
}
JSON
}

@test "ensure_state_bucket succeeds and does nothing when the bucket exists and is hardened" {
  stub_response aws-s3api-get_bucket_versioning "Enabled"
  stub_response aws-s3api-get_public_access_block "True	True	True	True"
  stub_exit aws-s3api-get_bucket_encryption 0

  run ensure_state_bucket
  assert_success
  assert_output_contains "exists"
  refute_stub_called_with "aws s3api create-bucket"
  refute_stub_called_with "aws s3api put-bucket-versioning"
  refute_stub_called_with "aws s3api put-public-access-block"
  refute_stub_called_with "aws s3api put-bucket-encryption"
}

@test "ensure_state_bucket offers to fix an existing bucket missing versioning only" {
  stub_response aws-s3api-get_bucket_versioning ""
  stub_response aws-s3api-get_public_access_block "True	True	True	True"
  stub_exit aws-s3api-get_bucket_encryption 0

  run ensure_state_bucket -y
  assert_success
  assert_call_args aws s3api put-bucket-versioning --bucket example-tfstate --region eu-west-2 --versioning-configuration Status=Enabled --profile dalmatian-main
  refute_stub_called_with "aws s3api put-public-access-block"
  refute_stub_called_with "aws s3api put-bucket-encryption"
  refute_stub_called_with "aws s3api create-bucket"
}

@test "ensure_state_bucket declines to fix an existing bucket missing everything" {
  stub_response aws-s3api-get_bucket_versioning "None"
  stub_exit aws-s3api-get_public_access_block 254
  stub_response aws-s3api-get_public_access_block "An error occurred (NoSuchPublicAccessBlockConfiguration) when calling the GetPublicAccessBlock operation: The public access block configuration was not found"
  stub_exit aws-s3api-get_bucket_encryption 254
  stub_response aws-s3api-get_bucket_encryption "An error occurred (ServerSideEncryptionConfigurationNotFoundError) when calling the GetBucketEncryption operation: The server side encryption configuration was not found"

  run --separate-stderr ensure_state_bucket <<< "n"
  assert_failure
  assert_stderr_contains "versioning"
  assert_stderr_contains "public access block"
  assert_stderr_contains "default encryption"
  refute_stub_called_with "aws s3api put-bucket-versioning"
  refute_stub_called_with "aws s3api put-public-access-block"
  refute_stub_called_with "aws s3api put-bucket-encryption"
}

@test "ensure_state_bucket applies missing encryption to an existing bucket when answered y" {
  stub_response aws-s3api-get_bucket_versioning "Enabled"
  stub_response aws-s3api-get_public_access_block "True	True	True	True"
  stub_exit aws-s3api-get_bucket_encryption 254
  stub_response aws-s3api-get_bucket_encryption "An error occurred (ServerSideEncryptionConfigurationNotFoundError) when calling the GetBucketEncryption operation: The server side encryption configuration was not found"

  run ensure_state_bucket <<< "y"
  assert_success
  assert_stub_called_with "aws s3api put-bucket-encryption --bucket example-tfstate --region eu-west-2 --server-side-encryption-configuration"
  refute_stub_called_with "BucketKeyEnabled"
}

@test "ensure_state_bucket reports a denied versioning lookup instead of treating it as missing" {
  stub_exit aws-s3api-get_bucket_versioning 254
  stub_response aws-s3api-get_bucket_versioning "An error occurred (AccessDenied) when calling the GetBucketVersioning operation: Access Denied"
  stub_response aws-s3api-get_public_access_block "True	True	True	True"
  stub_exit aws-s3api-get_bucket_encryption 0

  run --separate-stderr ensure_state_bucket -y
  assert_failure 1
  assert_stderr_contains "Could not read versioning on Terraform state bucket 'example-tfstate'"
  assert_stderr_contains "AccessDenied"
  refute_stub_called_with "aws s3api put-bucket-versioning"
}

@test "ensure_state_bucket treats an unconfigured public access block as missing but a denied lookup as an error" {
  stub_response aws-s3api-get_bucket_versioning "Enabled"
  stub_exit aws-s3api-get_public_access_block 254
  stub_response aws-s3api-get_public_access_block "An error occurred (NoSuchPublicAccessBlockConfiguration) when calling the GetPublicAccessBlock operation: The public access block configuration was not found"
  stub_exit aws-s3api-get_bucket_encryption 0

  run ensure_state_bucket -y
  assert_success
  assert_stub_called_with "aws s3api put-public-access-block --bucket example-tfstate"
  refute_stub_called_with "aws s3api put-bucket-versioning"
  refute_stub_called_with "aws s3api put-bucket-encryption"

  stub_response aws-s3api-get_public_access_block "An error occurred (AccessDenied) when calling the GetPublicAccessBlock operation: Access Denied"
  : > "$DALMATIAN_STUB_LOG"

  run --separate-stderr ensure_state_bucket -y
  assert_failure 1
  assert_stderr_contains "Could not read the public access block on Terraform state bucket 'example-tfstate'"
  refute_stub_called_with "aws s3api put-public-access-block"
}

@test "ensure_state_bucket reports a denied encryption lookup instead of treating it as missing" {
  stub_response aws-s3api-get_bucket_versioning "Enabled"
  stub_response aws-s3api-get_public_access_block "True	True	True	True"
  stub_exit aws-s3api-get_bucket_encryption 254
  stub_response aws-s3api-get_bucket_encryption "An error occurred (AccessDenied) when calling the GetBucketEncryption operation: Access Denied"

  run --separate-stderr ensure_state_bucket -y
  assert_failure 1
  assert_stderr_contains "Could not read the default encryption on Terraform state bucket 'example-tfstate'"
  refute_stub_called_with "aws s3api put-bucket-encryption"
}

@test "ensure_state_bucket creates the missing bucket with -y" {
  stub_exit aws-s3api-head_bucket 254
  stub_response aws-s3api-head_bucket "An error occurred (404) when calling the HeadBucket operation: Not Found"

  run ensure_state_bucket -y
  assert_success
  assert_call_args aws s3api head-bucket --bucket example-tfstate --region eu-west-2 --profile dalmatian-main
  assert_call_args aws s3api create-bucket --bucket example-tfstate --region eu-west-2 --create-bucket-configuration LocationConstraint=eu-west-2 --profile dalmatian-main
  assert_stub_called_with "aws s3api put-bucket-versioning --bucket example-tfstate --region eu-west-2 --versioning-configuration Status=Enabled --profile dalmatian-main"
  assert_stub_called_with "aws s3api put-public-access-block --bucket example-tfstate --region eu-west-2 --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true --profile dalmatian-main"
  assert_stub_called_with "aws s3api put-bucket-ownership-controls --bucket example-tfstate --region eu-west-2 --ownership-controls Rules=[{ObjectOwnership=BucketOwnerEnforced}] --profile dalmatian-main"
  assert_stub_called_with "aws s3api put-bucket-encryption --bucket example-tfstate --region eu-west-2 --server-side-encryption-configuration"
  # F9: BucketKeyEnabled only applies to SSE-KMS; AES256 accepts and silently
  # ignores it, so leaving it out avoids implying it does something
  refute_stub_called_with "BucketKeyEnabled"
}

@test "ensure_state_bucket creates the missing bucket when answered y on stdin" {
  stub_exit aws-s3api-head_bucket 254
  stub_response aws-s3api-head_bucket "An error occurred (404) when calling the HeadBucket operation: Not Found"

  run ensure_state_bucket <<< "y"
  assert_success
  assert_stub_called_with "aws s3api create-bucket --bucket example-tfstate"
}

@test "ensure_state_bucket declines to create the bucket when answered n" {
  stub_exit aws-s3api-head_bucket 254
  stub_response aws-s3api-head_bucket "An error occurred (404) when calling the HeadBucket operation: Not Found"

  run --separate-stderr ensure_state_bucket <<< "n"
  assert_failure
  assert_stderr_contains "Nothing created"
  assert_stderr_contains "re-run \`dalmatian terraform-dependencies initialise\` and answer y"
  assert_stderr_contains "bucket 'example-tfstate' in region eu-west-2 of the main Dalmatian account"
  refute_stub_called_with "aws s3api create-bucket"
}

@test "ensure_state_bucket declines to create the bucket on EOF" {
  stub_exit aws-s3api-head_bucket 254
  stub_response aws-s3api-head_bucket "An error occurred (404) when calling the HeadBucket operation: Not Found"

  run ensure_state_bucket < /dev/null
  assert_failure
  refute_stub_called_with "aws s3api create-bucket"
}

@test "ensure_state_bucket omits the location constraint in us-east-1" {
  cat <<'JSON' > "$CONFIG_SETUP_JSON_FILE"
{
  "project_name": "example-project",
  "backend": {
    "s3": {
      "bucket_name": "example-tfstate",
      "bucket_region": "us-east-1"
    }
  }
}
JSON
  stub_exit aws-s3api-head_bucket 254
  stub_response aws-s3api-head_bucket "An error occurred (404) when calling the HeadBucket operation: Not Found"

  run ensure_state_bucket -y
  assert_success
  assert_call_args aws s3api create-bucket --bucket example-tfstate --region us-east-1 --profile dalmatian-main
}

@test "ensure_state_bucket reports a bucket it cannot access as forbidden" {
  stub_exit aws-s3api-head_bucket 254
  stub_response aws-s3api-head_bucket "An error occurred (403) when calling the HeadBucket operation: Forbidden"

  run --separate-stderr ensure_state_bucket -y
  assert_failure
  assert_stderr_contains "cannot access it"
  refute_stub_called_with "aws s3api create-bucket"
}

@test "ensure_state_bucket reports any other check failure" {
  stub_exit aws-s3api-head_bucket 254
  stub_response aws-s3api-head_bucket "Could not connect to the endpoint URL"

  run --separate-stderr ensure_state_bucket -y
  assert_failure
  assert_stderr_contains "Could not connect to the endpoint URL"
  refute_stub_called_with "aws s3api create-bucket"
}

@test "ensure_state_bucket treats DALMATIAN_ASSUME_YES=1 like -y" {
  stub_exit aws-s3api-head_bucket 254
  stub_response aws-s3api-head_bucket "An error occurred (404) when calling the HeadBucket operation: Not Found"

  DALMATIAN_ASSUME_YES=1 run ensure_state_bucket < /dev/null
  assert_success
  assert_stub_called_with "aws s3api create-bucket --bucket example-tfstate"
}

@test "ensure_state_bucket fails when no bucket is configured" {
  cat <<'JSON' > "$CONFIG_SETUP_JSON_FILE"
{
  "project_name": "example-project"
}
JSON

  run --separate-stderr ensure_state_bucket
  assert_failure
  assert_stderr_contains "Run \`dalmatian setup\`"
}
