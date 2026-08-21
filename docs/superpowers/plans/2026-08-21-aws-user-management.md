# `list-users` and `remove-user` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `dalmatian aws list-users` and `dalmatian aws remove-user`, and extract the Identity Center machinery `add-user` already has into `lib/bash-functions/` so all three share one implementation.

**Architecture:** Eight new single-function files in `lib/bash-functions/`, auto-sourced and exported by `bin/dalmatian`. `bin/aws/v2/add-user` is refactored to consume them. Two new commands are then thin scripts over the shared functions plus their own logic.

**Tech Stack:** Bash 4+, `aws` CLI v2 (`identitystore`, `sso-admin`, `organizations`), `jq`, `shellcheck`.

**Spec:** `docs/superpowers/specs/2026-08-21-aws-user-management-design.md`. Read it first, and the earlier `2026-08-20-aws-add-user-design.md` for the profile mechanism. Where plan and spec disagree, the spec wins.

## Global Constraints

- **Extracted functions MUST be declared `function foo {`, not `foo() {`.** `bin/dalmatian:90`
  finds what to export with `grep "^function" "$file" | cut -d" " -f2`. The parenthesis form is
  sourced but never exported, so the command subprocess will not see it. This is the single most
  likely way to get this wrong, and it fails at runtime, not at lint time.
- **One function per file** in `lib/bash-functions/`. All 18 existing files follow this without
  exception.
- **Extracted functions must not call `aws_admin`.** That wrapper is defined per-command. Shared
  functions call `aws --profile "$IDENTITY_CENTER_PROFILE"` directly. Each command still defines
  its own `aws_admin` for its own calls.
- **`list-users` output goes to stdout with `printf`, never `esc_msg`.** The table is the
  payload. `bin/dalmatian:49-52` forces `QUIET_MODE=1` when stdout is not a TTY, so `log_msg`
  would make `dalmatian aws list-users | grep DISABLED` print nothing. Precedent:
  `bin/aws/v2/list-profiles` and `bin/deploy/v2/list-accounts` both use bare `echo`.
- **Status messages that are not payload still use `esc_info`/`esc_msg`** so they stay
  suppressed when piped and cannot corrupt the table or the JSON.
- **Never split tab-separated fields with `IFS=$'\t' read`.** Tab is IFS *whitespace*, so bash
  collapses empty adjacent fields and shifts every later field left. Both new commands have
  legitimately empty fields (no email, no groups). Use `$'\x1f'` as the separator, which is
  non-whitespace and therefore preserves empty fields.
- **`./test.sh` must exit 0 after every task**, with no new `# shellcheck disable=` comments.
- **No unit tests.** The toolkit has no framework; shellcheck plus named manual checks is the
  test cycle. This is a standing decision from the previous change.
- **`add-user`'s full verification matrix is deliberately NOT repeated** after the refactor. The
  repo owner asked for lint plus a smoke test only.
- **Ask before committing.** One squashed commit at the end, matching how the previous change
  was landed.

## File Structure

| File | Change | Responsibility |
| --- | --- | --- |
| `lib/bash-functions/die.sh` | Create | `err` then `exit 1` |
| `lib/bash-functions/esc_msg.sh` | Create | `log_msg` + backslash escaping + `-q "$QUIET_MODE"` |
| `lib/bash-functions/esc_info.sh` | Create | as above for `log_info` |
| `lib/bash-functions/load_aws_sso_setup.sh` | Create | read `aws_sso.*` from setup.json; set `CONSOLE_USERS_URL` |
| `lib/bash-functions/aws_profile_exists.sh` | Create | exact-match profile lookup |
| `lib/bash-functions/resolve_identity_center_profile.sh` | Create | resolve/derive the admin profile and verify it authenticates |
| `lib/bash-functions/identity_center_instance.sh` | Create | set `INSTANCE_ARN` and `IDENTITY_STORE_ID` |
| `lib/bash-functions/require_visible_plan.sh` | Create | refuse to prompt when the plan is hidden |
| `bin/aws/v2/add-user` | Modify | drop the extracted functions, call the shared ones |
| `bin/aws/v2/list-users` | Create | list users with status and groups |
| `bin/aws/v2/remove-user` | Create | tear down access and delete a user |

---

### Task 1: Extract the shared functions into `lib/bash-functions/`

Creates the eight files. Nothing consumes them yet, so `add-user` keeps working unchanged
throughout this task — its own copies still take precedence because they are defined in the
script itself, after the exported versions are inherited.

**Files:** the eight `lib/bash-functions/*.sh` files above.

**Interfaces:**
- Consumes: `err`, `warning`, `log_msg`, `log_info` (existing lib functions); `$QUIET_MODE`,
  `$CONFIG_SETUP_JSON_FILE`, `$CONFIG_AWS_SSO_FILE`, `$AWS_CONFIG_FILE` (dispatcher exports);
  `append_sso_config_file` (existing lib function).
- Produces: `die <msg>`; `esc_msg <line>`; `esc_info <line>`; `load_aws_sso_setup` setting
  `AWS_SSO_START_URL`, `AWS_SSO_REGION`, `AWS_SSO_ADMIN_ROLE_NAME`, `CONSOLE_USERS_URL`;
  `aws_profile_exists <name>` returning 0/1; `resolve_identity_center_profile` reading
  `PROFILE_OVERRIDE` and `IDENTITY_CENTER_PROFILE_NAME` and setting `IDENTITY_CENTER_PROFILE`;
  `identity_center_instance` setting `INSTANCE_ARN` and `IDENTITY_STORE_ID`;
  `require_visible_plan <assume_yes> <dry_run>`.

- [ ] **Step 1: Confirm the starting state**

```bash
cd /Users/bob/git/dxw/dalmatian-tools
git branch --show-current && git status --short && ./test.sh && echo "BASELINE OK"
```

Expected: `add-aws-sso-user`, a clean tree apart from the untracked files that were already
there, then `BASELINE OK`.

- [ ] **Step 2: Create `lib/bash-functions/die.sh`**

```bash
#!/usr/bin/env bash
set -e
set -o pipefail

# Report a fatal error and exit.
#
# `err` prints in red to stderr but does not exit, so commands that want to
# abort need this wrapper rather than a bare `err` call.
#
# @usage die "could not find the thing"
# @param $1 The error message
function die {
  err "$1"
  exit 1
}
```

- [ ] **Step 3: Create `lib/bash-functions/esc_msg.sh`**

```bash
#!/usr/bin/env bash
set -e
set -o pipefail

# Output a plain message, escaped so `echo -e` cannot reinterpret it.
#
# `log_msg` renders with `echo -e`, which interprets backslash escapes. AWS
# Organizations permits any printable ASCII in an account name, backslash
# included, and Identity Center is similarly permissive about group and
# permission set names. An unescaped name therefore mangles the line it appears
# in, and a name containing `\c` truncates the line outright — dropping, for
# example, the account ID an operator is meant to be checking before they
# approve a change. Doubling backslashes makes `echo -e` emit them literally.
#
# This also supplies `-q "$QUIET_MODE"`, which `log_msg` assigns to as a side
# effect: omitting it silently resets quiet mode to 0 for the rest of the run.
#
# @usage esc_msg "    ADD    grant 'admin' on some-account (123456789012)"
# @param $1 The line to output
function esc_msg {
  log_msg -l "${1//\\/\\\\}" -q "$QUIET_MODE"
}
```

- [ ] **Step 4: Create `lib/bash-functions/esc_info.sh`**

```bash
#!/usr/bin/env bash
set -e
set -o pipefail

# Output a `==>` progress message, escaped so `echo -e` cannot reinterpret it.
# See esc_msg.sh for why the escaping and the -q are both necessary.
#
# @usage esc_info "Creating user someone@example.com"
# @param $1 The line to output
function esc_info {
  log_info -l "${1//\\/\\\\}" -q "$QUIET_MODE"
}
```

- [ ] **Step 5: Create `lib/bash-functions/load_aws_sso_setup.sh`**

