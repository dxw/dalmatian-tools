# AWS put-secret (v2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `v2` command `dalmatian aws put-secret` that can add an arbitrary secret to Parameter Store and output its ARN.

**Architecture:** A bash script that resolves the AWS SSO profile, gets the secret value (via flag, stdin, or secure prompt), structures the parameter name path, writes it as a SecureString parameter using SSM, and outputs the ARN of the created parameter.

**Tech Stack:** Bash, AWS CLI, jq.

---

### Task 1: Scaffold the put-secret script

**Files:**
- Create: `bin/aws/v2/put-secret`

- [ ] **Step 1: Create the file with usage and basic argument parsing**

Write this content to `bin/aws/v2/put-secret`:
```bash
#!/usr/bin/env bash

# exit on failures
set -e
set -o pipefail

usage() {
  echo "Usage: $(basename "$0") [OPTIONS]" 1>&2
  echo "This command puts an arbitrary secret into SSM Parameter Store and prints its ARN."
  echo "  -h                     - help"
  echo "  -i <infrastructure>    - infrastructure name"
  echo "  -e <environment>       - environment name (e.g. 'staging' or 'prod')"
  echo "  -n <secret-name>       - name/suffix of the secret"
  echo "  -v <secret-value>      - value of the secret (optional)"
  echo "  -k <kms-key-id>        - KMS key ID or alias (optional, defaults to alias/aws/ssm)"
  exit 1
}

# if there are no arguments passed exit with usage
if [ $# -eq 0 ]
then
 usage
fi

SECRET_VALUE=""
KMS_KEY_ID="alias/aws/ssm"

while getopts "i:e:n:v:k:h" opt; do
  case $opt in
    i)
      INFRASTRUCTURE_NAME=$OPTARG
      ;;
    e)
      ENVIRONMENT=$OPTARG
      ;;
    n)
      SECRET_NAME=$OPTARG
      ;;
    v)
      SECRET_VALUE=$OPTARG
      ;;
    k)
      KMS_KEY_ID=$OPTARG
      ;;
    h)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -z "$INFRASTRUCTURE_NAME" || -z "$ENVIRONMENT" || -z "$SECRET_NAME" ]]
then
  usage
fi

echo "Scaffolded put-secret for $SECRET_NAME in $INFRASTRUCTURE_NAME-$ENVIRONMENT" >&2
```

- [ ] **Step 2: Make the script executable**

Run: `chmod +x bin/aws/v2/put-secret`

- [ ] **Step 3: Run static analysis check**

Run: `./test.sh`
Expected: PASS (no shellcheck errors for the new script)

- [ ] **Step 4: Verify usage output**

Run: `./bin/aws/v2/put-secret -h` 2>&1
Expected: Exit 1, prints the usage message.

- [ ] **Step 5: Commit**

```bash
git add bin/aws/v2/put-secret
git commit -m "feat: scaffold aws v2 put-secret command"
```

---

### Task 2: Implement Profile Resolution and Parameter Name Formatting

**Files:**
- Modify: `bin/aws/v2/put-secret`

- [ ] **Step 1: Add profile resolution and path formatting logic**

Replace the placeholder `echo` at the end of `bin/aws/v2/put-secret` with:
```bash
PROFILE="$(resolve_aws_profile -i "$INFRASTRUCTURE_NAME" -e "$ENVIRONMENT")"

# Strip leading slash if present in the secret name
SECRET_NAME_CLEANED="${SECRET_NAME#/}"

PARAMETER_NAME="/$INFRASTRUCTURE_NAME/$ENVIRONMENT/$SECRET_NAME_CLEANED"

log_info -l "Resolved profile: $PROFILE" -q "$QUIET_MODE"
log_info -l "SSM Parameter Name: $PARAMETER_NAME" -q "$QUIET_MODE"
```

- [ ] **Step 2: Run static analysis check**

Run: `./test.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add bin/aws/v2/put-secret
git commit -m "feat: add profile resolution and path formatting to put-secret"
```

---

### Task 3: Implement Secret Value Gathering (stdin/TTY prompt)

**Files:**
- Modify: `bin/aws/v2/put-secret`

- [ ] **Step 1: Add interactive and non-interactive input handling**

Append to `bin/aws/v2/put-secret`:
```bash
# If value is not provided as an argument, gather it from stdin/prompt
if [ -z "$SECRET_VALUE" ]
then
  if [ -t 0 ]
  then
    # TTY: prompt securely
    echo -n "Enter secret value: " >&2
    read -rs SECRET_VALUE
    echo >&2
  else
    # Non-TTY: read from piped stdin
    read -r SECRET_VALUE
  fi
fi

if [ -z "$SECRET_VALUE" ]
then
  err "Secret value cannot be empty"
  exit 1
fi
```

- [ ] **Step 2: Run static analysis check**

Run: `./test.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add bin/aws/v2/put-secret
git commit -m "feat: implement secret value gathering in put-secret"
```

---

### Task 4: Implement SSM Put Parameter and Retrieval of ARN

**Files:**
- Modify: `bin/aws/v2/put-secret`

- [ ] **Step 1: Append SSM write and get ARN operations**

Append to `bin/aws/v2/put-secret`:
```bash
log_info -l "Storing secret in Parameter Store..." -q "$QUIET_MODE"

"$APP_ROOT/bin/dalmatian" aws run-command \
  -p "$PROFILE" \
  ssm put-parameter \
  --name "$PARAMETER_NAME" \
  --value "$SECRET_VALUE" \
  --type SecureString \
  --key-id "$KMS_KEY_ID" \
  --overwrite >/dev/null

log_info -l "Retrieving parameter ARN..." -q "$QUIET_MODE"

ARN=$("$APP_ROOT/bin/dalmatian" aws run-command \
  -p "$PROFILE" \
  ssm get-parameter \
  --name "$PARAMETER_NAME" \
  --query "Parameter.ARN" \
  --output text)

echo "$ARN"
```

- [ ] **Step 2: Run static analysis check**

Run: `./test.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add bin/aws/v2/put-secret
git commit -m "feat: complete ssm write and ARN output logic in put-secret"
```

---

### Task 5: Final Verification

- [ ] **Step 1: Verify the command lists correctly**

Run: `dalmatian -l | grep put-secret`
Expected: `put-secret` is displayed under `aws`.

- [ ] **Step 2: Run test.sh to verify no shellcheck regressions**

Run: `./test.sh`
Expected: Clean exit 0 with no errors.
