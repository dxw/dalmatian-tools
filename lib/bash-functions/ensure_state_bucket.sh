#!/usr/bin/env bash
set -e
set -o pipefail

# Apply one of the state bucket's hardening settings.
#
# Shared by the create path (which applies all four unconditionally) and the
# repair path (which applies only what an existing bucket is missing), so the
# argument vector for each setting is defined once.
#
# @usage _ensure_state_bucket_put BUCKET REGION SETTING
function _ensure_state_bucket_put {
  local BUCKET=$1
  local REGION=$2
  local SETTING=$3

  case "$SETTING" in
    "ownership controls")
      aws s3api put-bucket-ownership-controls --bucket "$BUCKET" --region "$REGION" --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]' --profile dalmatian-main
      ;;
    "public access block")
      aws s3api put-public-access-block --bucket "$BUCKET" --region "$REGION" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true --profile dalmatian-main
      ;;
    versioning)
      aws s3api put-bucket-versioning --bucket "$BUCKET" --region "$REGION" --versioning-configuration Status=Enabled --profile dalmatian-main
      ;;
    "default encryption")
      aws s3api put-bucket-encryption --bucket "$BUCKET" --region "$REGION" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' --profile dalmatian-main
      ;;
    *)
      err "Invalid \`_ensure_state_bucket_put\` setting: $SETTING"
      return 1
      ;;
  esac
}