```bash
#!/usr/bin/env bash
set -e
set -o pipefail

# Read the AWS SSO values needed to talk to IAM Identity Center out of
# setup.json, and derive the console URL from the Identity Center region.
#
# Every value is checked. `jq -r` prints the literal string "null" for a missing
# field, which would otherwise be built into an SSO profile or a URL and only
# fail much later as an opaque AWS error.
#
# @usage load_aws_sso_setup
# Sets AWS_SSO_START_URL, AWS_SSO_REGION, AWS_SSO_ADMIN_ROLE_NAME and
# CONSOLE_USERS_URL in the calling shell.
function load_aws_sso_setup {
  [[ -f "$CONFIG_SETUP_JSON_FILE" ]] ||
    die "$CONFIG_SETUP_JSON_FILE does not exist. Run \`dalmatian setup\` first."

  AWS_SSO_START_URL=$(jq -r '.aws_sso.start_url // empty' < "$CONFIG_SETUP_JSON_FILE" 2>/dev/null) ||
    die "could not parse $CONFIG_SETUP_JSON_FILE"
  AWS_SSO_REGION=$(jq -r '.aws_sso.region // empty' < "$CONFIG_SETUP_JSON_FILE" 2>/dev/null) ||
    die "could not parse $CONFIG_SETUP_JSON_FILE"
  AWS_SSO_ADMIN_ROLE_NAME=$(jq -r '.aws_sso.default_admin_role_name // empty' < "$CONFIG_SETUP_JSON_FILE" 2>/dev/null) ||
    die "could not parse $CONFIG_SETUP_JSON_FILE"

  [[ -n "$AWS_SSO_START_URL" ]] ||
    die "aws_sso.start_url is not set in $CONFIG_SETUP_JSON_FILE. Run \`dalmatian setup\`."
  [[ -n "$AWS_SSO_REGION" ]] ||
    die "aws_sso.region is not set in $CONFIG_SETUP_JSON_FILE. Run \`dalmatian setup\`."
  [[ -n "$AWS_SSO_ADMIN_ROLE_NAME" ]] ||
    die "aws_sso.default_admin_role_name is not set in $CONFIG_SETUP_JSON_FILE. Run \`dalmatian setup\`."

  CONSOLE_USERS_URL="https://$AWS_SSO_REGION.console.aws.amazon.com/singlesignon/identity/home?region=$AWS_SSO_REGION#!/users"
}
```

- [ ] **Step 6: Create `lib/bash-functions/aws_profile_exists.sh`**

```bash
#!/usr/bin/env bash
set -e
set -o pipefail

# Return 0 if the named profile is in the AWS config dalmatian is pointed at.
#
# `aws configure list-profiles` reads whatever AWS_CONFIG_FILE points at, which
# bin/dalmatian has already overridden to the Dalmatian SSO config, so this
# checks the right file without naming it. The match is exact, not a grep of the
# file, so a profile name that is a substring of another cannot satisfy it.
#
# The output is captured rather than read from a process substitution: a failure
# inside `< <(...)` is invisible, which would make an unreadable or unparseable
# config indistinguishable from "no such profile". That matters in both
# directions — a caller would append a duplicate profile, or would insist a
# profile is missing that the operator can plainly see in the file.
#
# @usage if aws_profile_exists "dalmatian-main"; then ...; fi
# @param $1 The profile name to look for
function aws_profile_exists {
  local wanted=$1 profile profiles

  profiles=$(aws configure list-profiles) ||
    die "could not read AWS profiles from $AWS_CONFIG_FILE"

  while IFS='' read -r profile
  do
    if [[ "$profile" == "$wanted" ]]
    then
      return 0
    fi
  done <<<"$profiles"
  return 1
}
```

- [ ] **Step 7: Create `lib/bash-functions/resolve_identity_center_profile.sh`**

```bash
#!/usr/bin/env bash
set -e
set -o pipefail

# Set IDENTITY_CENTER_PROFILE to a profile that can administer IAM Identity
# Center, and verify it actually authenticates.
#
# The Identity Center instance lives in the organisation's management account,
# which is not a Dalmatian-managed Terraform workspace and therefore gets no
# profile from `dalmatian aws generate-config`. When no usable profile exists,
# this discovers the management account and writes one.
#
# Reads PROFILE_OVERRIDE (from a command's -p flag, may be empty) and
# IDENTITY_CENTER_PROFILE_NAME. Sets IDENTITY_CENTER_PROFILE, and via
# load_aws_sso_setup also AWS_SSO_START_URL, AWS_SSO_REGION,
# AWS_SSO_ADMIN_ROLE_NAME and CONSOLE_USERS_URL.
#
# @usage resolve_identity_center_profile
function resolve_identity_center_profile {
  load_aws_sso_setup

  if [[ -n "${PROFILE_OVERRIDE:-}" ]]
  then
    aws_profile_exists "$PROFILE_OVERRIDE" ||
      die "profile '$PROFILE_OVERRIDE' is not in $AWS_CONFIG_FILE.
       Try running \`dalmatian aws generate-config\` first."
    IDENTITY_CENTER_PROFILE=$PROFILE_OVERRIDE
  elif aws_profile_exists "$IDENTITY_CENTER_PROFILE_NAME"
  then
    IDENTITY_CENTER_PROFILE=$IDENTITY_CENTER_PROFILE_NAME
  else
    # A member account is permitted to call describe-organization, so this works
    # from dalmatian-main. stderr is folded into the variable so a failure can be
    # reported verbatim; the 12-digit check below is what catches a corrupted
    # value, an empty response, or the literal "None" that --output text prints
    # for a missing field.
    local management_account_id
    management_account_id=$(aws --profile dalmatian-main organizations describe-organization \
      --query 'Organization.MasterAccountId' --output text 2>&1) ||
      die "could not look up the organisation's management account: $management_account_id"
    [[ "$management_account_id" =~ ^[0-9]{12}$ ]] ||
      die "organizations describe-organization did not return a 12-digit management account ID (got '$management_account_id')"

    esc_info "$(printf "Adding the '%s' profile for management account %s" \
      "$IDENTITY_CENTER_PROFILE_NAME" "$management_account_id")"

    # The profile's region is the Identity Center region, not the project's
    # default region: sso-admin and identitystore calls have to be made in the
    # region the instance lives in. They are often the same value, which is
    # exactly why this is worth stating.
    #
    # append_sso_config_file appends blind with no existence check of its own, so
    # the aws_profile_exists call above is the whole of the idempotency. Note
    # that `dalmatian aws generate-config` rewrites this file wholesale and will
    # drop this profile; that costs nothing, because the next run re-adds it.
    append_sso_config_file \
      "$CONFIG_AWS_SSO_FILE" \
      "$IDENTITY_CENTER_PROFILE_NAME" \
      "$AWS_SSO_START_URL" \
      "$AWS_SSO_REGION" \
      "$management_account_id" \
      "$AWS_SSO_ADMIN_ROLE_NAME" \
      "$AWS_SSO_REGION"

    IDENTITY_CENTER_PROFILE=$IDENTITY_CENTER_PROFILE_NAME
  fi

  # Fail fast and usefully. Keep the underlying error rather than discarding it:
  # a profile that does not exist fails here too, and `aws sso login` cannot fix
  # that, so advice which assumes expiry would send the operator down a dead end.
  local auth_err
  if ! auth_err=$(aws --profile "$IDENTITY_CENTER_PROFILE" sts get-caller-identity 2>&1 >/dev/null)
  then
    die "cannot authenticate with profile '$IDENTITY_CENTER_PROFILE': ${auth_err:-unknown error}
       This usually means one of two things. Either the SSO session has expired,
       in which case run: dalmatian aws login
       Or you have no '$AWS_SSO_ADMIN_ROLE_NAME' permission set assigned on the
       organisation's management account, which no amount of logging in will fix."
  fi
}
```

- [ ] **Step 8: Create `lib/bash-functions/identity_center_instance.sh`**

