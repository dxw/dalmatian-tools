# Design Spec: `dalmatian aws add-user`

Date: 2026-08-20

## Overview

Port the standalone `add-aws-sso-user.sh` script into dalmatian-tools as a v2 command,
`dalmatian aws add-user`. The command adds a person to the organisation's AWS IAM Identity
Center: it creates the user in the identity store, adds them to groups, and grants permission
sets on specific accounts. It is idempotent — re-running tops up whatever is missing rather
than failing.

The port is deliberately faithful. The standalone script's behaviour, control flow and
defensive checks are carried over as they stand; only the things that are specific to its
old home change. Those are the AWS profile it authenticates with, its output functions, its
confirmation prompt, and its fzf detection.

## Background

The standalone script defaults to the `org.admin` profile in the operator's own
`~/.aws/config`, which points at the organisation's management account
(`111122223333`). That is where the Identity Center instance lives, so it is where
`sso-admin` and `identitystore` calls must be made.

Under v2, `bin/dalmatian` overrides `AWS_CONFIG_FILE` to
`~/.config/dalmatian/dalmatian-sso.config` and sets `AWS_PROFILE=dalmatian-main`
(`444455556666`). The operator's own `~/.aws/config` is therefore invisible to the command,
and the management account is not in the Dalmatian config either: `bin/aws/v2/generate-config`
only writes profiles for accounts that exist as Terraform workspaces, and the management
account is not Dalmatian-managed. So there is no existing profile the command can use, and
the first job of the port is to obtain one.

## Goals

- `dalmatian aws add-user` behaves as `add-aws-sso-user.sh` does today.
- It works for any operator with a completed `dalmatian setup`, with no re-setup and no
  manual profile editing.
- Output respects `QUIET_MODE` and uses the repo's logging functions.
- `./test.sh` (shellcheck) passes with no new suppressions.

## Non-goals

- A v1 equivalent. v1 has no SSO administration story.
- Porting the standalone script's 3132-line offline unit test suite. shellcheck remains
  the only automated check, matching the rest of the repo.
- Adding `fzf` to the `Brewfile`. Several existing commands already use fzf without it
  being declared, and this command retains a numbered-menu fallback.
- Deleting or modifying users, or removing group memberships and grants.
- Sending the Identity Center invitation email. There is still no API for it, so the
  summary continues to point the operator at the console.

## Design

### File layout

One new executable file: `bin/aws/v2/add-user`. Nothing else is touched.

- Both `support/bash-completion.sh` and `support/zsh-completion.sh` discover commands by
  listing `bin/<subcommand>/<version>/`, so the command completes with no registration.
- `README.md` does not enumerate commands, so it needs no change.
- `Brewfile` already declares `awscli`, `bash` and `jq`.

### Command structure

The standalone script's function decomposition is kept as-is, driven by `main`:

```
parse_args → preflight → prompt_identity → load_directory → collect_inputs
           → lookup_user → load_current_state → print_plan → gate
           → do_create_user → do_add_groups → do_add_assignments
           → wait_for_assignments → print_summary
```

Two top-level constructs are dropped:

- The `if [[ "${BASH_SOURCE[0]}" == "$0" ]]` guard around `main`. It existed so the test
  harness could source the script without executing it. With the tests not being ported,
  nothing sources the file, so `main "$@"` is called unconditionally.
- The bash 4+ assertion at the top of the file. `bin/dalmatian` calls
  `check_bash_version` before dispatching to any command, so by the time this script runs
  the check has already happened. Duplicating it would be dead code.

### Flag surface

```
dalmatian aws add-user [-e email] [-f first] [-l last] [-g group]...
                       [-a permset:account]... [-p profile] [-n] [-y] [-h]
```

Unchanged from the standalone script except for `-p`, whose default is now derived rather
than hardcoded. Any omitted input is prompted for.

Running with no arguments is valid and starts the fully interactive flow. This deliberately
breaks the `if [ $# -eq 0 ]; then usage; fi` convention that other v2 commands follow,
because interactive use is this command's primary mode, not an error.

`-q` needs no handling: `bin/dalmatian` strips a bare `-q` from the argument list before
dispatch and exports `QUIET_MODE`.

### Identity Center profile resolution

A new function, `resolve_identity_center_profile`, runs at the start of `preflight` and
sets `IDENTITY_CENTER_PROFILE`. `aws_admin()` becomes
`aws --profile "$IDENTITY_CENTER_PROFILE" "$@"` and is otherwise unchanged, so it remains
the single choke point for every AWS call.

