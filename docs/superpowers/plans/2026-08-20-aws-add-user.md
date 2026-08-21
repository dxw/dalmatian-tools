# `dalmatian aws add-user` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the standalone `add-aws-sso-user.sh` into dalmatian-tools as `dalmatian aws add-user`, a v2 command that creates an AWS IAM Identity Center user, adds them to groups, and grants permission sets on accounts.

**Architecture:** A single executable Bash script at `bin/aws/v2/add-user`, vendored from the standalone script and then adapted in four passes: AWS profile resolution, output functions, interaction helpers, and comments. The command derives its own `dalmatian-identity-center` SSO profile for the organisation's management account, because dalmatian's generated config contains no profile for it.

**Tech Stack:** Bash 4+, `aws` CLI v2 (`sso-admin`, `identitystore`, `organizations`), `jq`, optional `fzf`, `shellcheck`.

**Spec:** `docs/superpowers/specs/2026-08-20-aws-add-user-design.md`. Read it before starting. Where this plan and the spec disagree, the spec wins.

## Global Constraints

- **Source of truth for the port:** `/Users/bob/bin/add-aws-sso-user.sh`, sha256
  `897486b1e398061a2b4b944f3e5fb95f3b92a3a2464be7d7997937cbee5f2166`. Verify the checksum
  before Task 1. If it does not match, stop and ask — the file has changed since the spec
  was written.
- **Branch:** `add-aws-sso-user`, already created. Do not create a worktree.
- **No unit tests.** This is a deliberate decision recorded in the spec: dalmatian-tools has
  no unit test framework and the standalone script's suite is not being ported. The test
  cycle for every task is therefore `bash -n` (syntax), `./test.sh` (shellcheck), and a
  named manual check. Do not invent a test framework.
- **`./test.sh` must exit 0 after every task**, with no new `# shellcheck disable=` comments.
  If shellcheck objects, fix the code, do not silence the check.
- **Ask the user before every `git commit`.** `AGENTS.md` forbids committing autonomously.
  Each task below ends with a commit step, but on the run that produced this branch the user
  asked for a single squashed commit at the end instead. The per-task commit steps were
  therefore skipped and Task 6 Step 7 covers everything. Keep the per-task steps in the plan:
  they are the right default if this is ever re-run.
- **All status output goes through `log_info` / `log_msg` / `warning` / `err`**, never bare
  `echo` or `printf`. Build the string with `printf` first and pass it as `-l "$(printf ...)"`
  so dynamic values can never be read as printf directives.
- **Always pass `-q "$QUIET_MODE"` to `log_info` and `log_msg`.** Both functions assign to the
  global `QUIET_MODE` themselves, so omitting `-q` silently resets it to `0` for the rest of
  the script.
- **Never call `log_info` or `log_msg` from inside a function that is itself part-way through
  a `getopts` loop.** `log_info` sets `OPTIND=1` without declaring it `local`, so it would
  reset the caller's option parsing. Only `parse_args` uses `getopts`, and it must stay free
  of logging calls.
- **Interactive prompts keep raw `printf ... >&2`.** `bin/dalmatian` forces `QUIET_MODE=1`
  whenever stdout is not a TTY, so a prompt routed through `log_msg` would leave a piped run
  hanging at an invisible question. This applies to `read_line_or_die`, `_numbered_select`,
  and `usage`.
- **`err` does not exit.** Keep the local `die` function for fatal errors.
- **Do not add unit tests, a v1 equivalent, `fzf` to the `Brewfile`, or `README.md` entries.**
  All four are explicit non-goals.

## File Structure

| File | Change | Responsibility |
| --- | --- | --- |
| `bin/aws/v2/add-user` | Create (executable) | The entire command. Self-contained, as every other v2 command is. |
| `docs/superpowers/specs/2026-08-20-aws-add-user-design.md` | Already written, uncommitted | Design record. Committed in Task 6. |
| `docs/superpowers/plans/2026-08-20-aws-add-user.md` | This file, uncommitted | Committed in Task 6. |

Nothing else is touched. Completions auto-discover commands from the filesystem, `README.md`
does not enumerate commands, and the `Brewfile` already declares `awscli`, `bash` and `jq`.

The script keeps the standalone version's function decomposition rather than being split
across files — every other command in `bin/` is a single file, and the functions are already
small and single-purpose.

---

### Task 1: Vendor the script as a v2 command

Gets the command in place and discoverable, with the two constructs that only made sense in
its old home removed. At the end of this task the command runs and prints help, but will
fail at `preflight` because `org.admin` is not a profile in dalmatian's config. Task 2 fixes
that.

The profile variables are deliberately left alone here. `aws_admin` and `print_plan` both
reference `$PROFILE`, so removing its assignment in this task would leave those references
dangling — a shellcheck SC2154 failure and, at runtime under `set -u`, a fatal unbound
variable. The whole profile swap therefore happens in one task, Task 2.

**Files:**
- Create: `bin/aws/v2/add-user` (from `/Users/bob/bin/add-aws-sso-user.sh`)

**Interfaces:**
- Consumes: nothing.
- Produces: `bin/aws/v2/add-user`, executable, containing every function named in later
  tasks: `usage`, `die`, `aws_admin`, `parse_args`, `validate_email`, `derive_names`,
  `read_line_or_die`, `prompt_identity`, `preflight`, `_numbered_select`,
  `fzf_status_or_die`, `select_many`, `select_one`, `load_directory`, `resolve_group`,
  `resolve_permission_set`, `resolve_account`, `assignment_key`, `lookup_user`,
  `parse_grant_arg`, `load_current_state`, `print_plan`, `confirm`, `do_create_user`,
  `do_add_groups`, `do_add_assignments`, `wait_for_assignments`, `collect_inputs`,
  `print_summary`, `main`. Also produces the globals `DEFAULT_PROFILE` and `PROFILE`,
  unchanged from the source and consumed by Task 2.

- [ ] **Step 1: Verify the source file has not changed**

```bash
cd /Users/bob/git/dxw/dalmatian-tools
shasum -a 256 /Users/bob/bin/add-aws-sso-user.sh
```

Expected: `897486b1e398061a2b4b944f3e5fb95f3b92a3a2464be7d7997937cbee5f2166`. If it differs,
stop and ask the user.

- [ ] **Step 2: Confirm you are on the right branch and the baseline is clean**

```bash
git branch --show-current && ./test.sh && echo "BASELINE OK"
```

Expected: `add-aws-sso-user`, then `BASELINE OK` with no shellcheck output.

- [ ] **Step 3: Copy the script into place and make it executable**

```bash
cp /Users/bob/bin/add-aws-sso-user.sh bin/aws/v2/add-user
chmod +x bin/aws/v2/add-user
```

- [ ] **Step 4: Replace the file header**

The header describes a standalone script, including a bash version requirement that
`bin/dalmatian` now enforces before dispatch. Replace lines 1 through 13 — everything from
the shebang down to and including the `# Requires bash 4+ ...` line and the blank comment
line after it — with:

```bash
#!/usr/bin/env bash

# Add a user to AWS IAM Identity Center (SSO).
#
# Creates the user in the identity store, adds them to groups, and grants
# permission sets on specific accounts. Idempotent: re-running tops up whatever
# is missing rather than failing.
#
# NOTE: there is no API to send the Identity Center invitation email. This
# command creates and authorises the user; sending them their login must still
# be done from the console. The command prints the URL when it finishes.
#
# Uses fzf if it is installed and DALMATIAN_FZF_ENABLED is not 0, and falls back
# to a numbered menu otherwise.
```