```bash
#!/usr/bin/env bash
set -e
set -o pipefail

# Discover the single IAM Identity Center instance.
#
# Requires IDENTITY_CENTER_PROFILE to be set, so call
# resolve_identity_center_profile first. Sets INSTANCE_ARN and
# IDENTITY_STORE_ID in the calling shell.
#
# @usage identity_center_instance
function identity_center_instance {
  # Deliberately not redirecting aws's stderr into the variable: if
  # list-instances ever writes diagnostics to stderr they should reach the
  # terminal untouched, rather than get folded into $instances and corrupt the
  # JSON.
  local instances count
  instances=$(aws --profile "$IDENTITY_CENTER_PROFILE" sso-admin list-instances --output json) ||
    die "failed to list Identity Center instances"

  # jq exits non-zero on unparseable input. Without this check `set -e` kills the
  # caller on jq's own status and the operator gets a raw parse error instead of
  # a diagnosis. The numeric test also stops an empty response producing the
  # nonsense message "found " with a blank count.
  count=$(jq '.Instances | length' <<<"$instances" 2>/dev/null) ||
    die "could not parse the response from sso-admin list-instances"
  [[ "$count" =~ ^[0-9]+$ ]] ||
    die "could not parse the response from sso-admin list-instances"
  [[ "$count" == 1 ]] ||
    die "expected exactly 1 Identity Center instance, found $count"

  # `// empty` makes jq print nothing for a missing or null field. Without it
  # `jq -r` prints the literal string "null", this succeeds, and the failure
  # resurfaces as an opaque ValidationException much later.
  INSTANCE_ARN=$(jq -r '.Instances[0].InstanceArn // empty' <<<"$instances" 2>/dev/null) ||
    die "could not parse the response from sso-admin list-instances"
  IDENTITY_STORE_ID=$(jq -r '.Instances[0].IdentityStoreId // empty' <<<"$instances" 2>/dev/null) ||
    die "could not parse the response from sso-admin list-instances"

  [[ -n "$INSTANCE_ARN" && -n "$IDENTITY_STORE_ID" ]] ||
    die "sso-admin list-instances returned an instance with no ARN or identity store ID"
}
```

- [ ] **Step 9: Create `lib/bash-functions/require_visible_plan.sh`**

```bash
#!/usr/bin/env bash
set -e
set -o pipefail

# Refuse to run when the plan would be invisible but the confirmation prompt
# would still appear.
#
# Commands print their plan with esc_msg, which bin/dalmatian suppresses
# whenever stdout is not a terminal, or when -q was given. `yes_no`, by
# contrast, shows its prompt whenever *stdin* is a terminal. Those two
# conditions are independent, so redirecting stdout alone produces a "Proceed?"
# prompt with no visible plan anywhere — asking the operator to authorise
# changes they cannot see.
#
# The two flags are passed rather than read as globals because ASSUME_YES and
# DRY_RUN are command-local names, while QUIET_MODE belongs to the dispatcher.
#
# @usage require_visible_plan "$ASSUME_YES" "$DRY_RUN"
# @param $1 1 if -y was given (the operator has declined the prompt, so exempt)
# @param $2 1 if -n was given (a dry run changes nothing, so exempt)
function require_visible_plan {
  local assume_yes=${1:-0} dry_run=${2:-0}

  if ((QUIET_MODE && !assume_yes && !dry_run))
  then
    die "refusing to ask for confirmation when the plan cannot be shown.
       The plan is suppressed because output is not a terminal, or because -q
       was given, so you would be approving changes you cannot see. Re-run on a
       terminal, or pass -y to skip the confirmation, or -n for a dry run."
  fi
}
```

- [ ] **Step 10: Verify shellcheck accepts all eight files**

```bash
./test.sh && echo "SHELLCHECK OK"
```

Expected: `SHELLCHECK OK`. Note `test.sh` lints `./bin` and `./support` only, so also lint the
new files directly:

```bash
shellcheck -x lib/bash-functions/die.sh lib/bash-functions/esc_msg.sh \
  lib/bash-functions/esc_info.sh lib/bash-functions/load_aws_sso_setup.sh \
  lib/bash-functions/aws_profile_exists.sh \
  lib/bash-functions/resolve_identity_center_profile.sh \
  lib/bash-functions/identity_center_instance.sh \
  lib/bash-functions/require_visible_plan.sh && echo "LIB LINT OK"