Resolution order:

1. **`-p <profile>` given.** Use it. Verify it appears in `aws configure list-profiles`
   (which honours the overridden `AWS_CONFIG_FILE`) and die with a pointer to
   `dalmatian aws generate-config` if it does not.
2. **`dalmatian-identity-center` already exists** in `aws configure list-profiles`. Use it.
3. **Otherwise, discover the account and write the profile.**
   - Get the management account ID:
     `aws --profile dalmatian-main organizations describe-organization --query 'Organization.MasterAccountId' --output text`.
     A member account is permitted to call this. Guard the result for empty and the literal
     string `None`, as every other `--output text` call in the script does.
   - Read `aws_sso.start_url`, `aws_sso.region` and `aws_sso.default_admin_role_name` from
     `$CONFIG_SETUP_JSON_FILE`, each guarded for empty and the literal string `null`.
   - Append the profile:
     ```
     append_sso_config_file "$CONFIG_AWS_SSO_FILE" "dalmatian-identity-center" \
       "$start_url" "$sso_region" "$management_account_id" "$admin_role_name" "$sso_region"
     ```

The profile's `region` is the Identity Center region (`aws_sso.region`), not
`default_region`. `sso-admin` and `identitystore` calls must be made in the region the
Identity Center instance lives in; the two are often the same value, but they are not the
same thing.

`append_sso_config_file` is a blind append with no existence check of its own, so step 2 is
what makes this idempotent. `generate-config` rewrites `dalmatian-sso.config` wholesale, so
regenerating the config silently drops this profile and the next `add-user` run re-adds it.
That is acceptable — the whole point of deriving the profile is that losing it costs
nothing — and it is recorded in a comment at the call site so nobody later mistakes the
disappearing profile for a bug.

No additional `aws sso login` is needed. `bin/dalmatian` has already logged in before the
command runs, and the SSO token cache is keyed on `sso_start_url`, which is identical
across every profile the Dalmatian config generates. This new profile is no different from
the ones `generate-config` writes.

The existing `sts get-caller-identity` check in `preflight` stays, keeping the underlying
error rather than discarding it. Its advice is extended: as well as an expired session, the
likely cause is now that the operator has no `admin` assignment on the management account,
which `aws sso login` cannot fix.

### Other derived values

Two more values stop being hardcoded:

- `CONSOLE_USERS_URL`, printed by `print_summary`, is built from `aws_sso.region` instead of
  embedding `eu-west-2` twice in a literal URL.
- `print_plan`'s `profile:` line reports `IDENTITY_CENTER_PROFILE`, not the removed
  `PROFILE` variable, so the operator can see which profile was resolved before they
  approve the plan. This matters most in the discovery case, where they never named it.

### Output

Per `AGENTS.md`, user-facing output goes through the repo's logging functions, via two thin
local wrappers:

| Standalone script | Ported command |
| --- | --- |
| `printf '==> ...'` | `esc_info "$(printf ...)"` |
| plain and indented `printf` | `esc_msg "$(printf ...)"` |
| `printf 'Warning: ...' >&2` | `warning "$(printf ...)"` |
| `die()` | kept, redefined as `err "$1"; exit 1` |

where

```bash
esc_msg()  { log_msg  -l "${1//\\/\\\\}" -q "$QUIET_MODE"; }
esc_info() { log_info -l "${1//\\/\\\\}" -q "$QUIET_MODE"; }
```

`err` prints but does not exit, so `die` has to remain a local function rather than being
replaced by a bare `err` call.

Every dynamic value is built by passing it to `printf` as an argument, never interpolated
into a format string, so a group, account or permission-set name containing `%s`, quotes,
`*` or a leading `-` cannot be reinterpreted as a printf directive.

**The wrappers exist because `log_msg` and `log_info` render with `echo -e`, which
interprets backslash escapes.** An earlier draft of this spec dismissed that as "cosmetic,
affects display only". That was wrong, and code review caught it. AWS Organizations permits
any printable ASCII in an account name, backslash included. Verified empirically:

```
account name 'evil\c hidden'  ->  "ADD grant 'admin' on evil"
```

`\c` makes `echo -e` discard the rest of the line, so the account ID the operator is
supposed to be checking silently vanishes. `\t` and `\n` mangle the line similarly. Since
the plan is the operator's consent surface, under-reporting a change there is precisely the
failure the plan exists to prevent. Doubling backslashes in the wrapper makes `echo -e` emit
them literally.