- [ ] **Step 5: Remove the bash version guard**

Delete this whole block, comment included. `bin/dalmatian` calls `check_bash_version` before
dispatching to any command, so this is now dead code.

Remove:

```bash
# Must run before any bash-4-only feature (${var^}, associative arrays,
# readarray) is reached. Placed here rather than in preflight() because the
# harness sources this file without ever calling main(), and a failure that
# only surfaces after the operator has typed their email is a poor
# diagnostic. Verified this guard itself runs cleanly under bash 3.2.
if ((BASH_VERSINFO[0] < 4)); then
  printf 'Error: this script requires bash 4 or later (found %s). macOS ships bash 3.2 as /bin/bash; install a newer bash (e.g. via "brew install bash") and run this script with that instead.\n' \
    "$BASH_VERSION" >&2
  exit 1
fi
```

- [ ] **Step 6: Remove the matching note in `preflight`**

Remove the first comment inside `preflight`, which exists only to explain where the deleted
guard lived:

```bash
  # NOTE: the bash 4+ assertion is NOT here. It lives at the top level of the
  # script, immediately after `set -euo pipefail`, added in Task 2 — it must run
  # before the first `${var^}`, and the harness sources the script without going
  # through main. Do not duplicate it here.

```

`preflight` should now open directly with the `command -v aws` check.

- [ ] **Step 7: Retarget the usage text at the dalmatian command name**

`usage` still names a script on `$PATH`. Change only the invocation names; the `-p` line is
rewritten in Task 2, once there is a new default to describe.

Inside the `cat >&2 <<EOF` heredoc, replace:

```bash
Usage: $(basename "$0") [-e email] [-f first] [-l last] [-g group]... [-a permset:account]... [-p profile] [-n] [-y]
```

with:

```bash
Usage: dalmatian aws add-user [-e email] [-f first] [-l last] [-g group]... [-a permset:account]... [-p profile] [-n] [-y]
```

Then replace the two example lines:

```bash
  $(basename "$0") -e jane.doe@example.com
  $(basename "$0") -e jane.doe@example.com -f Jane -l Doe -g contractors \\
      -a admin:my-account -a read-only:123456789012 -y
```

with:

```bash
  dalmatian aws add-user -e jane.doe@example.com
  dalmatian aws add-user -e jane.doe@example.com -f Jane -l Doe -g contractors \\
      -a admin:my-account -a read-only:123456789012 -y
```

`usage` keeps `cat >&2` rather than `log_msg`: help must appear even when the dispatcher has
forced quiet mode.

- [ ] **Step 8: Replace the `main` invocation guard**

Nothing sources this file, so the guard is dead. Replace:

```bash
# Only run when executed, not when sourced by the tests.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
```

with:

```bash
main "$@"
```

- [ ] **Step 9: Syntax check**

```bash
bash -n bin/aws/v2/add-user && echo "SYNTAX OK"
```

Expected: `SYNTAX OK`.

- [ ] **Step 10: Shellcheck**

```bash
./test.sh && echo "SHELLCHECK OK"
```

Expected: `SHELLCHECK OK` with no findings. Nothing dangles at this point — `DEFAULT_PROFILE`
and `PROFILE` are still assigned and still used, so there is no unbound-variable or SC2154
exposure.

- [ ] **Step 11: Confirm the command is discoverable and help works**

```bash
./bin/dalmatian aws add-user -h
```

Expected: the usage block, headed `Usage: dalmatian aws add-user ...`, exit status 1.

```bash
./bin/dalmatian -l | grep 'add-user'
```

Expected: `add-user` listed under the `aws` subcommand.

- [ ] **Step 12: Commit (ask first)**

```bash
git add bin/aws/v2/add-user
git commit -m "Add aws add-user command, vendored from add-aws-sso-user.sh"
```

---

### Task 2: Resolve the Identity Center admin profile

Replaces the hardcoded `org.admin` default with a profile the command derives and, if
necessary, writes for itself. This is the only part of the port that is new code rather than
a substitution.

Validated live before this plan was written: `organizations describe-organization` from
`dalmatian-main` returns `111122223333`; a profile built as below authenticates off the
existing SSO token cache with no extra `aws sso login`; and `sso-admin list-instances` from
it returns exactly one instance with both `InstanceArn` and `IdentityStoreId` populated.

**Files:**
- Modify: `bin/aws/v2/add-user`

**Interfaces:**
- Consumes: `DEFAULT_PROFILE`, `PROFILE`, `die`, `usage`, `parse_args`, `preflight`,
  `aws_admin`, `print_plan`, `print_summary` from Task 1. From the dispatcher:
  `$CONFIG_SETUP_JSON_FILE`, `$CONFIG_AWS_SSO_FILE`, `$AWS_CONFIG_FILE`, `$QUIET_MODE`, and
  the exported `append_sso_config_file` function.
- Produces: globals `IDENTITY_CENTER_PROFILE_NAME`, `IDENTITY_CENTER_PROFILE`,
  `PROFILE_OVERRIDE`, `AWS_SSO_START_URL`, `AWS_SSO_REGION`, `AWS_SSO_ADMIN_ROLE_NAME`,
  `CONSOLE_USERS_URL`. New functions: `load_setup_config` (no args, sets the four values
  above), `profile_exists <name>` (returns 0 if the named profile is in the config file, 1
  otherwise), `resolve_identity_center_profile` (no args, sets `IDENTITY_CENTER_PROFILE`).
  Removes `DEFAULT_PROFILE` and `PROFILE`.

- [ ] **Step 1: Replace the profile globals**

Replace:

```bash
DEFAULT_PROFILE="org.admin"
PROFILE="$DEFAULT_PROFILE"
EMAIL=""
```

with:

```bash
# The SSO profile used to administer Identity Center. It targets the
# organisation's management account, which `dalmatian aws generate-config` does
# not write a profile for, so resolve_identity_center_profile creates it.
IDENTITY_CENTER_PROFILE_NAME="dalmatian-identity-center"
IDENTITY_CENTER_PROFILE=""
PROFILE_OVERRIDE=""
EMAIL=""
```

- [ ] **Step 2: Document the new `-p` default in `usage`**

Replace:

```bash
  -p <profile>          AWS profile (default: $DEFAULT_PROFILE)
```

with:

```bash
  -p <profile>          AWS profile to administer Identity Center with.
                        Defaults to $IDENTITY_CENTER_PROFILE_NAME, which is
                        created automatically if it does not already exist
```

The heredoc is unquoted (`<<EOF`), so `$IDENTITY_CENTER_PROFILE_NAME` expands. It is assigned
at the top level, well before `parse_args` can call `usage`.

- [ ] **Step 3: Point `-p` at the override variable**

In `parse_args`, replace:

```bash
    p) PROFILE="$OPTARG" ;;
```

with:

```bash
    p) PROFILE_OVERRIDE="$OPTARG" ;;
```

- [ ] **Step 4: Derive the console URL from config instead of hardcoding a region**

Replace:

```bash
CONSOLE_USERS_URL="https://eu-west-2.console.aws.amazon.com/singlesignon/identity/home?region=eu-west-2#!/users"
```

with:

```bash
# Populated by load_setup_config from the Identity Center region, rather than
# hardcoding one, since print_summary is the operator's only pointer at the
# console step this command cannot do for them.
CONSOLE_USERS_URL=""
AWS_SSO_START_URL=""
AWS_SSO_REGION=""
AWS_SSO_ADMIN_ROLE_NAME=""
```