# Check that the S3 bucket configured to hold Terraform state exists, and
# offer to create it (versioned, encrypted, publicly blocked) when it does not
#
# The bucket name and region are read from CONFIG_SETUP_JSON_FILE rather than
# taken as parameters, because every caller (setup, clone -I, initialise)
# already has that file in scope and it is the same source `terraform init`
# itself is configured from
#
# A bucket that exists but cannot be reached with the dalmatian-main profile
# is reported rather than offered for creation, since state buckets are
# per-project and this almost always means the name belongs to someone else's
#
# An existing bucket is also checked for versioning, default encryption and a
# public access block, because `create-bucket` succeeding on an earlier run is
# no guarantee the later `put-*` calls that harden it did too. Ownership
# controls are not part of that check: they only affect how new objects are
# owned, so a bucket missing them is not a live weakness the way the other
# three are.
#
# @usage ensure_state_bucket [-y]
# @param -y  Create the bucket, or apply missing settings to an existing one, without asking
# @return 0 if the bucket exists (optionally after repairing it) or was created, 1 otherwise
function ensure_state_bucket {
  local BUCKET
  local REGION
  local ASSUME_YES
  local HEAD_OUTPUT
  local MAIN_ACCOUNT_ID
  local opt
  local MISSING
  local setting
  local VERSIONING_OUTPUT
  local PAB_OUTPUT
  local ENCRYPTION_OUTPUT

  ASSUME_YES="${DALMATIAN_ASSUME_YES:-0}"

  OPTIND=1
  while getopts "y" opt; do
    case $opt in
      y)
        ASSUME_YES=1
        ;;
      *)
        echo "Invalid \`ensure_state_bucket\` function usage" >&2
        return 1
        ;;
    esac
  done

  BUCKET="$(jq -r '.backend.s3.bucket_name // empty' < "$CONFIG_SETUP_JSON_FILE")"
  REGION="$(jq -r '.backend.s3.bucket_region // empty' < "$CONFIG_SETUP_JSON_FILE")"

  if [ -z "$BUCKET" ] || [ -z "$REGION" ]
  then
    die "No Terraform state bucket is configured. Run \`dalmatian setup\`"
  fi

  if HEAD_OUTPUT="$(aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" --profile dalmatian-main 2>&1)"
  then
    MISSING=()

    # Each lookup is judged on its own status and error text: only a
    # successful read that shows the setting off, or the specific "not
    # configured" error, counts as missing. A denied or failed read is
    # reported, never treated as an absent setting to be written over.
    if VERSIONING_OUTPUT="$(aws s3api get-bucket-versioning --bucket "$BUCKET" --profile dalmatian-main --region "$REGION" --query 'Status' --output text 2>&1)"
    then
      if [ "$VERSIONING_OUTPUT" != "Enabled" ]
      then
        MISSING+=("versioning")
      fi
    else
      err "Could not read versioning on Terraform state bucket '$BUCKET':"
      err "$VERSIONING_OUTPUT"
      return 1
    fi

    if PAB_OUTPUT="$(aws s3api get-public-access-block --bucket "$BUCKET" --profile dalmatian-main --region "$REGION" --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' --output text 2>&1)"
    then
      if [ "$PAB_OUTPUT" != $'True\tTrue\tTrue\tTrue' ]
      then
        MISSING+=("public access block")
      fi
    else
      case "$PAB_OUTPUT" in
        *NoSuchPublicAccessBlockConfiguration*)
          MISSING+=("public access block")
          ;;
        *)
          err "Could not read the public access block on Terraform state bucket '$BUCKET':"
          err "$PAB_OUTPUT"
          return 1
          ;;
      esac
    fi

    if ENCRYPTION_OUTPUT="$(aws s3api get-bucket-encryption --bucket "$BUCKET" --region "$REGION" --profile dalmatian-main 2>&1)"
    then
      :
    else
      case "$ENCRYPTION_OUTPUT" in
        *ServerSideEncryptionConfigurationNotFoundError*)
          MISSING+=("default encryption")
          ;;
        *)
          err "Could not read the default encryption on Terraform state bucket '$BUCKET':"
          err "$ENCRYPTION_OUTPUT"
          return 1
          ;;
      esac
    fi

    if [ "${#MISSING[@]}" -eq 0 ]
    then
      log_info -l "Terraform state bucket '$BUCKET' exists" -q "$QUIET_MODE"
      return 0
    fi

    warning "Terraform state bucket '$BUCKET' exists but is missing: ${MISSING[*]}"
    log_msg -l "State buckets should have versioning on, default encryption and all public access blocked" -q "$QUIET_MODE"

    if [ "$ASSUME_YES" != 1 ] && ! yes_no "Apply the missing settings now? (y/N)" "N"
    then
      err "Nothing changed. Re-run \`dalmatian terraform-dependencies initialise\` and answer y to apply them, or fix the bucket by hand"
      return 1
    fi

    for setting in "${MISSING[@]}"
    do
      _ensure_state_bucket_put "$BUCKET" "$REGION" "$setting"
    done
    log_info -l "Applied the missing settings to '$BUCKET'" -q "$QUIET_MODE"

    return 0
  fi

  case "$HEAD_OUTPUT" in
    *404*|*"Not Found"*)
      ;;
    *403*|*Forbidden*)
      err "Terraform state bucket '$BUCKET' exists but the dalmatian-main profile cannot access it"
      err "It may belong to another AWS account; state buckets are per project, so choose a different name with \`dalmatian setup\`"
      return 1
      ;;
    *)
      err "Could not check the Terraform state bucket '$BUCKET':"
      err "$HEAD_OUTPUT"
      return 1
      ;;
  esac

  warning "Terraform state bucket '$BUCKET' does not exist in the main Dalmatian account"
  log_msg -l "Dalmatian keeps its Terraform state in this bucket; nothing can be deployed until it exists" -q "$QUIET_MODE"

  if [ "$ASSUME_YES" != 1 ] && ! yes_no "Create it now in region $REGION with versioning, encryption and public access blocked? (y/N)" "N"
  then
    # A raw `aws` command would only be right inside the tool's environment,
    # where AWS_CONFIG_FILE and the dalmatian-main profile are set, so point
    # at the tool or at the console rather than print one
    MAIN_ACCOUNT_ID="$(jq -r '.main_dalmatian_account_id // empty' < "$CONFIG_SETUP_JSON_FILE")"
    err "Nothing created. To let Dalmatian create it, re-run \`dalmatian terraform-dependencies initialise\` and answer y"
    err "To create it yourself: bucket '$BUCKET' in region $REGION of the main Dalmatian account${MAIN_ACCOUNT_ID:+ ($MAIN_ACCOUNT_ID)}, with versioning on, default encryption and all public access blocked; then re-run initialise (see README-in-development.md, Prerequisites)"
    return 1
  fi

  log_info -l "Creating Terraform state bucket '$BUCKET' in $REGION ..." -q "$QUIET_MODE"
  if [ "$REGION" == "us-east-1" ]
  then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" --profile dalmatian-main > /dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" --create-bucket-configuration "LocationConstraint=$REGION" --profile dalmatian-main > /dev/null
  fi
  _ensure_state_bucket_put "$BUCKET" "$REGION" "ownership controls"
  _ensure_state_bucket_put "$BUCKET" "$REGION" "public access block"
  _ensure_state_bucket_put "$BUCKET" "$REGION" "versioning"
  _ensure_state_bucket_put "$BUCKET" "$REGION" "default encryption"
  log_info -l "Created Terraform state bucket '$BUCKET'" -q "$QUIET_MODE"

  return 0
}