Routing every message through the wrappers has a second benefit: `log_msg` and `log_info`
both assign to the global `QUIET_MODE` as a side effect, so omitting `-q "$QUIET_MODE"`
silently disables quiet mode for the rest of the run. The wrappers make that impossible to
forget.

### Refusing to prompt when the plan is hidden

The Plan and Summary blocks go through `esc_msg`, so they are suppressed when the dispatcher
forces quiet mode — which it does whenever stdout is not a TTY. `yes_no`, however, shows its
prompt whenever *stdin* is a terminal. Those two conditions are independent, and code review
found the gap: an operator running

```
dalmatian aws add-user -e someone@example.com -g admin > onboarding.log
```

sees `Proceed? (y/N)` on their terminal while the plan appears neither on screen nor in the
log file. They would be authorising AWS access grants they cannot see. Verified live: the
redirected file contained two blank lines and no plan.

The command therefore refuses outright:

```bash
if ((QUIET_MODE && !ASSUME_YES && !DRY_RUN))
then
  die "refusing to ask for confirmation when the plan cannot be shown. ..."
fi
```

placed first in `preflight` so it fails before any AWS call. `-y` is exempt: the operator has
explicitly declined the confirmation, so there is no consent to misinform. `-n` is exempt: it
makes no AWS changes.

The alternative considered was to print the plan to stderr unconditionally, like the prompts.
That would also have fixed the backslash problem in one stroke, but it moves the plan out of
stdout, so `-n > plan.txt` would no longer capture it. Refusing is the smaller change and
keeps the toolkit's logging convention intact.

Note the same shape exists in `bin/terraform-dependencies/v2/set-tfvars` (plan suppressed,
`yes_no` still asked, and there defaulting to yes). That is out of scope here, but worth
fixing separately.

### Prompts

Prompts keep writing to stderr with raw `printf`, exactly as the standalone script does.
They are deliberately not routed through `log_msg`: `bin/dalmatian` force-enables quiet
mode whenever stdout is not a TTY, so a suppressed prompt would leave a piped run hanging
at an invisible question. This applies to `read_line_or_die` and to the grant loop's
prompts.

`read_line_or_die` is otherwise unchanged, including its EOF-is-fatal behaviour and its
whitespace trimming.

### Confirmation gate

`confirm()` is dropped in favour of the repo's `yes_no "Proceed? (y/N)" "n"`. Two
behavioural differences, both acceptable:

- Unrecognised input re-prompts rather than aborting. The standalone script aborted on
  anything that was not `y`/`Y`.
- EOF leaves `CHOICE` empty, which falls through to the `n` default and returns false, so
  a closed stdin still aborts without writing anything.

The `Add a permission set grant?` loop in `collect_inputs` likewise uses
`yes_no "Add a permission set grant? (y/N)" "n"` and breaks when it returns false.

`-y` continues to skip the gate entirely, and continues to mean non-interactive: with no
`-g` or `-a` given, `-y` means no groups and no grants rather than "prompt anyway".

### Interactive selection

`HAVE_FZF` detection adopts the convention already used by `bin/ec2/v2/shell` and
`bin/terraform-dependencies/v2/set-tfvars`:

```bash
if [[ "${DALMATIAN_FZF_ENABLED:-1}" == "1" ]] && command -v fzf > /dev/null
```

`select_one`, `select_many`, `_numbered_select` and `fzf_status_or_die` are otherwise
unchanged. The numbered fallback matters: fzf is not in the `Brewfile`, so a machine
without it must still be able to run the command, and `DALMATIAN_FZF_ENABLED=0` must
force that path.

### Behaviour carried over unchanged

Everything below is ported as it stands, comments included:

- `validate_email`, `derive_names` and the `prompt_identity` flow, including the
  single-keystroke "name looks like X" confirmation and the per-field fallback prompts.
- `load_directory`'s three-way validation of every AWS response (jq exit status, explicit
  array-type check, empty-body check), its tab-splitting via parameter expansion rather
  than `IFS=$'\t' read`, its case-collision detection for groups and permission sets, and
  its warn-and-skip handling of a malformed account row.
- `resolve_group`, `resolve_permission_set` and `resolve_account`, including the
  `AMBIGUOUS` sentinel for duplicate account names and the 12-digit account ID escape
  hatch.
- `lookup_user`'s classification of `ResourceNotFoundException` as the ordinary new-user
  outcome, matched against the CLI's stable error prefix rather than a bare substring.
- `load_current_state`'s distinction between direct and group-inherited assignments,
  requiring both `PrincipalType == USER` and `PrincipalId == USER_ID` for a direct match.