- [ ] **Step 5: Add the setup.json loader**

Insert immediately above `preflight`:

```bash
# Reads the three AWS SSO values this command needs out of setup.json, and
# derives the console URL from the Identity Center region. Every value is
# checked: `jq -r` prints the literal string "null" for a missing field, which
# would otherwise be silently built into an SSO profile or a URL and only fail
# much later as an opaque AWS error.
load_setup_config() {
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

- [ ] **Step 6: Add the profile existence helper**

Insert immediately after `load_setup_config`:

```bash
# `aws configure list-profiles` reads whatever AWS_CONFIG_FILE points at, which
# bin/dalmatian has already overridden to the Dalmatian SSO config, so this
# checks the right file without naming it. Deliberately an exact match, not a
# grep of the file: a profile name that is a substring of another must not
# satisfy the lookup.
profile_exists() {
  local wanted=$1 profile
  while IFS='' read -r profile
  do
    if [[ "$profile" == "$wanted" ]]
    then
      return 0
    fi
  done < <(aws configure list-profiles)
  return 1
}
```

- [ ] **Step 7: Add the profile resolver**

Insert immediately after `profile_exists`:

```bash
# Sets IDENTITY_CENTER_PROFILE to a profile that can administer Identity
# Center. The instance lives in the organisation's management account, which is
# not a Dalmatian-managed Terraform workspace and therefore gets no profile from
# `dalmatian aws generate-config` — so when no usable profile exists, this
# discovers the account and writes one.
resolve_identity_center_profile() {
  if [[ -n "$PROFILE_OVERRIDE" ]]
  then
    profile_exists "$PROFILE_OVERRIDE" ||
      die "profile '$PROFILE_OVERRIDE' is not in $AWS_CONFIG_FILE.
       Try running \`dalmatian aws generate-config\` first."
    IDENTITY_CENTER_PROFILE=$PROFILE_OVERRIDE
    return 0
  fi

  if profile_exists "$IDENTITY_CENTER_PROFILE_NAME"
  then
    IDENTITY_CENTER_PROFILE=$IDENTITY_CENTER_PROFILE_NAME
    return 0
  fi

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

  log_info -l "$(printf "Adding the '%s' profile for management account %s" \
    "$IDENTITY_CENTER_PROFILE_NAME" "$management_account_id")" -q "$QUIET_MODE"

  # The profile's region is the Identity Center region, not the project's
  # default region: sso-admin and identitystore calls have to be made in the
  # region the instance lives in. They are often the same value, which is
  # exactly why this is worth stating.
  #
  # append_sso_config_file appends blind with no existence check of its own, so
  # the profile_exists call above is the whole of the idempotency. Note that
  # `dalmatian aws generate-config` rewrites this file wholesale and will drop
  # this profile; that costs nothing, because the next run re-adds it.
  append_sso_config_file \
    "$CONFIG_AWS_SSO_FILE" \
    "$IDENTITY_CENTER_PROFILE_NAME" \
    "$AWS_SSO_START_URL" \
    "$AWS_SSO_REGION" \
    "$management_account_id" \
    "$AWS_SSO_ADMIN_ROLE_NAME" \
    "$AWS_SSO_REGION"

  IDENTITY_CENTER_PROFILE=$IDENTITY_CENTER_PROFILE_NAME
}
```

No `aws sso login` is needed afterwards. `bin/dalmatian` has already logged in before
dispatching, and the SSO token cache is keyed on `sso_start_url`, which is identical across
every profile in this config.

- [ ] **Step 8: Point `aws_admin` at the resolved profile**

Replace:

```bash
# All AWS calls funnel through here, so the profile is named once and tests have
# a single function to override.
aws_admin() {
  aws --profile "$PROFILE" "$@"
}
```

with:

```bash
# All AWS calls funnel through here, so the profile is named in exactly one
# place. Set by resolve_identity_center_profile before any call is made.
aws_admin() {
  aws --profile "$IDENTITY_CENTER_PROFILE" "$@"
}
```

- [ ] **Step 9: Wire both new functions into `preflight`**

In `preflight`, after the `command -v jq` check and the fzf detection block, and immediately
before the `sts get-caller-identity` check, insert:

```bash
  load_setup_config
  resolve_identity_center_profile
```

- [ ] **Step 10: Widen the authentication failure advice**

The likeliest cause is no longer only an expired session. Replace:

```bash
  local auth_err
  if ! auth_err=$(aws_admin sts get-caller-identity 2>&1 >/dev/null); then
    die "cannot authenticate with profile '$PROFILE': ${auth_err:-unknown error}
       If the session has merely expired, run: aws sso login --profile $PROFILE"
  fi
```

with:

```bash
  local auth_err
  if ! auth_err=$(aws_admin sts get-caller-identity 2>&1 >/dev/null); then
    die "cannot authenticate with profile '$IDENTITY_CENTER_PROFILE': ${auth_err:-unknown error}
       This usually means one of two things. Either the SSO session has expired,
       in which case run: dalmatian aws login
       Or you have no '$AWS_SSO_ADMIN_ROLE_NAME' permission set assigned on the
       organisation's management account, which no amount of logging in will fix."
  fi
```

The comment above this block, explaining why the underlying error is kept rather than
discarded, stays as it is.

- [ ] **Step 11: Report the resolved profile in the plan**

In `print_plan`, replace:

```bash
  printf '  profile:        %s\n' "$PROFILE"
```

with:

```bash
  printf '  profile:        %s\n' "$IDENTITY_CENTER_PROFILE"
```

This line is converted to `log_msg` in Task 3; only the variable changes here. The operator
needs to see which profile was resolved before approving the plan, because in the discovery
case they never named it.

- [ ] **Step 12: Confirm no reference to the old variable survives**

```bash
grep -n 'PROFILE\b' bin/aws/v2/add-user | grep -v 'IDENTITY_CENTER_PROFILE\|PROFILE_OVERRIDE\|AWS_PROFILE'
```

Expected: no output. Any hit is a leftover reference to the deleted `PROFILE` variable.

- [ ] **Step 13: Syntax and lint**

```bash
bash -n bin/aws/v2/add-user && ./test.sh && echo "OK"
```

Expected: `OK`.

- [ ] **Step 14: Manual check — discovery writes the profile once, then reuses it**

First, prove the profile is absent and note the config file size:

```bash
grep -c 'dalmatian-identity-center' ~/.config/dalmatian/dalmatian-sso.config || true
```

Expected: `0`.

Then run a dry run and abort at the first prompt with Ctrl-C once the plan is not needed —
or better, drive it non-interactively:

```bash
./bin/dalmatian aws add-user -n -y -e "$(git config --get user.email)"
```

Expected: an `==> Adding the 'dalmatian-identity-center' profile for management account
111122223333` line, then a Plan block whose `profile:` line reads
`dalmatian-identity-center` and whose `identity store:` line is populated. Exit status 0,
nothing written to AWS.

```bash
grep -c 'dalmatian-identity-center' ~/.config/dalmatian/dalmatian-sso.config
```

Expected: `1`.

Run the same command again. Expected: no `Adding the ... profile` line this time, and the
count above still `1` — proving the `profile_exists` check makes it idempotent.

- [ ] **Step 15: Manual check — the `-p` override rejects a bogus profile**

```bash
./bin/dalmatian aws add-user -n -y -p definitely-not-a-profile -e nobody@example.com
```

Expected: `[!] Error: profile 'definitely-not-a-profile' is not in ...` and exit status 1.

- [ ] **Step 16: Commit (ask first)**

```bash
git add bin/aws/v2/add-user
git commit -m "Derive an Identity Center admin profile in aws add-user"
```

---

### Task 3: Convert output to the toolkit's logging functions

**Files:**
- Modify: `bin/aws/v2/add-user`

**Interfaces:**
- Consumes: everything from Task 2. From the dispatcher: the exported `log_info`, `log_msg`,
  `warning`, `err` functions and `$QUIET_MODE`.
- Produces: no new functions. `die` changes implementation but keeps its signature
  (`die <message>`, prints and exits 1).

- [ ] **Step 1: Reimplement `die` on top of `err`**

`err` prints in red to stderr but does not exit, so `die` stays as a function. Replace:

```bash
die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}
```

with:

```bash
# `err` prints to stderr but does not exit, so this stays a function rather than
# becoming a bare `err` call.
die() {
  err "$1"
  exit 1
}
```

- [ ] **Step 2: Convert the three `Warning:` messages**

`warning` supplies its own `[!] Warning: ` prefix and writes to stderr unconditionally, so
the literal prefix goes and the quiet-mode question does not arise.

In `prompt_identity`, replace:

```bash
    printf 'Warning: %s is not a @example.com address.\n' "$EMAIL" >&2
```

with:

```bash
    warning "$(printf '%s is not a @example.com address.' "$EMAIL")"
```

In `load_directory`, replace:

```bash
        printf "Warning: organizations list-accounts returned an account with a missing Id or Name (Id='%s', Name='%s'); skipping this account.\n" \
          "$id" "$name" >&2
```

with:

```bash
        warning "$(printf "organizations list-accounts returned an account with a missing Id or Name (Id='%s', Name='%s'); skipping this account." \
          "$id" "$name")"
```

In `load_current_state`, replace:

```bash
        printf 'Warning: sso-admin list-account-assignments-for-principal returned an assignment with an unrecognised PrincipalType (AccountId=%s, PermissionSetArn=%s, PrincipalType=%s, PrincipalId=%s); treating it as not held.\n' \
          "$acct" "$arn" "$ptype" "$pid" >&2
```

with:

```bash
        warning "$(printf 'sso-admin list-account-assignments-for-principal returned an assignment with an unrecognised PrincipalType (AccountId=%s, PermissionSetArn=%s, PrincipalType=%s, PrincipalId=%s); treating it as not held.' \
          "$acct" "$arn" "$ptype" "$pid")"
```

- [ ] **Step 3: Convert `print_plan`**

`log_info` prefixes `==> ` itself, so converted `==>` lines drop the literal. Replace the
whole body of `print_plan` — every `printf` in it, keeping every comment and every
conditional exactly as they are — with:

```bash
print_plan() {
  log_msg -l "" -q "$QUIET_MODE"
  log_msg -l "Plan" -q "$QUIET_MODE"
  log_msg -l "====" -q "$QUIET_MODE"
  if ((DRY_RUN)); then
    log_msg -l "" -q "$QUIET_MODE"
    log_msg -l "  DRY RUN — no changes will be made" -q "$QUIET_MODE"
    log_msg -l "" -q "$QUIET_MODE"
  fi
  log_msg -l "$(printf '  profile:        %s' "$IDENTITY_CENTER_PROFILE")" -q "$QUIET_MODE"
  log_msg -l "$(printf '  identity store: %s' "$IDENTITY_STORE_ID")" -q "$QUIET_MODE"
  log_msg -l "$(printf '  username:       %s' "$EMAIL")" -q "$QUIET_MODE"
  log_msg -l "$(printf '  display name:   %s %s' "$FIRST_NAME" "$LAST_NAME")" -q "$QUIET_MODE"

  if ((USER_EXISTS)); then
    log_msg -l "$(printf '  user:           REUSE existing user (%s)' "$USER_ID")" -q "$QUIET_MODE"
  else
    log_msg -l "  user:           CREATE new user" -q "$QUIET_MODE"
  fi

  log_msg -l "" -q "$QUIET_MODE"
  log_msg -l "  Groups:" -q "$QUIET_MODE"
  if ((${#TARGET_GROUP_IDS[@]} == 0)); then
    log_msg -l "    (none)" -q "$QUIET_MODE"
  else
    local gid gname
    for gid in "${TARGET_GROUP_IDS[@]}"; do
      gname=${GROUP_ID_TO_NAME[$gid]:-$gid}
      if [[ -n "${EXISTING_MEMBERSHIP[$gid]:-}" ]]; then
        log_msg -l "$(printf "    skip   already a member of '%s'" "$gname")" -q "$QUIET_MODE"
      else
        log_msg -l "$(printf "    ADD    add to '%s'" "$gname")" -q "$QUIET_MODE"
      fi
    done
  fi

  log_msg -l "" -q "$QUIET_MODE"
  log_msg -l "  Account grants:" -q "$QUIET_MODE"
  if ((${#GRANTS[@]} == 0)); then
    log_msg -l "    (none)" -q "$QUIET_MODE"
  else
    local entry arn account_id ps_name account_name key via
    for entry in "${GRANTS[@]}"; do
      IFS="$GRANT_TUPLE_SEP" read -r arn account_id ps_name account_name <<<"$entry"
      key=$(assignment_key "$account_id" "$arn")
      if [[ -n "${DIRECT_ASSIGNMENT[$key]:-}" ]]; then
        log_msg -l "$(printf "    skip   already granted directly: '%s' on %s (%s)" \
          "$ps_name" "$account_name" "$account_id")" -q "$QUIET_MODE"
      elif [[ -n "${INHERITED_ASSIGNMENT[$key]:-}" ]]; then
        via=${INHERITED_ASSIGNMENT[$key]}
        log_msg -l "$(printf "    ADD    grant '%s' on %s (%s)  [redundant — inherited from group '%s']" \
          "$ps_name" "$account_name" "$account_id" "$via")" -q "$QUIET_MODE"
      else
        log_msg -l "$(printf "    ADD    grant '%s' on %s (%s)" "$ps_name" "$account_name" "$account_id")" -q "$QUIET_MODE"
      fi
    done
  fi
  log_msg -l "" -q "$QUIET_MODE"
}
```

Keep all four explanatory comments from the original body in place: the one about `DRY_RUN`
only affecting whether writes follow, the one about the `redundant` grant still being
created, the one about `GRANT_TUPLE_SEP` and field order, and the function's own header
comment. Only the `printf`-versus-`log_msg` mechanics change. Two notes on the header
comment: the reference to "Task 8" is fixed in Task 5, and the sentence about the trailing
`printf` having to stay unconditional to avoid tripping `set -e` no longer applies once the
final statement is a `log_msg` call that always returns 0 — reword it in Task 5 rather than
deleting the reasoning.

- [ ] **Step 4: Convert `do_create_user`**

Replace:

```bash
  if ((USER_EXISTS)); then
    printf '==> Reusing existing user %s (%s)\n' "$EMAIL" "$USER_ID"
    return 0
  fi

  printf '==> Creating user %s\n' "$EMAIL"
```

with:

```bash
  if ((USER_EXISTS)); then
    log_info -l "$(printf 'Reusing existing user %s (%s)' "$EMAIL" "$USER_ID")" -q "$QUIET_MODE"
    return 0
  fi

  log_info -l "$(printf 'Creating user %s' "$EMAIL")" -q "$QUIET_MODE"
```

and replace:

```bash
  printf '    UserId: %s\n' "$USER_ID"
```

with:

```bash
  log_msg -l "$(printf '    UserId: %s' "$USER_ID")" -q "$QUIET_MODE"
```

- [ ] **Step 5: Convert `do_add_groups`**

Replace:

```bash
    if [[ -n "${EXISTING_MEMBERSHIP[$gid]:-}" ]]; then
      printf "==> Already a member of '%s', skipping\n" "$gname"
      continue
    fi

    printf "==> Adding to group '%s'\n" "$gname"
```

with:

```bash
    if [[ -n "${EXISTING_MEMBERSHIP[$gid]:-}" ]]; then
      log_info -l "$(printf "Already a member of '%s', skipping" "$gname")" -q "$QUIET_MODE"
      continue
    fi

    log_info -l "$(printf "Adding to group '%s'" "$gname")" -q "$QUIET_MODE"
```

and replace:

```bash
      if [[ "$out" == *ConflictException* ]]; then
        printf '    already a member, skipping\n'
      else
        printf "    FAILED to add to '%s': %s\n" "$gname" "$out" >&2
        FAILURES=$((FAILURES + 1))
      fi
```

with:

```bash
      if [[ "$out" == *ConflictException* ]]; then
        log_msg -l "    already a member, skipping" -q "$QUIET_MODE"
      else
        err "$(printf "failed to add to group '%s': %s" "$gname" "$out")"
        FAILURES=$((FAILURES + 1))
      fi
```

`err` is right here rather than `warning`: this is a genuine failure that is counted and
reported at the end, it is simply not fatal to the rest of the run.

- [ ] **Step 6: Convert `do_add_assignments`**

Replace:

```bash
    if [[ -n "${DIRECT_ASSIGNMENT[$key]:-}" ]]; then
      printf '==> Already granted directly: %s, skipping\n' "$desc"
      continue
    fi

    printf '==> Granting %s\n' "$desc"
```

with:

```bash
    if [[ -n "${DIRECT_ASSIGNMENT[$key]:-}" ]]; then
      log_info -l "$(printf 'Already granted directly: %s, skipping' "$desc")" -q "$QUIET_MODE"
      continue
    fi

    log_info -l "$(printf 'Granting %s' "$desc")" -q "$QUIET_MODE"
```

replace:

```bash
      if [[ "$out" == *ConflictException* ]]; then
        printf '    already granted, skipping\n'
      else
        printf '    FAILED to grant %s: %s\n' "$desc" "$out" >&2
        FAILURES=$((FAILURES + 1))
      fi
```

with:

```bash
      if [[ "$out" == *ConflictException* ]]; then
        log_msg -l "    already granted, skipping" -q "$QUIET_MODE"
      else
        err "$(printf 'failed to grant %s: %s' "$desc" "$out")"
        FAILURES=$((FAILURES + 1))
      fi
```

and replace:

```bash
    if [[ -z "$request_id" || "$request_id" == "None" ]]; then
      printf '    FAILED to grant %s: create-account-assignment returned no RequestId\n' "$desc" >&2
      FAILURES=$((FAILURES + 1))
      continue
    fi
```

with:

```bash
    if [[ -z "$request_id" || "$request_id" == "None" ]]; then
      err "$(printf 'failed to grant %s: create-account-assignment returned no RequestId' "$desc")"
      FAILURES=$((FAILURES + 1))
      continue
    fi
```

- [ ] **Step 7: Convert `wait_for_assignments`**

Replace:

```bash
  printf '==> Waiting for %d assignment(s) to provision\n' "${#ASSIGNMENT_REQUESTS[@]}"
```

with:

```bash
  log_info -l "$(printf 'Waiting for %d assignment(s) to provision' "${#ASSIGNMENT_REQUESTS[@]}")" -q "$QUIET_MODE"
```

replace:

```bash
        printf '    WARNING could not check %s (%s): %s\n' "$desc" "$request_id" "$json" >&2
```

with:

```bash
        warning "$(printf 'could not check %s (%s): %s' "$desc" "$request_id" "$json")"
```

replace:

```bash
        printf '    ok %s\n' "$desc"
```

with:

```bash
        log_msg -l "$(printf '    ok %s' "$desc")" -q "$QUIET_MODE"
```

replace:

```bash
        printf '    FAILED %s: %s\n' "$desc" "$reason" >&2
```

with:

```bash
        err "$(printf '%s: %s' "$desc" "$reason")"
```

and replace:

```bash
      printf '    WARNING still in progress after timeout: %s (request %s)\n' \
        "$desc" "$request_id" >&2
```

with:

```bash
      warning "$(printf 'still in progress after timeout: %s (request %s)' \
        "$desc" "$request_id")"
```

- [ ] **Step 8: Convert `print_summary`**

Replace the whole body with:

```bash
print_summary() {
  log_msg -l "" -q "$QUIET_MODE"
  if ((FAILURES == 0)); then
    log_info -l "$(printf 'Done. %s is set up.' "$EMAIL")" -q "$QUIET_MODE"
  else
    log_info -l "$(printf 'Finished with %d failure(s). Re-run the same command to retry;' "$FAILURES")" -q "$QUIET_MODE"
    log_msg -l "    every step is idempotent." -q "$QUIET_MODE"
  fi
  log_msg -l "" -q "$QUIET_MODE"
  log_msg -l "REMINDER: no invitation email has been sent — there is no API for it." -q "$QUIET_MODE"
  log_msg -l "$(printf 'Send it from the console: %s' "$CONSOLE_USERS_URL")" -q "$QUIET_MODE"
  log_msg -l "$(printf 'Pick %s, then Reset password > "Send an email to the user".' "$EMAIL")" -q "$QUIET_MODE"
}
```

- [ ] **Step 9: Convert the two lines in `main`**

Replace:

```bash
    printf '==> Dry run (-n), nothing changed.\n'
```

with:

```bash
    log_info -l "Dry run (-n), nothing changed." -q "$QUIET_MODE"
```

and replace:

```bash
    printf '==> Aborted, nothing changed.\n'
```

with:

```bash
    log_info -l "Aborted, nothing changed." -q "$QUIET_MODE"
```

- [ ] **Step 10: Verify the only remaining `printf` calls are prompts**

```bash
grep -n 'printf' bin/aws/v2/add-user | grep -v '\$(printf'
```

Expected: exactly these, all of them interactive prompts or menu rendering that must bypass
quiet mode —

- in `read_line_or_die`: `printf '%s' "$1" >&2` and `printf '\n' >&2`
- in `prompt_identity`: `printf 'Not a valid email address.\n' >&2`
- in `_numbered_select`: the `%4d) %s` item line and the two prompt lines
- in `collect_inputs`: the `Add a permission set grant?` prompt, until Task 4 removes it
- in `confirm`: the `Proceed?` prompt, until Task 4 removes it

**And, critically, the `printf` calls that are function return values, not output.**
`_numbered_select`, `select_many`, `select_one`, `resolve_group`, `resolve_permission_set`,
`resolve_account` and `assignment_key` all emit their result on stdout for a caller to
capture with `$(...)`. Converting any of those to `log_msg` would break the function
outright — and worse, would break it *silently and only in quiet mode*, since `log_msg`
returns nothing when `QUIET_MODE=1`, so every lookup would resolve to an empty string. Leave
every one of them as `printf`. The same applies to the `printf` inside `resolve_group`'s
`die` message, which is a command substitution building a string.

Anything other than the above is a missed conversion.

- [ ] **Step 11: Verify no `log_info` or `log_msg` call omits `-q`**

```bash
grep -n 'log_info\|log_msg' bin/aws/v2/add-user | grep -v -- '-q "\$QUIET_MODE"'
```

Expected: no output. A call without `-q` resets the global `QUIET_MODE` to `0` and silently
breaks quiet mode for everything after it.

- [ ] **Step 12: Syntax and lint**

```bash
bash -n bin/aws/v2/add-user && ./test.sh && echo "OK"
```

Expected: `OK`.

- [ ] **Step 13: Manual check — output and quiet mode**

```bash
./bin/dalmatian aws add-user -n -y -e "$(git config --get user.email)"
```

Expected: the same Plan block as Task 2, now with `==>` lines in cyan.

```bash
./bin/dalmatian aws add-user -n -y -e "$(git config --get user.email)" | wc -l
```

Expected: `0`. Piping forces quiet mode, so the plan is suppressed. This confirms the
conversion is actually honouring `QUIET_MODE`.

- [ ] **Step 14: Commit (ask first)**

```bash
git add bin/aws/v2/add-user
git commit -m "Use dalmatian logging functions in aws add-user"
```

---

### Task 4: Adopt the toolkit's confirmation prompt and fzf convention

**Files:**
- Modify: `bin/aws/v2/add-user`

**Interfaces:**
- Consumes: everything from Task 3, plus the dispatcher's exported `yes_no <message> <default>`
  function, which returns 0 for yes and 1 for no.
- Produces: removes `confirm`. `HAVE_FZF` keeps its meaning (1 when fzf should be used).

- [ ] **Step 1: Adopt `DALMATIAN_FZF_ENABLED` in `preflight`**

This matches `bin/ec2/v2/shell` and `bin/terraform-dependencies/v2/set-tfvars`, and gives
operators a way to force the numbered fallback. Replace:

```bash
  if command -v fzf >/dev/null 2>&1; then
    HAVE_FZF=1
  else
    HAVE_FZF=0
  fi
```

with:

```bash
  # DALMATIAN_FZF_ENABLED=0 forces the numbered fallback, matching the
  # convention in bin/ec2/v2/shell and bin/terraform-dependencies/v2/set-tfvars.
  if [[ "${DALMATIAN_FZF_ENABLED:-1}" == "1" ]] && command -v fzf >/dev/null 2>&1; then
    HAVE_FZF=1
  else
    HAVE_FZF=0
  fi
```

- [ ] **Step 2: Delete `confirm`**

Remove the whole function and its comment block:

```bash
# The last gate before Task 8 writes anything to AWS. ASSUME_YES (-y) skips
# it outright. Otherwise only 'y' or 'Y' proceeds — `read`'s default IFS
# trims surrounding whitespace, so " y " also proceeds, but nothing else
# does. A reply that is empty once read returns — a bare enter, or a closed
# stdin hit before any byte arrives — aborts, as do 'n' and any other text.
# EOF on its own does not: `printf 'y' | confirm` with no trailing newline
# still proceeds, because `read` returns 1 on that EOF but `reply` already
# holds 'y' by then. Deliberately strict — a stray keystroke must never be
# read as authorisation to grant access.
confirm() {
  ((ASSUME_YES)) && return 0

  printf 'Proceed? [y/N] ' >&2
  local reply=""
  read -r reply || true
  [[ "$reply" == "y" || "$reply" == "Y" ]]
}
```

- [ ] **Step 3: Replace the gate in `main` with `yes_no`**

Replace:

```bash
  if ! confirm; then
    log_info -l "Aborted, nothing changed." -q "$QUIET_MODE"
    exit 0
  fi
```

with:

```bash
  # `-y` means non-interactive, so it skips the gate outright. Otherwise the
  # default is No: a stray keystroke must never be read as authorisation to
  # grant access. `yes_no` re-prompts on unrecognised input rather than
  # aborting, and on EOF falls through to the "n" default, so a closed stdin
  # still aborts before anything is written.
  if ((!ASSUME_YES)) && ! yes_no "Proceed? (y/N)" "n"
  then
    log_info -l "Aborted, nothing changed." -q "$QUIET_MODE"
    exit 0
  fi
```

- [ ] **Step 4: Replace the grant loop prompt with `yes_no`**

In `collect_inputs`, replace:

```bash
  local reply ps_name accounts account_line account_id
  while true; do
    printf 'Add a permission set grant? [y/N] ' >&2
    read -r reply || true
    [[ "$reply" == "y" || "$reply" == "Y" ]] || break
```

with:

```bash
  local ps_name accounts account_line account_id
  while true; do
    if ! yes_no "Add a permission set grant? (y/N)" "n"
    then
      break
    fi
```

Note `reply` is dropped from the `local` declaration — it has no other use in the function,
and shellcheck will flag it if left behind.

- [ ] **Step 5: Confirm both prompts are gone**

```bash
grep -n 'confirm\|read -r reply' bin/aws/v2/add-user
```

Expected: no output.

- [ ] **Step 6: Syntax and lint**

```bash
bash -n bin/aws/v2/add-user && ./test.sh && echo "OK"
```

Expected: `OK`.

- [ ] **Step 7: Manual check — the numbered fallback**

```bash
DALMATIAN_FZF_ENABLED=0 ./bin/dalmatian aws add-user -n -e "$(git config --get user.email)"
```

Expected: a numbered list of groups with a `Groups to join (comma-separated numbers, blank
for none):` prompt instead of an fzf window. Enter a blank line, then answer `n` to the
grant prompt. A Plan block follows, then `==> Dry run (-n), nothing changed.`

- [ ] **Step 8: Manual check — the confirmation gate defaults to No**

```bash
printf '\n\n\n' | ./bin/dalmatian aws add-user -e nobody-does-not-exist@example.com -f No -l Body
```

Expected: it reaches `Proceed? (y/N) [n]:`, takes the default, prints
`==> Aborted, nothing changed.` and exits 0 having written nothing. Confirm with
`echo $?` that the status is 0.

- [ ] **Step 9: Commit (ask first)**

```bash
git add bin/aws/v2/add-user
git commit -m "Use yes_no and DALMATIAN_FZF_ENABLED in aws add-user"
```

---

### Task 5: Rewrite comments that describe the old home

The port keeps the source script's comments deliberately — they record real reasoning about
real AWS behaviour. But some of them refer to a test harness that was not ported, or to
numbered tasks from the original build. Left as they are, they describe code that does not
exist, which is worse than no comment.

**Files:**
- Modify: `bin/aws/v2/add-user`

**Interfaces:**
- Consumes: everything from Task 4.
- Produces: no functional change. `./test.sh` and every manual check must behave identically
  before and after this task.

- [ ] **Step 1: Find every stale reference**

```bash
grep -n -i 'harness\|test suite\|tests \|Task [0-9]\|a later task\|an earlier draft\|stub' bin/aws/v2/add-user
```

Work through every hit. The known set is below; if the grep finds more, apply the same
principle — describe what the code does and why, never how it came to be written.

- [ ] **Step 2: `read_line_or_die` — drop the harness reference**

Replace:

```bash
# Read one line from stdin into REPLY_LINE, treating EOF as fatal.
# A bare `read` that hits EOF inside a `while [[ -z ... ]]` loop spins forever
# whenever `set -e` is not in force — which is the case inside the test harness.
```

with:

```bash
# Read one line from stdin into REPLY_LINE, treating EOF as fatal.
# A bare `read` that hits EOF inside a `while [[ -z ... ]]` loop spins forever
# whenever `set -e` is not in force, so EOF is handled explicitly rather than
# left to the loop guard.
```

- [ ] **Step 3: `load_directory` — drop the "a test calling it twice" reference**

Replace:

```bash
# Safe to call more than once: it clears its own state first, rather than
# accumulating, so a later re-run (or a test calling it twice) starts clean.
```

with:

```bash
# Safe to call more than once: it clears its own state first, rather than
# accumulating, so a second call starts clean.
```

- [ ] **Step 4: `load_directory` — rewrite the permission-set loop asymmetry note**

The reason for the asymmetry no longer involves test stubs. Replace:

```bash
  # This loop has no `if [[ -n "$tsv" ]]` empty-guard like the groups and
  # accounts loops above and below, and kept `continue` rather than `die` for
  # an empty $arn: `<<<""` still hands `read` one empty line, and dying on it
  # would break every stub with an empty `PermissionSets` list used
  # throughout the test suite. Deliberate asymmetry, not an oversight.
```

with:

```bash
  # This loop has no `if [[ -n "$tsv" ]]` empty-guard like the groups and
  # accounts loops above and below, and uses `continue` rather than `die` for
  # an empty $arn: `<<<""` still hands `read` one empty line, and an instance
  # with genuinely zero permission sets must not be fatal. Deliberate
  # asymmetry, not an oversight.
```

- [ ] **Step 5: `load_current_state` — name the function instead of "a later task"**

Replace:

```bash
      # A genuine error (throttling, permissions, ...) must not be read as
      # "not a member": that would have a later task attempt to add a
      # membership that may already exist.
```

with:

```bash
      # A genuine error (throttling, permissions, ...) must not be read as
      # "not a member": that would have do_add_groups attempt to add a
      # membership that may already exist.
```

And replace, in the unrecognised-`PrincipalType` branch:

```bash
        # The fail-safe
        # direction matters — dropping it means a later task attempts the
        # grant anyway, rather than wrongly reporting it already held via a
        # raw, unrecognised principal id and skipping a grant the operator
        # asked for.
```

with:

```bash
        # The fail-safe
        # direction matters — dropping it means do_add_assignments attempts
        # the grant anyway, rather than wrongly reporting it already held via
        # a raw, unrecognised principal id and skipping a grant the operator
        # asked for.
```

- [ ] **Step 6: `print_plan` — rewrite the header comment**

Replace:

```bash
# Renders the plan to stdout: what will be created versus reused, and which
# target groups/grants are genuine changes versus already in place. This is
# the operator's only chance to catch a mistake before Task 8 issues any AWS
# write, so every branch below must say plainly what WILL happen — under-
# reporting a change (e.g. showing "already granted" for something that will
# actually be created) is worse than no plan at all.
#
# Read-only: never mutates PROFILE/EMAIL/USER_EXISTS/TARGET_GROUP_IDS/GRANTS/
# EXISTING_MEMBERSHIP/DIRECT_ASSIGNMENT/INHERITED_ASSIGNMENT. confirm() and
# (on a dry run) the caller both run after this and need every one of them
# exactly as load_current_state left it.
```

with:

```bash
# Renders the plan: what will be created versus reused, and which target
# groups/grants are genuine changes versus already in place. This is the
# operator's only chance to catch a mistake before any AWS write happens, so
# every branch below must say plainly what WILL happen — under-reporting a
# change (e.g. showing "already granted" for something that will actually be
# created) is worse than no plan at all.
#
# Read-only: never mutates IDENTITY_CENTER_PROFILE/EMAIL/USER_EXISTS/
# TARGET_GROUP_IDS/GRANTS/EXISTING_MEMBERSHIP/DIRECT_ASSIGNMENT/
# INHERITED_ASSIGNMENT. The confirmation gate and (on a dry run) the caller
# both run after this and need every one of them exactly as
# load_current_state left it.
```

- [ ] **Step 7: `print_plan` — rewrite the `DRY_RUN` banner comment**

The `set -e` reasoning about the final `printf` no longer applies now the last statement is a
`log_msg` call. Replace:

```bash
  # DRY_RUN only ever affects whether this plan is followed by real AWS
  # writes (Task 8's concern) or the operator simply reads it and exits; the
  # classification of each group/grant below is identical either way, so this
  # is the only place -n has any visible effect within this function.
  #
  # Blank-line-separated rather than folded in among profile:/username:
  # below: every action line further down still reads ADD regardless of
  # DRY_RUN, so without a banner that is hard to skim past, a dry-run plan
  # is visually indistinguishable from a live one. `if` rather than
  # `((DRY_RUN)) && printf ...`: harmless today (this is not the function's
  # last statement, so a false `((DRY_RUN))` here would not trip `set -e`
  # either way — see the trailing printf below, which IS the last statement
  # and must stay unconditional for exactly that reason) but `if` doesn't
  # rely on that positional accident.
```

with:

```bash
  # DRY_RUN only ever affects whether this plan is followed by real AWS
  # writes or the operator simply reads it and exits; the classification of
  # each group/grant below is identical either way, so this is the only place
  # -n has any visible effect within this function.
  #
  # Blank-line-separated rather than folded in among profile:/username:
  # below: every action line further down still reads ADD regardless of
  # DRY_RUN, so without a banner that is hard to skim past, a dry-run plan
  # is visually indistinguishable from a live one. `if` rather than
  # `((DRY_RUN)) && log_msg ...`, so a false condition can never become the
  # function's exit status under `set -e`.
```

- [ ] **Step 8: Check the two write-path comments need no change**

This step is a verification, not an edit. Two comments look like candidates but are already
accurate and must be left exactly as they are.

In `do_create_user`:

```bash
# The only fatal write: nothing downstream (group membership, grants) has a
# principal to attach to without a UserId, so there is no useful way to
# "continue past" a failure here the way do_add_groups/do_add_assignments do.
```

In `do_add_groups`:

```bash
      # Belt and braces: load_current_state's pre-check is the primary
      # idempotency mechanism, but state can still change underneath us
      # between then and now.
```

Both name real functions and describe current behaviour. Confirm they are present and
unmodified, then move on.

- [ ] **Step 9: `aws_admin` — already handled**

Task 2 replaced this comment. Verify it no longer mentions tests:

```bash
grep -n -A3 '^aws_admin' bin/aws/v2/add-user
```

Expected: the comment reads "so the profile is named in exactly one place", with no mention
of tests.

- [ ] **Step 10: Confirm no stale references remain**

```bash
grep -n -i 'harness\|test suite\|Task [0-9]\|a later task' bin/aws/v2/add-user
```

Expected: no output.

- [ ] **Step 11: Syntax and lint**

```bash
bash -n bin/aws/v2/add-user && ./test.sh && echo "OK"
```

Expected: `OK`.

- [ ] **Step 12: Confirm behaviour is unchanged**

```bash
./bin/dalmatian aws add-user -n -y -e "$(git config --get user.email)"
```

Expected: byte-identical output to the same command at the end of Task 4. This task changed
comments only.

- [ ] **Step 13: Commit (ask first)**

```bash
git add bin/aws/v2/add-user
git commit -m "Update aws add-user comments for its new home"
```

---

### Task 6: Full verification and documentation commit

**Files:**
- Modify: none
- Commit: `docs/superpowers/specs/2026-08-20-aws-add-user-design.md`,
  `docs/superpowers/plans/2026-08-20-aws-add-user.md`

**Interfaces:**
- Consumes: the finished `bin/aws/v2/add-user`.
- Produces: a branch ready for review.

- [ ] **Step 1: Full lint**

```bash
./test.sh && echo "SHELLCHECK OK"
```

Expected: `SHELLCHECK OK`. Then confirm no suppressions were added:

```bash
grep -n 'shellcheck disable' bin/aws/v2/add-user
```

Expected: no output.

- [ ] **Step 2: Dry run against an existing user**

```bash
./bin/dalmatian aws add-user -n -y -e "$(git config --get user.email)"
```

Expected: `user:           REUSE existing user (<id>)` in the plan, `Groups: (none)`,
`Account grants: (none)`, exit 0, nothing written.

- [ ] **Step 3: Dry run exercising groups and a grant**

Pick a real group and a real permission set and account from the interactive lists, then:

```bash
./bin/dalmatian aws add-user -n -e "$(git config --get user.email)" -g <a-real-group> -a <a-real-permset>:<a-real-account>
```

Expected: the Groups section classifies the group as either `skip already a member` or
`ADD`, and the grant is classified as `skip already granted directly`, `ADD ... [redundant —
inherited from group '...']`, or plain `ADD`. Exit 0. This is the only check that exercises
`load_current_state`'s direct-versus-inherited logic.

- [ ] **Step 4: Dry run for a brand-new user, exercising name derivation**

```bash
./bin/dalmatian aws add-user -n -e jane.doe@example.com
```

Expected: a `Name looks like "Jane Doe" — enter to accept, anything else to correct:` prompt.
Press enter, decline groups and grants, and confirm the plan says
`user:           CREATE new user` and `display name:   Jane Doe`. Exit 0, nothing written.

- [ ] **Step 5: Error paths**

```bash
./bin/dalmatian aws add-user -n -y -e not-an-email
```

Expected: `[!] Error: not a valid email address: not-an-email`, exit 1.

```bash
./bin/dalmatian aws add-user -n -y -e "$(git config --get user.email)" -g no-such-group-exists
```

Expected: `[!] Error: unknown group 'no-such-group-exists'. Available: ...`, exit 1.

```bash
./bin/dalmatian aws add-user -n -y -e "$(git config --get user.email)" -a bad-format
```

Expected: `[!] Error: invalid -a value 'bad-format', expected 'PermissionSet:account'`,
exit 1.

- [ ] **Step 6: Review the whole diff**

```bash
git diff main...HEAD --stat
git diff main...HEAD
```

Expected: `bin/aws/v2/add-user` added, nothing else. Read the full diff before committing
the docs.

- [ ] **Step 7: Commit the spec and plan (ask first)**

```bash
git add docs/superpowers/specs/2026-08-20-aws-add-user-design.md docs/superpowers/plans/2026-08-20-aws-add-user.md
git commit -m "Document the aws add-user design and plan"
```

Stage only those two paths. `TODO.md`, `stderr.log`, `stdout.log` and the other untracked
files under `docs/` are pre-existing local state and must stay untracked.

- [ ] **Step 8: Live run**

The final check is adding a real new joiner. Every step is idempotent, so a partial failure
is safe to re-run with the same arguments. Do this with the user present, not
autonomously.

---

## Task 7: Post-review fixes (added during execution)

A `pr-reviewer` subagent reviewed the staged result before commit and returned BLOCK with two
Critical findings, both independently verified before being acted on. This task records what
changed. It is written after the fact rather than as forward-looking steps, because the review
happened during execution.

**Files:** `bin/aws/v2/add-user`, plus spec corrections.

- [x] **Critical 1 — refuse to prompt when the plan is hidden.** `print_plan` uses `esc_msg`,
  suppressed when the dispatcher forces quiet mode (stdout not a TTY). `yes_no` shows its
  prompt whenever *stdin* is a terminal. Independent conditions, so `add-user -e x@example.com >
  log` showed `Proceed? (y/N)` with the plan nowhere — verified live, the redirected file held
  two blank lines. Added a guard first in `preflight`:
  `if ((QUIET_MODE && !ASSUME_YES && !DRY_RUN)); then die ...; fi`. Verified all four cases:
  refuses when hidden, allows `-n`, allows `-y`, and a normal terminal run shows the plan then
  the gate.

- [x] **Critical 2 — `echo -e` could truncate a plan line.** `log_msg`/`log_info` render with
  `echo -e`. An account name containing `\c` made the rest of the line vanish, including the
  account ID the operator is meant to verify; `\t`/`\n` mangled it. Backslash is legal in an
  AWS Organizations account name. Added `esc_msg`/`esc_info` wrappers that double backslashes,
  and converted all 44 call sites. Verified both hostile names now render literally.

- [x] **Important 3 — `-n` is not "change nothing".** It writes the local SSO profile, since
  `resolve_identity_center_profile` runs in `preflight`. Banner now reads `DRY RUN — no AWS
  changes will be made`, and the `-n` help text says so explicitly.

- [x] **Important 4 — `profile_exists` masked config read failures.** Now captures
  `aws configure list-profiles` and dies on non-zero rather than reporting "profile absent".

- [x] **Important 5 — `--name` shorthand injection.** Now built with `jq -nc --arg`.

- [x] **Important 6 — `-y` help text** expanded to state it also fixes groups/grants to
  `-g`/`-a` and does not skip the name prompts.

- [x] **Re-verified after the changes:** `./test.sh` clean with no suppressions; REUSE path;
  all three plan classification branches (`skip already a member`, `ADD ... [redundant —
  inherited from group]`, plain `ADD`); four error paths; the guard's four cases; help text.

### Deferred (reviewer's Minor findings, not actioned)

- On a `REUSE` run the plan prints `display name:` but `do_create_user` returns early and never
  calls `update-user`, so the stated name is not applied. Should be suppressed or marked
  `(unchanged)` when `USER_EXISTS`. This is a plan-accuracy issue, the same class as Critical 2,
  and is the strongest candidate for a follow-up.
- `ASSIGNMENT_REQUESTS` joins on `|`, the very separator the file rejects for `GRANTS` because
  an account name may contain it. Harmless today, wrong in principle — use `GRANT_TUPLE_SEP`.
- `printf 'Not a valid email address.\n' >&2` is the last user-facing diagnostic left raw; its
  sibling was converted to `warning`.
- With `fzf --multi`, plain Enter selects the row under the cursor, so "no groups" is not
  reachable the same way as in the numbered fallback (which honours a blank line). Inherited
  from the original.
- Assignment polling is strictly sequential, 60 × 2s per grant, so N grants worst-case N × 2
  minutes.
- `aws --profile dalmatian-main` is the one hardcoded profile name left; matches
  `generate-config` but `"${AWS_PROFILE:-dalmatian-main}"` would express the coupling.
- The same hidden-plan-but-still-prompting shape exists in
  `bin/terraform-dependencies/v2/set-tfvars`, and there the default is yes.

---

## Deferred

Recorded so they are not silently lost, and deliberately not in any task above:

- A `dalmatian aws add-user` entry in shell completion argument lists. Completion currently
  only completes command names, not flags, for any command.
- `DALMATIAN_TOOLS_DEBUG`-triggered `set -x`, which `bin/aws/v2/put-secret` and
  `bin/aws/v2/exec` have. Not in the spec; add it only if asked.
- Adding `fzf` to the `Brewfile`. An explicit non-goal, though several commands including
  this one already use it.