```

Expected: `LIB LINT OK`. Findings about `err`, `log_msg`, `append_sso_config_file` or `die`
being undefined are expected and acceptable — they are supplied by the dispatcher at runtime.
If shellcheck reports SC2154 for the dispatcher-exported variables, do not silence it; those
are genuinely externally supplied, and `-x` plus the existing lib files' precedent shows the
repo tolerates this pattern. If it errors rather than warns, stop and ask.

- [ ] **Step 11: Verify the dispatcher actually exports all eight**

This is the check that catches the `function foo {` mistake, which lint cannot see.

```bash
for f in die esc_msg esc_info load_aws_sso_setup aws_profile_exists \
         resolve_identity_center_profile identity_center_instance require_visible_plan
do
  printf '%-34s ' "$f"
  grep -q "^function $f\b" "lib/bash-functions/$f.sh" && echo "exportable" || echo "NOT EXPORTABLE - fix the declaration"
done
```

Expected: all eight `exportable`.

Then prove it end to end, through the real dispatcher:

```bash
cat > /tmp/dalmatian-export-probe <<'PROBE'
#!/usr/bin/env bash
set -euo pipefail
for f in die esc_msg esc_info load_aws_sso_setup aws_profile_exists \
         resolve_identity_center_profile identity_center_instance require_visible_plan
do
  if declare -F "$f" > /dev/null
  then
    printf 'ok      %s\n' "$f"
  else
    printf 'MISSING %s\n' "$f"
  fi
done
PROBE
chmod +x /tmp/dalmatian-export-probe
cp /tmp/dalmatian-export-probe bin/aws/v2/export-probe
DALMATIAN_SKIP_UPDATE_CHECK=1 ./bin/dalmatian aws export-probe
rm -f bin/aws/v2/export-probe /tmp/dalmatian-export-probe
```

Expected: eight `ok` lines and no `MISSING`. Remember to delete `bin/aws/v2/export-probe` — it
must not be committed, and `test.sh` would lint it.

---

### Task 2: Refactor `add-user` onto the shared functions

**Files:**
- Modify: `bin/aws/v2/add-user`

**Interfaces:**
- Consumes: all eight functions from Task 1.
- Produces: an `add-user` roughly 120 lines shorter, behaving identically. Keeps its own
  `aws_admin`, pickers, `load_directory`, `resolve_group`, `resolve_permission_set`,
  `resolve_account`, `assignment_key`, `validate_email`, `derive_names`, `read_line_or_die`,
  `prompt_identity`, and everything from `parse_grant_arg` onward.

- [ ] **Step 1: Delete the six now-duplicated function definitions**

Remove these entire definitions, comments included, from `bin/aws/v2/add-user`:

- `die()`
- `esc_msg()`
- `esc_info()`
- `load_setup_config()`
- `profile_exists()`
- `resolve_identity_center_profile()`

Leave `aws_admin()` exactly as it is. The script keeps calling `die`, `esc_msg`, `esc_info` and
`resolve_identity_center_profile` by the same names, so no call site changes.

- [ ] **Step 2: Replace the guard and the removed calls in `preflight`**

Replace:

```bash
preflight() {
  # The plan is the operator's only chance to catch a wrong grant before it is
  # made, and print_plan emits it with log_msg — which bin/dalmatian suppresses
  # whenever stdout is not a terminal, or when -q was given. `yes_no`, by
  # contrast, shows its prompt whenever *stdin* is a terminal. Redirecting
  # stdout alone therefore produces a "Proceed?" prompt with no visible plan
  # anywhere, asking the operator to authorise access they cannot see. Refuse
  # rather than let that happen.
  #
  # -y is exempt: the operator has explicitly declined the confirmation, so
  # there is no consent to misinform. -n is exempt: it writes nothing to AWS.
  if ((QUIET_MODE && !ASSUME_YES && !DRY_RUN))
  then
    die "refusing to ask for confirmation when the plan cannot be shown.
       The plan is suppressed because output is not a terminal, or because -q
       was given, so you would be approving grants you cannot see. Re-run on a
       terminal, or pass -y to skip the confirmation, or -n for a dry run."
  fi

  command -v aws >/dev/null 2>&1 || die "aws CLI not found on PATH"
```

with:

```bash
preflight() {
  require_visible_plan "$ASSUME_YES" "$DRY_RUN"

  command -v aws >/dev/null 2>&1 || die "aws CLI not found on PATH"
```

- [ ] **Step 3: Replace the setup/profile/instance block in `preflight`**

Replace everything from `load_setup_config` to the end of the function — that is
`load_setup_config`, `resolve_identity_center_profile`, the `sts get-caller-identity` check, and
the whole `list-instances` block — with:

```bash
  resolve_identity_center_profile
  identity_center_instance
}
```

`resolve_identity_center_profile` now calls `load_aws_sso_setup` and does the authentication
check itself, and `identity_center_instance` replaces the `list-instances` block.

- [ ] **Step 4: Remove the now-dead declarations, keep the live ones**

`load_aws_sso_setup` assigns `AWS_SSO_START_URL`, `AWS_SSO_REGION` and
`AWS_SSO_ADMIN_ROLE_NAME` itself, and after this refactor `add-user` never reads any of the
three — the authentication error message that used `AWS_SSO_ADMIN_ROLE_NAME` moved into
`resolve_identity_center_profile`. Leaving them declared would be dead code and may trip
shellcheck's SC2034. Delete these three lines:

```bash
AWS_SSO_START_URL=""
AWS_SSO_REGION=""
AWS_SSO_ADMIN_ROLE_NAME=""
```

Keep the rest, and verify each is still present:

```bash
grep -n 'IDENTITY_CENTER_PROFILE_NAME=\|IDENTITY_CENTER_PROFILE=\|PROFILE_OVERRIDE=\|CONSOLE_USERS_URL=\|INSTANCE_ARN=\|IDENTITY_STORE_ID=' bin/aws/v2/add-user | head -8
```

Expected: an initialising assignment for each of the six. They must stay:
`resolve_identity_center_profile` reads `PROFILE_OVERRIDE` and `IDENTITY_CENTER_PROFILE_NAME`,
`aws_admin` and `print_plan` read `IDENTITY_CENTER_PROFILE`, `print_summary` reads
`CONSOLE_USERS_URL`, and the identity-store pair is used throughout.

If shellcheck now flags `PROFILE_OVERRIDE` as unused, that is expected — it is assigned here and
read by an exported library function, which shellcheck cannot see. Do **not** suppress it; if it
is reported as a warning rather than an error, `test.sh` still passes and no action is needed.
If it fails the lint, stop and ask rather than adding a disable comment.

- [ ] **Step 5: Lint**

```bash
bash -n bin/aws/v2/add-user && ./test.sh && echo "OK"
```

Expected: `OK`.

- [ ] **Step 6: Smoke test**

```bash
DALMATIAN_SKIP_UPDATE_CHECK=1 script -q /dev/null \
  ./bin/dalmatian aws add-user -n -y -e jane.doe@example.com -f Jane -l Doe \
  -g Admin -a admin:my-account 2>&1 | tr -d '\r' | tail -14
```

Expected: a plan reading `REUSE existing user`, `skip   already a member of 'Admin'`, and
`ADD    grant 'admin' on my-account (123456789012)  [redundant — inherited from group
'Admin']`, then `==> Dry run (-n), nothing changed.` Identical to before the refactor. The full
matrix is deliberately not repeated.

- [ ] **Step 7: Confirm the line count dropped**

```bash
wc -l < bin/aws/v2/add-user
```

Expected: roughly 1250, down from 1370. A number close to 1370 means the deletions in Step 1
did not happen.

---

### Task 3: `list-users`

**Files:**
- Create: `bin/aws/v2/list-users`

**Interfaces:**
- Consumes: `die`, `esc_info`, `resolve_identity_center_profile`, `identity_center_instance`
  from Task 1.
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Create the file**

```bash
#!/usr/bin/env bash

# List AWS IAM Identity Center users, with their status and group memberships.
#
# The table is the payload, so it is written straight to stdout with printf and
# NOT through esc_msg. bin/dalmatian forces QUIET_MODE=1 whenever stdout is not
# a terminal, so routing it through log_msg would make
# `dalmatian aws list-users | grep DISABLED` print nothing at all. Messages that
# are not payload — the profile-creation notice, for instance — do go through
# esc_info, so they stay out of a pipe. Same reasoning as the bare `echo` in
# bin/aws/v2/list-profiles and bin/deploy/v2/list-accounts.

set -euo pipefail

# The SSO profile used to read Identity Center. See
# lib/bash-functions/resolve_identity_center_profile.sh.
IDENTITY_CENTER_PROFILE_NAME="dalmatian-identity-center"
IDENTITY_CENTER_PROFILE=""
PROFILE_OVERRIDE=""

# AWS_SSO_START_URL, AWS_SSO_REGION, AWS_SSO_ADMIN_ROLE_NAME and
# CONSOLE_USERS_URL are deliberately not declared here. load_aws_sso_setup
# assigns them, and this command never reads them, so declaring them would be
# dead code.

INSTANCE_ARN=""
IDENTITY_STORE_ID=""

JSON_OUTPUT=0

# Fields are joined with the ASCII unit separator rather than a tab. Tab is IFS
# *whitespace*, so `IFS=$'\t' read` silently collapses an empty field adjacent to
# the delimiter and shifts every later field left — and both EMAIL and GROUPS are
# legitimately empty for some users. A non-whitespace IFS preserves empty fields.
readonly FIELD_SEP=$'\x1f'

usage() {
  cat >&2 <<EOF
Usage: dalmatian aws list-users [-j] [-p profile] [-h]

Lists every user in the AWS IAM Identity Center directory, with their status and
group memberships.

  -j                    output JSON instead of a table
  -p <profile>          AWS profile to read Identity Center with.
                        Defaults to $IDENTITY_CENTER_PROFILE_NAME, which is
                        created automatically if it does not already exist
  -h                    this help

Examples:
  dalmatian aws list-users
  dalmatian aws list-users | grep DISABLED
  dalmatian aws list-users -j | jq -r '.[] | select(.Groups | index("Admin")) | .UserName'
EOF
  exit 1
}

parse_args() {
  local OPTIND OPTARG opt
  while getopts "jp:h" opt; do
    case "$opt" in
    j) JSON_OUTPUT=1 ;;
    p) PROFILE_OVERRIDE="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
    esac
  done
}

# All AWS calls funnel through here, so the profile is named in exactly one
# place. Set by resolve_identity_center_profile before any call is made.
aws_admin() {
  aws --profile "$IDENTITY_CENTER_PROFILE" "$@"
}

preflight() {
  command -v aws >/dev/null 2>&1 || die "aws CLI not found on PATH"
  command -v jq >/dev/null 2>&1 || die "jq not found on PATH"

  resolve_identity_center_profile
  identity_center_instance
}

declare -A USER_GROUPS=()