- `assignment_key`, `GRANT_TUPLE_SEP` and the deliberate field-order asymmetry between
  them.
- `print_plan`'s classification of each group and grant, including flagging a requested
  grant that is currently redundant because it is inherited from a group, and still
  creating it.
- `do_create_user` being the only fatal write, and `do_add_groups` /
  `do_add_assignments` counting per-item failures into `FAILURES` instead of aborting.
- `ConflictException` treated as already-done in both write paths.
- `wait_for_assignments`' polling, its `SUCCEEDED`/`FAILED`/timeout handling, and its
  counting of a timeout as a failure.
- Dry run prints the plan and exits 0. A non-zero `FAILURES` exits 1.

### Comment adjustments

Comments in the standalone script that refer to the test harness, to "the harness sources
this file", or to numbered porting tasks ("Task 8", "a later task") are rewritten to
describe what the code does. Leaving them would be actively misleading in the new home,
since no harness exists and the task numbering refers to nothing. This is the only place
the port is not literal.

### Robustness fixes from code review

Three further changes, none of which alter the design but all of which close real failure
modes found in review:

- **`profile_exists` captures its input.** It originally read from `< <(aws configure
  list-profiles)`, where a failure is invisible — an unreadable or unparseable config would be
  indistinguishable from "no such profile". That fails in both directions: the discovery path
  would append a *second* `dalmatian-identity-center` block, and the `-p` path would insist a
  profile is absent that the operator can see in the file. It now captures the output and dies
  on a non-zero exit. Verified: `aws configure list-profiles` exits 255 on a malformed config.

- **`--name` is built with `jq`, not CLI shorthand.** `--name "GivenName=$FIRST_NAME,..."`
  relied on names containing no `,` or `=`, but `FIRST_NAME`/`LAST_NAME` are free text from
  `-f`/`-l` or a prompt and are only whitespace-trimmed. `-f 'Jane, Q'` broke shorthand
  parsing into an opaque "failed to create user"; `-f 'X,FamilyName=Y'` silently supplied a
  duplicate key. Now `jq -nc --arg given ... --arg family ...`. `--emails` stays as shorthand
  because `validate_email` already excludes both characters.

- **`-y`'s blast radius is documented in the help text.** It suppresses group and grant
  collection as well as the confirmation, so `-y` with no `-g`/`-a` means "no groups, no
  grants" — but it does *not* suppress the name prompts, so scripted use needs `-f`/`-l` too.
  The help text now says all of this.

## Error handling

`set -e` and `set -o pipefail` as per every other v2 command. Failure classes:

| Failure | Behaviour |
| --- | --- |
| Quiet mode would hide the plan while still prompting | die in `preflight`, before any AWS call |
| Missing `aws` or `jq` | die in `preflight` |
| Cannot read the AWS config at all | die naming the config file, rather than reporting "profile absent" |
| `-p` profile does not exist | die, pointing at `generate-config` |
| Management account not discoverable | die with the underlying AWS error |
| Cannot authenticate as Identity Center admin | die, covering both expired session and missing `admin` assignment |
| Not exactly one Identity Center instance | die with the count |
| Unparseable or wrong-shaped AWS response | die naming the API call |
| Unknown group, permission set or account | die listing the valid options |
| User creation fails | die |
| A single group or grant fails | warn, increment `FAILURES`, continue |
| Assignment provisioning fails or times out | warn, increment `FAILURES`, continue |
| `FAILURES > 0` at the end | exit 1 after printing the retry advice |

## Verification

1. `./test.sh` passes, with no new shellcheck suppressions.
2. `dalmatian aws add-user -n -e <an existing user's address>` — confirms profile
   discovery, that the `dalmatian-identity-center` profile is written and then reused on a
   second run, that groups, permission sets and accounts all list, and that the plan
   renders and classifies existing state correctly. Makes no AWS changes — but note it
   does write the local `dalmatian-identity-center` profile if absent, since
   `resolve_identity_center_profile` runs in `preflight`, before the dry-run check. The
   banner and the `-n` help text both say "no AWS changes" rather than "change nothing"
   for exactly this reason.
3. `dalmatian aws add-user -n -e <an unused address>` — confirms the CREATE-new-user path
   of the plan and the name derivation prompts.
4. `DALMATIAN_FZF_ENABLED=0 dalmatian aws add-user -n` — confirms the numbered-menu
   fallback.
5. A live run for a real new joiner is the final check. Every step is idempotent, so a
   partial failure is safe to re-run.