# Build a UserId -> comma-separated group names map.
#
# Iterates groups rather than users on purpose. A directory typically has far
# fewer groups than users, and list-group-memberships-for-member would need one
# call per user; this needs one per group. Group names containing a comma will be
# ambiguous in the joined string, which is accepted: the JSON output (-j) keeps
# them as a proper array for anyone who needs to parse it.
load_user_groups() {
  USER_GROUPS=()

  local groups tsv line gid gname members uids uid
  groups=$(aws_admin identitystore list-groups \
    --identity-store-id "$IDENTITY_STORE_ID" --output json) ||
    die "failed to list groups"
  [[ -n "$groups" ]] || die "empty response from identitystore list-groups"

  tsv=$(jq -r '
      if (.Groups | type) != "array" then error("Groups is not an array")
      else (.Groups | sort_by(.DisplayName) | .[] |
            [(.GroupId // ""), (.DisplayName // "")] | join("\u001f"))
      end' <<<"$groups" 2>/dev/null) ||
    die "could not parse the response from identitystore list-groups"

  # An empty tsv means genuinely zero groups. `<<<""` still hands `read` one
  # empty line, which must not be mistaken for a malformed row.
  [[ -n "$tsv" ]] || return 0

  while IFS= read -r line
  do
    [[ -n "$line" ]] || continue
    IFS="$FIELD_SEP" read -r gid gname <<<"$line"
    [[ -n "$gid" && -n "$gname" ]] ||
      die "identitystore list-groups returned a group with a missing GroupId or DisplayName"

    members=$(aws_admin identitystore list-group-memberships \
      --identity-store-id "$IDENTITY_STORE_ID" --group-id "$gid" --output json) ||
      die "failed to list memberships for group '$gname'"

    # Captured rather than piped from a process substitution, so a jq failure
    # cannot be mistaken for "this group has no members".
    uids=$(jq -r '.GroupMemberships[]?.MemberId.UserId // empty' <<<"$members" 2>/dev/null) ||
      die "could not parse the response from identitystore list-group-memberships for '$gname'"

    [[ -n "$uids" ]] || continue

    while IFS= read -r uid
    do
      [[ -n "$uid" ]] || continue
      if [[ -n "${USER_GROUPS[$uid]:-}" ]]
      then
        USER_GROUPS["$uid"]="${USER_GROUPS[$uid]},$gname"
      else
        USER_GROUPS["$uid"]=$gname
      fi
    done <<<"$uids"
  done <<<"$tsv"
}

# Render USER_GROUPS as a JSON object of UserId -> array of group names, for -j.
user_groups_json() {
  local uid pairs
  pairs=""
  for uid in "${!USER_GROUPS[@]}"
  do
    pairs+="$uid$FIELD_SEP${USER_GROUPS[$uid]}"$'\n'
  done

  if [[ -z "$pairs" ]]
  then
    printf '%s' '{}'
    return 0
  fi

  printf '%s' "$pairs" | jq -R -s --arg sep "$FIELD_SEP" '
      split("\n")
      | map(select(length > 0) | split($sep))
      | map({key: .[0], value: (.[1] | split(","))})
      | from_entries' ||
    die "could not build the group map"
}

USERS_JSON=""

load_users() {
  USERS_JSON=$(aws_admin identitystore list-users \
    --identity-store-id "$IDENTITY_STORE_ID" --output json) ||
    die "failed to list users"
  [[ -n "$USERS_JSON" ]] || die "empty response from identitystore list-users"

  jq -e '(.Users | type) == "array"' <<<"$USERS_JSON" >/dev/null 2>&1 ||
    die "could not parse the response from identitystore list-users"
}

output_json() {
  jq --argjson groups "$(user_groups_json)" '
      [.Users[] | . + {Groups: ($groups[.UserId] // [])}]
      | sort_by(.UserName)' <<<"$USERS_JSON" ||
    die "could not render JSON output"
}

output_table() {
  local rows
  rows=$(jq -r --argjson groups "$(user_groups_json)" '
      .Users
      | sort_by(.UserName)
      | .[]
      | [ (.UserName // ""),
          (.UserStatus // ""),
          (.DisplayName // ""),
          ((.Emails // []) | map(select(.Primary == true)) | first | .Value //
           ((.Emails // []) | first | .Value) // ""),
          (($groups[.UserId] // []) | join(","))
        ]
      | join("\u001f")' <<<"$USERS_JSON") ||
    die "could not build the user table"

  local -a headers=("USERNAME" "STATUS" "DISPLAY NAME" "EMAIL" "GROUPS")
  local -a widths=(0 0 0 0 0)
  local -a fields
  local line i

  for i in 0 1 2 3 4
  do
    widths[i]=${#headers[i]}
  done

  if [[ -n "$rows" ]]
  then
    while IFS= read -r line
    do
      [[ -n "$line" ]] || continue
      IFS="$FIELD_SEP" read -r -a fields <<<"$line"
      for i in 0 1 2 3 4
      do
        if ((${#fields[i]} > widths[i]))
        then
          widths[i]=${#fields[i]}
        fi
      done
    done <<<"$rows"
  fi

  # printf, straight to stdout, never esc_msg: see the header comment.
  printf '%-*s  %-*s  %-*s  %-*s  %s\n' \
    "${widths[0]}" "${headers[0]}" \
    "${widths[1]}" "${headers[1]}" \
    "${widths[2]}" "${headers[2]}" \
    "${widths[3]}" "${headers[3]}" \
    "${headers[4]}"

  [[ -n "$rows" ]] || return 0

  while IFS= read -r line
  do
    [[ -n "$line" ]] || continue
    IFS="$FIELD_SEP" read -r -a fields <<<"$line"
    printf '%-*s  %-*s  %-*s  %-*s  %s\n' \
      "${widths[0]}" "${fields[0]:-}" \
      "${widths[1]}" "${fields[1]:-}" \
      "${widths[2]}" "${fields[2]:-}" \
      "${widths[3]}" "${fields[3]:-}" \
      "${fields[4]:-}"
  done <<<"$rows"
}

main() {
  parse_args "$@"
  preflight
  load_users
  load_user_groups

  if ((JSON_OUTPUT))
  then
    output_json
  else
    output_table
  fi
}

main "$@"
```

- [ ] **Step 2: Make it executable and lint**

```bash
chmod +x bin/aws/v2/list-users
bash -n bin/aws/v2/list-users && ./test.sh && echo "OK"
```

Expected: `OK`.

- [ ] **Step 3: Verify the table**

```bash
DALMATIAN_SKIP_UPDATE_CHECK=1 script -q /dev/null ./bin/dalmatian aws list-users 2>&1 | tr -d '\r' | head -8
```

Expected: a `USERNAME  STATUS  DISPLAY NAME  EMAIL  GROUPS` header with aligned columns, then
users sorted by username. `asmith` should show `ENABLED`, and its `GROUPS` column should be
populated.

- [ ] **Step 4: Verify the row count and that DISABLED users appear**

```bash
DALMATIAN_SKIP_UPDATE_CHECK=1 ./bin/dalmatian aws list-users | tail -n +2 | wc -l
DALMATIAN_SKIP_UPDATE_CHECK=1 ./bin/dalmatian aws list-users | grep -c DISABLED
```

Expected: `42` and `7`. **These two commands are piped, which is the whole point** — they prove
the payload is not suppressed by quiet mode. If the first returns 0, the table was wrongly
routed through `esc_msg`.

- [ ] **Step 5: Verify JSON output**

```bash
DALMATIAN_SKIP_UPDATE_CHECK=1 ./bin/dalmatian aws list-users -j | jq -e 'length == 42' >/dev/null && echo "count ok"
DALMATIAN_SKIP_UPDATE_CHECK=1 ./bin/dalmatian aws list-users -j | jq -r '.[0] | {UserName, UserStatus, Groups}'
DALMATIAN_SKIP_UPDATE_CHECK=1 ./bin/dalmatian aws list-users -j | jq -r '[.[] | select(.Groups | index("Admin")) | .UserName] | length'
```

Expected: `count ok`; a first object with `Groups` as an array; and a non-zero count of Admin
members. Valid JSON on a pipe proves the same point as Step 4.

- [ ] **Step 6: Verify empty columns do not break alignment**

```bash
DALMATIAN_SKIP_UPDATE_CHECK=1 ./bin/dalmatian aws list-users | awk -F'  +' '{print NF}' | sort -u
```

Expected: mostly `5`, and no row with more fields than the header. A user with no groups must
still line up — this is what the `$'\x1f'` separator protects against.

---

### Task 4: `remove-user`

**Files:**
- Create: `bin/aws/v2/remove-user`

**Interfaces:**
- Consumes: `die`, `esc_msg`, `esc_info`, `require_visible_plan`,
  `resolve_identity_center_profile`, `identity_center_instance` from Task 1; `yes_no`,
  `warning`, `err` from the existing lib.
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Create the file**

```bash
#!/usr/bin/env bash

# Remove a user from AWS IAM Identity Center.
#
# Revokes every direct account assignment, removes every group membership, then
# deletes the user record. Prints a plan first and asks for confirmation.
#
# Order matters: assignments are revoked before the user is deleted, so an
# interrupted run can never leave a deleted principal holding live grants. If any
# teardown step fails, the user record is deliberately NOT deleted — that would
# produce exactly the orphaned-assignment state this command exists to avoid, and
# would destroy the UserId needed to find those grants again.
#
# NOTE: this cannot disable a user instead of deleting them. The identitystore
# API exposes UserStatus as output only; UpdateUser rejects both `userStatus` and
# `active` with "Updates for AttributePath: X is not supported". Disabling is a
# console-only action.

set -euo pipefail

IDENTITY_CENTER_PROFILE_NAME="dalmatian-identity-center"
IDENTITY_CENTER_PROFILE=""
PROFILE_OVERRIDE=""

# AWS_SSO_START_URL, AWS_SSO_REGION, AWS_SSO_ADMIN_ROLE_NAME and
# CONSOLE_USERS_URL are deliberately not declared here. load_aws_sso_setup
# assigns them, and this command never reads them, so declaring them would be
# dead code.

INSTANCE_ARN=""
IDENTITY_STORE_ID=""

EMAIL=""
DRY_RUN=0
ASSUME_YES=0

USER_ID=""
GIVEN_NAME=""
FAMILY_NAME=""
USER_STATUS=""

FAILURES=0

# Tuple separator. The ASCII unit separator cannot appear in any AWS-supplied
# value, and unlike a tab it is not IFS whitespace, so empty fields survive
# splitting intact.
readonly FIELD_SEP=$'\x1f'

# membershipId, groupId, groupName
MEMBERSHIPS=()
# accountId, permissionSetArn, permissionSetName, accountName
ASSIGNMENTS=()
# requestId, description
DELETION_REQUESTS=()

POLL_INTERVAL=2
POLL_ATTEMPTS=60

usage() {
  cat >&2 <<EOF
Usage: dalmatian aws remove-user -e <email> [-p profile] [-n] [-y] [-h]

Removes a user from AWS IAM Identity Center: revokes their direct account
assignments, removes their group memberships, then deletes the user.

  -e <email>            username of the user to remove
  -p <profile>          AWS profile to administer Identity Center with.
                        Defaults to $IDENTITY_CENTER_PROFILE_NAME, which is
                        created automatically if it does not already exist
  -n                    dry run: print the plan, make no AWS changes
  -y                    skip the confirmation prompt
  -h                    this help

This cannot disable a user. The API exposes UserStatus as read-only, so
disabling remains a console action.

Examples:
  dalmatian aws remove-user -e jane.doe@example.com -n
  dalmatian aws remove-user -e jane.doe@example.com
EOF
  exit 1
}

parse_args() {
  local OPTIND OPTARG opt
  while getopts "e:p:nyh" opt; do
    case "$opt" in
    e) EMAIL="$OPTARG" ;;
    p) PROFILE_OVERRIDE="$OPTARG" ;;
    n) DRY_RUN=1 ;;
    y) ASSUME_YES=1 ;;
    h) usage ;;
    *) usage ;;
    esac
  done

  [[ -n "$EMAIL" ]] || usage
  [[ "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] ||
    die "not a valid email address: $EMAIL"
}

aws_admin() {
  aws --profile "$IDENTITY_CENTER_PROFILE" "$@"
}

preflight() {
  require_visible_plan "$ASSUME_YES" "$DRY_RUN"

  command -v aws >/dev/null 2>&1 || die "aws CLI not found on PATH"
  command -v jq >/dev/null 2>&1 || die "jq not found on PATH"

  resolve_identity_center_profile
  identity_center_instance
}

# Unlike add-user, a missing user is fatal: there is nothing to remove, and
# exiting 0 would wrongly suggest the account had been cleaned up.
lookup_user() {
  local out rc=0
  out=$(aws_admin identitystore get-user-id \
    --identity-store-id "$IDENTITY_STORE_ID" \
    --alternate-identifier "{\"UniqueAttribute\":{\"AttributePath\":\"UserName\",\"AttributeValue\":\"$EMAIL\"}}" \
    --output json 2>&1) || rc=$?

  if ((rc != 0))
  then
    # Matched against the CLI's stable error prefix, not a bare substring, so a
    # message that merely mentions the exception name cannot be misread.
    if [[ "$out" == *"An error occurred (ResourceNotFoundException)"* ]]
    then
      die "no Identity Center user with username '$EMAIL'. Nothing to remove."
    fi
    die "failed looking up user '$EMAIL': $out"
  fi

  USER_ID=$(jq -r '.UserId // empty' <<<"$out" 2>/dev/null) ||
    die "could not parse the response from identitystore get-user-id"
  [[ -n "$USER_ID" ]] ||
    die "identitystore get-user-id returned no UserId for $EMAIL"
}

# Captured before deletion so the restore line can reproduce the user.
load_user_details() {
  local out
  out=$(aws_admin identitystore describe-user \
    --identity-store-id "$IDENTITY_STORE_ID" --user-id "$USER_ID" --output json) ||
    die "failed to describe user $EMAIL"

  GIVEN_NAME=$(jq -r '.Name.GivenName // empty' <<<"$out" 2>/dev/null) ||
    die "could not parse the response from identitystore describe-user"
  FAMILY_NAME=$(jq -r '.Name.FamilyName // empty' <<<"$out" 2>/dev/null) ||
    die "could not parse the response from identitystore describe-user"
  USER_STATUS=$(jq -r '.UserStatus // empty' <<<"$out" 2>/dev/null) ||
    die "could not parse the response from identitystore describe-user"
}

load_memberships() {
  MEMBERSHIPS=()

  local out rows line mid gid gname
  out=$(aws_admin identitystore list-group-memberships-for-member \
    --identity-store-id "$IDENTITY_STORE_ID" \
    --member-id "{\"UserId\":\"$USER_ID\"}" --output json) ||
    die "failed to list group memberships for $EMAIL"

  rows=$(jq -r '
      (if has("GroupMemberships") then .GroupMemberships else [] end) as $m
      | if ($m | type) != "array" then error("GroupMemberships is not an array")
        else ($m[] | [(.MembershipId // ""), (.GroupId // "")] | join("\u001f"))
        end' <<<"$out" 2>/dev/null) ||
    die "could not parse the response from identitystore list-group-memberships-for-member"

  [[ -n "$rows" ]] || return 0

  while IFS= read -r line
  do
    [[ -n "$line" ]] || continue
    IFS="$FIELD_SEP" read -r mid gid <<<"$line"
    [[ -n "$mid" && -n "$gid" ]] || continue

    # Resolved on demand: a leaver belongs to a handful of groups, so this is
    # cheaper than loading the whole directory.
    gname=$(aws_admin identitystore describe-group \
      --identity-store-id "$IDENTITY_STORE_ID" --group-id "$gid" \
      --query DisplayName --output text 2>/dev/null) || gname=""
    [[ -n "$gname" && "$gname" != "None" ]] || gname=$gid

    MEMBERSHIPS+=("$mid$FIELD_SEP$gid$FIELD_SEP$gname")
  done <<<"$rows"
}

# Only DIRECT assignments. list-account-assignments-for-principal with
# --principal-type USER also returns grants the user merely inherits through a
# group, distinguished by PrincipalType. Removing an inherited grant would revoke
# access for every other member of that group, so rows are kept only when
# PrincipalType is USER and PrincipalId is this user.
load_assignments() {
  ASSIGNMENTS=()

  local out rows line acct arn psname acctname
  out=$(aws_admin sso-admin list-account-assignments-for-principal \
    --instance-arn "$INSTANCE_ARN" \
    --principal-id "$USER_ID" \
    --principal-type USER \
    --output json) ||
    die "failed to list account assignments for $EMAIL"

  rows=$(jq -r --arg uid "$USER_ID" '
      (if has("AccountAssignments") then .AccountAssignments else [] end) as $aa
      | if ($aa | type) != "array" then error("AccountAssignments is not an array")
        else ($aa[]
              | select(.PrincipalType == "USER" and .PrincipalId == $uid)
              | [(.AccountId // ""), (.PermissionSetArn // "")] | join("\u001f"))
        end' <<<"$out" 2>/dev/null) ||
    die "could not parse the response from sso-admin list-account-assignments-for-principal"

  [[ -n "$rows" ]] || return 0

  while IFS= read -r line
  do
    [[ -n "$line" ]] || continue
    IFS="$FIELD_SEP" read -r acct arn <<<"$line"
    [[ -n "$acct" && -n "$arn" ]] || continue

    psname=$(aws_admin sso-admin describe-permission-set \
      --instance-arn "$INSTANCE_ARN" --permission-set-arn "$arn" \
      --query 'PermissionSet.Name' --output text 2>/dev/null) || psname=""
    [[ -n "$psname" && "$psname" != "None" ]] || psname=$arn

    acctname=$(aws_admin organizations describe-account --account-id "$acct" \
      --query 'Account.Name' --output text 2>/dev/null) || acctname=""
    [[ -n "$acctname" && "$acctname" != "None" ]] || acctname=$acct

    ASSIGNMENTS+=("$acct$FIELD_SEP$arn$FIELD_SEP$psname$FIELD_SEP$acctname")
  done <<<"$rows"
}

print_plan() {
  esc_msg ""
  esc_msg "Plan"
  esc_msg "===="
  if ((DRY_RUN))
  then
    esc_msg ""
    esc_msg "  DRY RUN — no AWS changes will be made"
    esc_msg ""
  fi
  esc_msg "$(printf '  profile:        %s' "$IDENTITY_CENTER_PROFILE")"
  esc_msg "$(printf '  identity store: %s' "$IDENTITY_STORE_ID")"
  esc_msg "$(printf '  username:       %s' "$EMAIL")"
  esc_msg "$(printf '  display name:   %s %s' "$GIVEN_NAME" "$FAMILY_NAME")"
  esc_msg "$(printf '  status:         %s' "$USER_STATUS")"
  esc_msg "$(printf '  user:           DELETE (%s)' "$USER_ID")"

  esc_msg ""
  esc_msg "  Group memberships to remove:"
  if ((${#MEMBERSHIPS[@]} == 0))
  then
    esc_msg "    (none)"
  else
    local entry mid gid gname
    for entry in "${MEMBERSHIPS[@]}"
    do
      IFS="$FIELD_SEP" read -r mid gid gname <<<"$entry"
      esc_msg "$(printf "    REMOVE '%s'" "$gname")"
    done
  fi

  esc_msg ""
  esc_msg "  Direct account grants to revoke:"
  if ((${#ASSIGNMENTS[@]} == 0))
  then
    esc_msg "    (none)"
  else
    local entry acct arn psname acctname
    for entry in "${ASSIGNMENTS[@]}"
    do
      IFS="$FIELD_SEP" read -r acct arn psname acctname <<<"$entry"
      esc_msg "$(printf "    REVOKE '%s' on %s (%s)" "$psname" "$acctname" "$acct")"
    done
  fi

  esc_msg ""
  esc_msg "  Grants inherited from groups are not listed: removing the group"
  esc_msg "  membership above is what withdraws them."
  esc_msg ""
}

do_revoke_assignments() {
  ((${#ASSIGNMENTS[@]})) || return 0

  local entry acct arn psname acctname desc out rc request_id
  for entry in "${ASSIGNMENTS[@]}"
  do
    IFS="$FIELD_SEP" read -r acct arn psname acctname <<<"$entry"
    desc="'$psname' on $acctname ($acct)"

    esc_info "$(printf 'Revoking %s' "$desc")"
    rc=0
    out=$(aws_admin sso-admin delete-account-assignment \
      --instance-arn "$INSTANCE_ARN" \
      --target-id "$acct" \
      --target-type AWS_ACCOUNT \
      --permission-set-arn "$arn" \
      --principal-type USER \
      --principal-id "$USER_ID" \
      --query 'AccountAssignmentDeletionStatus.RequestId' \
      --output text 2>&1) || rc=$?

    if ((rc != 0))
    then
      # Already gone is success, mirroring how add-user treats ConflictException
      # on create. Keeps a re-run after partial failure safe.
      if [[ "$out" == *ResourceNotFoundException* ]]
      then
        esc_msg "    already revoked, skipping"
      else
        err "$(printf 'failed to revoke %s: %s' "$desc" "$out")"
        FAILURES=$((FAILURES + 1))
      fi
      continue
    fi

    request_id=$out
    if [[ -z "$request_id" || "$request_id" == "None" ]]
    then
      err "$(printf 'failed to revoke %s: delete-account-assignment returned no RequestId' "$desc")"
      FAILURES=$((FAILURES + 1))
      continue
    fi

    DELETION_REQUESTS+=("$request_id$FIELD_SEP$desc")
  done
}

# Revocation is asynchronous, so returning straight after the delete call would
# report success for something that later failed — and would let delete-user run
# while grants were still live.
wait_for_revocations() {
  ((${#DELETION_REQUESTS[@]})) || return 0

  esc_info "$(printf 'Waiting for %d revocation(s) to complete' "${#DELETION_REQUESTS[@]}")"

  local entry request_id desc attempt checked status reason json
  for entry in "${DELETION_REQUESTS[@]}"
  do
    IFS="$FIELD_SEP" read -r request_id desc <<<"$entry"
    attempt=0
    checked=0
    while ((attempt < POLL_ATTEMPTS))
    do
      if ! json=$(aws_admin sso-admin describe-account-assignment-deletion-status \
        --instance-arn "$INSTANCE_ARN" \
        --account-assignment-deletion-request-id "$request_id" \
        --output json 2>&1)
      then
        warning "$(printf 'could not check %s (%s): %s' "$desc" "$request_id" "$json")"
        FAILURES=$((FAILURES + 1))
        checked=1
        break
      fi

      # `|| status=""` matters under `set -e`: a malformed response would
      # otherwise kill the script on jq's own exit status rather than falling
      # through to the retry branch below.
      status=$(jq -r '.AccountAssignmentDeletionStatus.Status // empty' <<<"$json" 2>/dev/null) ||
        status=""
      case "$status" in
      SUCCEEDED)
        esc_msg "$(printf '    ok %s' "$desc")"
        checked=1
        break
        ;;
      FAILED)
        reason=$(jq -r '.AccountAssignmentDeletionStatus.FailureReason // "unknown"' <<<"$json" 2>/dev/null) ||
          reason="unknown"
        err "$(printf '%s: %s' "$desc" "$reason")"
        FAILURES=$((FAILURES + 1))
        checked=1
        break
        ;;
      *)
        attempt=$((attempt + 1))
        ((POLL_INTERVAL > 0)) && sleep "$POLL_INTERVAL"
        ;;
      esac
    done

    if ((!checked))
    then
      warning "$(printf 'still in progress after timeout: %s (request %s)' "$desc" "$request_id")"
      FAILURES=$((FAILURES + 1))
    fi
  done
}

do_remove_memberships() {
  ((${#MEMBERSHIPS[@]})) || return 0

  local entry mid gid gname out rc
  for entry in "${MEMBERSHIPS[@]}"
  do
    IFS="$FIELD_SEP" read -r mid gid gname <<<"$entry"

    esc_info "$(printf "Removing from group '%s'" "$gname")"
    rc=0
    out=$(aws_admin identitystore delete-group-membership \
      --identity-store-id "$IDENTITY_STORE_ID" \
      --membership-id "$mid" 2>&1) || rc=$?

    if ((rc != 0))
    then
      if [[ "$out" == *ResourceNotFoundException* ]]
      then
        esc_msg "    already removed, skipping"
      else
        err "$(printf "failed to remove from group '%s': %s" "$gname" "$out")"
        FAILURES=$((FAILURES + 1))
      fi
    fi
  done
}

# The one step that is skipped rather than attempted-and-counted on failure.
# Deleting the identity while grants remain produces orphaned assignments and
# destroys the UserId needed to find them again.
do_delete_user() {
  if ((FAILURES > 0))
  then
    warning "$(printf 'not deleting %s: %d earlier step(s) failed, so grants may still be live. Fix the errors above and re-run.' \
      "$EMAIL" "$FAILURES")"
    return 0
  fi

  esc_info "$(printf 'Deleting user %s' "$EMAIL")"
  local out rc=0
  out=$(aws_admin identitystore delete-user \
    --identity-store-id "$IDENTITY_STORE_ID" \
    --user-id "$USER_ID" 2>&1) || rc=$?

  if ((rc != 0))
  then
    if [[ "$out" == *ResourceNotFoundException* ]]
    then
      esc_msg "    already deleted, skipping"
    else
      err "$(printf 'failed to delete user %s: %s' "$EMAIL" "$out")"
      FAILURES=$((FAILURES + 1))
    fi
  fi
}

print_restore_line() {
  local line entry mid gid gname acct arn psname acctname
  line="dalmatian aws add-user -e $EMAIL"
  [[ -n "$GIVEN_NAME" ]] && line+=" -f '$GIVEN_NAME'"
  [[ -n "$FAMILY_NAME" ]] && line+=" -l '$FAMILY_NAME'"

  for entry in ${MEMBERSHIPS[@]+"${MEMBERSHIPS[@]}"}
  do
    IFS="$FIELD_SEP" read -r mid gid gname <<<"$entry"
    line+=" -g '$gname'"
  done

  # Accounts are rendered as 12-digit IDs, not names: IDs are unambiguous,
  # whereas account names are not unique in an organisation.
  for entry in ${ASSIGNMENTS[@]+"${ASSIGNMENTS[@]}"}
  do
    IFS="$FIELD_SEP" read -r acct arn psname acctname <<<"$entry"
    line+=" -a '$psname:$acct'"
  done

  esc_msg ""
  esc_msg "To restore this user and their access, run:"
  esc_msg "$(printf '  %s' "$line")"
}

print_summary() {
  esc_msg ""
  if ((FAILURES == 0))
  then
    esc_info "$(printf 'Done. %s has been removed.' "$EMAIL")"
    print_restore_line
  else
    esc_info "$(printf 'Finished with %d failure(s). %s has NOT been deleted.' "$FAILURES" "$EMAIL")"
    esc_msg "    Every step is idempotent, so re-run the same command to retry."
  fi
  esc_msg ""
}

main() {
  parse_args "$@"
  preflight
  lookup_user
  load_user_details
  load_memberships
  load_assignments

  print_plan

  if ((DRY_RUN))
  then
    esc_info "Dry run (-n), nothing changed."
    exit 0
  fi

  if ((!ASSUME_YES)) && ! yes_no "Remove $EMAIL? (y/N)" "n"
  then
    esc_info "Aborted, nothing changed."
    exit 0
  fi

  do_revoke_assignments
  wait_for_revocations
  do_remove_memberships
  do_delete_user
  print_summary

  ((FAILURES == 0)) || exit 1
}

main "$@"
```

- [ ] **Step 2: Make it executable and lint**

```bash
chmod +x bin/aws/v2/remove-user
bash -n bin/aws/v2/remove-user && ./test.sh && echo "OK"
```

Expected: `OK`.

- [ ] **Step 3: Verify the dry-run plan against a real user**

```bash
DALMATIAN_SKIP_UPDATE_CHECK=1 script -q /dev/null \
  ./bin/dalmatian aws remove-user -n -y -e jane.doe@example.com 2>&1 | tr -d '\r' | tail -22
```

Expected: `DRY RUN — no AWS changes will be made`; `user: DELETE (1a2b3c4d-...)`;
`status: ENABLED`; `REMOVE 'Admin'` under group memberships; `(none)` under direct account
grants, because that user's admin access is inherited rather than direct; then
`==> Dry run (-n), nothing changed.` Exit 0, nothing written.

- [ ] **Step 4: Verify the not-found error path**

```bash
DALMATIAN_SKIP_UPDATE_CHECK=1 ./bin/dalmatian aws remove-user -n -y -e nobody-here@example.com 2>&1; echo "exit=$?"
```

Expected: `[!] Error: no Identity Center user with username 'nobody-here@example.com'. Nothing to
remove.` and `exit=1`.

- [ ] **Step 5: Verify the invalid-email and missing-argument paths**

```bash
DALMATIAN_SKIP_UPDATE_CHECK=1 ./bin/dalmatian aws remove-user -n -e not-an-email 2>&1 | head -2; echo "exit=$?"
DALMATIAN_SKIP_UPDATE_CHECK=1 ./bin/dalmatian aws remove-user -n 2>&1 | head -2
```

Expected: `[!] Error: not a valid email address: not-an-email` with exit 1; then the usage
block, because `-e` is required.

- [ ] **Step 6: Verify the hidden-plan guard**

```bash
OUT=$(mktemp)
(sleep 2; printf '\n'; sleep 2) | DALMATIAN_SKIP_UPDATE_CHECK=1 \
  script -q /dev/null bash -c "./bin/dalmatian aws remove-user -e jane.doe@example.com > $OUT; echo exit=\$?" 2>&1 | tr -d '\r' | tail -6
rm -f "$OUT"
```

Expected: `refusing to ask for confirmation when the plan cannot be shown.` and `exit=1`. The
prompt must never appear. This is the same protection `add-user` has.

- [ ] **Step 7: Confirm completions pick both commands up**

```bash
./bin/dalmatian -l | grep -E 'list-users|remove-user|add-user'
```

Expected: all three listed under the `aws` subcommand. No registration is needed; completion
and listing both scan the filesystem.

---

### Task 5: Documentation and commit

**Files:**
- Commit: the eight lib files, `bin/aws/v2/add-user`, `bin/aws/v2/list-users`,
  `bin/aws/v2/remove-user`, and the spec and plan for this change.

- [ ] **Step 1: Full lint and suppression check**

```bash
./test.sh && echo "SHELLCHECK OK"
grep -rn 'shellcheck disable' bin/aws/v2/add-user bin/aws/v2/list-users bin/aws/v2/remove-user lib/bash-functions/ || echo "no suppressions"
```

Expected: `SHELLCHECK OK` and `no suppressions`.

- [ ] **Step 2: Confirm no probe file survived Task 1**

```bash
ls bin/aws/v2/export-probe 2>/dev/null && echo "DELETE THIS" || echo "clean"
```

Expected: `clean`.

- [ ] **Step 3: Review the whole diff**

```bash
git status --short
git diff
```

Expected: eight new lib files, two new commands, one modified command, two new docs. Nothing
else. Read it before staging.

- [ ] **Step 4: Stage and commit (ask first)**

```bash
git add lib/bash-functions/die.sh lib/bash-functions/esc_msg.sh \
  lib/bash-functions/esc_info.sh lib/bash-functions/load_aws_sso_setup.sh \
  lib/bash-functions/aws_profile_exists.sh \
  lib/bash-functions/resolve_identity_center_profile.sh \
  lib/bash-functions/identity_center_instance.sh \
  lib/bash-functions/require_visible_plan.sh \
  bin/aws/v2/add-user bin/aws/v2/list-users bin/aws/v2/remove-user \
  docs/superpowers/specs/2026-08-21-aws-user-management-design.md \
  docs/superpowers/plans/2026-08-21-aws-user-management.md
git commit -m "Add aws list-users and remove-user commands"
```

Stage only those paths. `TODO.md`, `stderr.log`, `stdout.log` and the other untracked files
under `docs/` are pre-existing local state and must stay untracked.

- [ ] **Step 5: The destructive path**

Not exercised by this plan. `remove-user`'s delete path must be run once against a user the
repo owner nominates, with them present. Every step is idempotent, so a partial failure is safe
to re-run.

---

## Deferred

- **`-y` with redirected stdout leaves no record.** `require_visible_plan` exempts `-y`, and
  quiet mode then suppresses both the plan and the restore line, so
  `remove-user -e x -y > audit.log` deletes a user and writes an empty log. Fix would be to route
  `print_plan` and `print_restore_line` to stderr unconditionally, as `err` and `warning` already
  are. Raised in review and consciously deferred.
- **No self-removal guard.** Nothing stops `remove-user -e <your own username>`. Run from the
  management account under the admin permission set, an operator can delete their own Identity
  Center identity, and if they are the sole assignee of that permission set, lock the
  organisation out of Identity Center administration. `export_aws_caller_identity_username`
  already implements the `${arn##*/}` extraction needed to detect this. Raised in review and
  consciously deferred.
- **Minor review findings not actioned:** byte-versus-character padding means non-ASCII names
  (`Zoë`) lose one column of alignment per non-ASCII character; `remove-user` silently ignores
  stray non-option arguments; `wait_for_revocations` polls the full two minutes on an
  unparseable response rather than bailing early; a restore line is unusable if a
  `describe-permission-set` or `describe-group` lookup fell back to a raw identifier; a `die`
  inside `user_groups_json`'s command substitution prints two error lines; and Identity Center
  *application* assignments are not revoked, so the "leaves nothing behind" claim is true only
  for account assignments and group memberships.
- **`do_revoke_assignments` and `wait_for_revocations` have never executed.** No user in the
  directory has a direct account assignment — all access is group-based — so the revoke path was
  reviewed against the bundled botocore model rather than run. Every flag name, `--query` path
  and JSON path was confirmed correct that way, but it remains unexecuted code.
- The `add-user` minors recorded in `docs/superpowers/plans/2026-08-20-aws-add-user.md`,
  including the `REUSE` display-name bug, the `ASSIGNMENT_REQUESTS` separator, and the
  `fzf --multi` "no groups" asymmetry.
- **`./test.sh` does not fail on shellcheck findings.** It runs
  `find ... -exec shellcheck -x {} +`, and `find` does not propagate the command's exit status,
  so the script exits 0 even when shellcheck reports problems. Verified during this change.
  Every lint claim in this plan was therefore checked by running `shellcheck -x` directly and
  requiring empty output. Worth fixing separately — CI could be green with real findings.
- `bin/terraform-dependencies/v2/set-tfvars` has the same hidden-plan-but-still-prompting shape
  that `require_visible_plan` now fixes here, and there `yes_no` defaults to yes. It could adopt
  `require_visible_plan` directly.
- `list-users` shows group membership but not direct account assignments, which would cost one
  call per user. Add only if an audit actually needs it.
- Neither new command has a v1 equivalent.
