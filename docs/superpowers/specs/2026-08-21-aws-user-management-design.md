# Design Spec: `dalmatian aws list-users` and `dalmatian aws remove-user`

Date: 2026-08-21

Follows on from `2026-08-20-aws-add-user-design.md`, which added `dalmatian aws add-user`.
Read that first: this spec reuses its Identity Center profile mechanism, its plan-and-confirm
pattern, and its output conventions, and extracts the shared parts of it into
`lib/bash-functions/`.

## Overview

Add two commands for managing AWS IAM Identity Center users:

- `dalmatian aws list-users` — show every user in the identity store, with status and group
  membership.
- `dalmatian aws remove-user` — tear down a user's access and delete them, with a plan, a
  confirmation gate, and a printed line to restore them.

A third command, `disable-user`, was requested and then dropped. See below.

Along the way, the machinery `add-user` built for talking to Identity Center is extracted into
`lib/bash-functions/` so all three commands share one implementation.

## Why there is no `disable-user`

Disabling an Identity Center user cannot be done through the AWS API. Established three ways
before any code was written:

1. The `identitystore` service model defines `UserStatus` with enum `["ENABLED", "DISABLED"]`,
   and the field is present in the `User` output shape — so the status is **readable**.
2. `UpdateUser` refuses to write it. Probed against a deliberately non-existent user ID, so
   nothing could be mutated either way:

   | `AttributePath` | Result |
   | --- | --- |
   | `displayName` | `ResourceNotFoundException: User not found` — path accepted |
   | `userStatus` | `ValidationException: Updates for AttributePath: userStatus is not supported` |
   | `active` | `ValidationException: Updates for AttributePath: active is not supported` |
   | `zzzNotAnAttribute` | `ValidationException: ... is not supported` |

   `displayName` reaching the user lookup while `userStatus` fails validation proves the
   rejection is about the attribute, not the fake user ID.
3. There is no SCIM path to do it upstream instead. All 42 users in the directory at the
   time of writing have `ExternalIds: null`, so none are externally provisioned. The 7
   currently `DISABLED` users were all disabled by hand in the console, which drives an
   internal endpoint the CLI has no access to.

Reverse-engineering that console endpoint was considered and rejected: undocumented,
unsupported, needs browser session credentials, and would break without warning.

So disabling stays a console action. This mirrors the invitation email, which `add-user`
already cannot send for the same class of reason.

The option of implementing `disable-user` as "revoke all access but keep the user record" was
offered and declined — it would be a command whose name promised something it does not do.

## Goals

- Listing users is composable: the output is data, so it survives a pipe.
- Removing a user leaves nothing behind — no group memberships, no orphaned account
  assignments, no user record.
- An accidental removal is recoverable from the command's own output.
- One implementation of Identity Center profile resolution, shared by all three commands.
- `./test.sh` (shellcheck) passes with no new suppressions.

## Non-goals

- `disable-user`, for the reasons above.
- Re-enabling users, or any other status change.
- A v1 equivalent.
- Removing groups, permission sets or accounts. Only users.
- Modifying a user in place (`add-user` already tops up group and grant membership; nothing
  needs to rename a user).
- Fixing the deferred `add-user` minors recorded in
  `docs/superpowers/plans/2026-08-20-aws-add-user.md`, including the `REUSE` display-name bug.

## Design

### Shared library extraction

Eight new files in `lib/bash-functions/`, one function each, matching the existing convention
exactly — all 18 current files hold precisely one function.

**Every extracted function must be declared `function foo {`, not `foo() {`.** `bin/dalmatian`
discovers what to export with `grep "^function" "$bash_function_file" | cut -d" " -f2`, so a
function using the parenthesis form is sourced but never exported, and is therefore invisible
to the command subprocess. This is the single most likely way to get the extraction wrong.

| File | Function | Responsibility |
| --- | --- | --- |
| `die.sh` | `die <message>` | `err` then `exit 1`. `err` alone does not exit. |
| `esc_msg.sh` | `esc_msg <line>` | `log_msg` with backslashes doubled and `-q "$QUIET_MODE"` supplied |
| `esc_info.sh` | `esc_info <line>` | as above for `log_info` |
| `load_aws_sso_setup.sh` | `load_aws_sso_setup` | reads `aws_sso.start_url`, `aws_sso.region`, `aws_sso.default_admin_role_name` from setup.json; sets `CONSOLE_USERS_URL` |
| `aws_profile_exists.sh` | `aws_profile_exists <name>` | exact-match lookup in the active AWS config; dies if the config cannot be read |
| `resolve_identity_center_profile.sh` | `resolve_identity_center_profile` | `-p` override, else reuse, else discover the management account and append the profile |
| `identity_center_instance.sh` | `identity_center_instance` | sets `INSTANCE_ARN` and `IDENTITY_STORE_ID`; enforces exactly one instance |
| `require_visible_plan.sh` | `require_visible_plan <assume_yes> <dry_run>` | refuses to run when quiet mode would hide the plan but the gate would still prompt |

`resolve_identity_center_profile` keeps reading `PROFILE_OVERRIDE` and
`IDENTITY_CENTER_PROFILE_NAME` from the caller's environment, and keeps setting
`IDENTITY_CENTER_PROFILE`. Exported functions run in the calling shell, so globals set inside
them are visible to the caller.

`require_visible_plan` takes its two flags as arguments rather than reading globals, because
`ASSUME_YES` and `DRY_RUN` are command-local names while `QUIET_MODE` is the dispatcher's.

Deliberately **not** extracted, because only `add-user` uses them: `_numbered_select`,
`fzf_status_or_die`, `select_one`, `select_many`, `load_directory`, `resolve_group`,
`resolve_permission_set`, `resolve_account`, `assignment_key`, `validate_email`,
`derive_names`, `read_line_or_die`, `prompt_identity`. Extracting them would be speculative.

`add-user` is refactored to call the extracted functions, losing roughly 120 lines. Its
`aws_admin` wrapper, its own pickers and its directory loading all stay where they are.

### `list-users`

```
dalmatian aws list-users [-j] [-h]
```

Default output is an aligned table, sorted by username, with column widths computed from the
data:

```
USERNAME              STATUS   DISPLAY NAME  EMAIL                   GROUPS
asmith                ENABLED  Alex Smith    alex.smith@example.com  Admin,contractors
jane.doe@example.com  ENABLED  Jane Doe      jane.doe@example.com    Admin
```

`-j` emits JSON instead: each user object from `list-users`, with a `Groups` array added,
assembled with `jq`.

**The table is written with `printf` directly to stdout, never through `esc_msg`.** The output
is the command's payload, not commentary about it. `bin/dalmatian` forces `QUIET_MODE=1`
whenever stdout is not a TTY, so routing this through `log_msg` would make
`dalmatian aws list-users | grep DISABLED` return nothing at all. This matches how
`bin/aws/v2/list-profiles` and `bin/deploy/v2/list-accounts` handle their output — both use a
bare `echo` for exactly this reason. Status messages that are *not* the payload (for example
the profile-creation notice from `resolve_identity_center_profile`) continue to use
`esc_info`, and so are correctly suppressed when piped.

Group membership is resolved by iterating groups, not users: `list-groups` then
`list-group-memberships` per group, inverted into a `UserId → group names` map. That is one
extra call per group rather than the one per user that
`list-group-memberships-for-member` would cost, and a directory has far fewer groups than
users. The map is built with an associative array keyed on `UserId`.

Users with no groups show an empty `GROUPS` column. Users with no email show an empty `EMAIL`
column rather than the literal `null`, using jq's `// ""`.

`list-users` is read-only as far as AWS is concerned, but it is not side-effect free: it calls
`resolve_identity_center_profile`, which appends the `dalmatian-identity-center` profile to the
local `dalmatian-sso.config` if it is missing. That is the same behaviour `add-user -n` has, and
the same reasoning applies — the profile is derived, so writing it costs nothing and losing it
costs nothing. Worth stating because "a list command that writes a file" is otherwise a
surprise. The notice it prints goes through `esc_info`, so it is suppressed when piped and
cannot corrupt the table.

### `remove-user`

```
dalmatian aws remove-user -e <email> [-n] [-y] [-h]
```

Sequence:

1. `preflight` — `require_visible_plan`, tool checks, profile resolution, instance discovery.
2. Resolve the email to a `UserId`. Unlike `add-user`, a missing user is **fatal**: there is
   nothing to remove, and silently succeeding would wrongly suggest the account was cleaned up.
3. Gather what the user holds:
   - group memberships, via `list-group-memberships-for-member`
   - direct account assignments, via `list-account-assignments-for-principal` with
     `--principal-type USER`, keeping only rows where `PrincipalType == "USER"` **and**
     `PrincipalId == USER_ID`. Inherited (`GROUP`) rows are ignored: they are not this user's
     to remove, and deleting them would revoke access for everyone else in the group.
4. Resolve display names **on demand** — `describe-group` per group held, and
   `describe-permission-set` / `organizations describe-account` per assignment held. A leaver
   holds a handful of each, so this is cheaper than building the full directory, and it means
   `load_directory` does not need to be shared.
5. Print the plan: the user being deleted, each membership to be removed, each assignment to
   be revoked.
6. Confirmation gate: `yes_no "Proceed? (y/N)" "n"`, skipped by `-y`. `-n` prints the plan and
   exits 0.
7. Execute, in this order:
   1. `sso-admin delete-account-assignment` for each direct assignment, then poll
      `describe-account-assignment-deletion-status` to `SUCCEEDED`.
   2. `identitystore delete-group-membership` for each membership.
   3. `identitystore delete-user`.
8. Print the restore line and the summary.

**Order matters and is deliberate.** Assignments are revoked before the user record is
deleted, so an interrupted run can never leave a deleted principal holding live grants.

**`delete-user` is skipped entirely if any earlier step failed.** Every other failure in this
command is counted and non-fatal, matching `add-user`. This one is not: deleting the identity
while grants remain produces exactly the orphaned-assignment state the command exists to
avoid, and it destroys the `UserId` needed to find those grants again. On any failure the
command reports what it could not remove and exits 1, leaving the user in place for a re-run.

The restore line is printed on success:

```
dalmatian aws add-user -e jane.doe@example.com -f Jane -l Doe -g Admin -a admin:123456789012
```

Given names come from the user's `Name.GivenName` / `Name.FamilyName`, captured before
deletion. Accounts are rendered as 12-digit IDs rather than names, since IDs are unambiguous
whereas account names are not unique in an organisation. The line is printed via `esc_msg`
like the rest of the summary, so it is suppressed when piped — it is advice to an operator at
a terminal, not machine output.

### Idempotency

Both commands are safe to re-run. `list-users` is read-only. For `remove-user`,
`ResourceNotFoundException` on any individual delete is treated as already-done, the same way
`add-user` treats `ConflictException` on create. So a run that fails partway through can be
repeated with the same arguments, and will pick up whatever is left.

## Fixes from code review

A reviewer went over the implementation before commit and found seven defects, all verified
independently before being acted on. Recorded here because several contradict what earlier
drafts of this spec asserted.

- **The restore line was silently corruptible.** It single-quoted values by hand. A name
  containing one apostrophe made the line a syntax error; two re-balanced the quoting and
  produced a *valid but wrong* command. With `FAMILY_NAME="O'Brien"` and a group `Dev's Team`,
  the printed line parsed to argv `[-l] [OBrien -g Devs Team]` — corrupted surname, and the
  `-g` flag swallowed entirely. Since this is the only recovery path for an irreversible
  operation, a silently-wrong line is worse than none. Now built with `printf '%q'`, which
  round-trips through `esc_msg`'s backslash doubling intact.

- **`-e` no longer requires an email address.** The original spec said `-e <email>` and the
  implementation enforced it with a regex. Identity Center does not require `UserName` to be an
  email, and 28 of the 42 users in the directory at the time of writing were not (`asmith`,
  `rjones`, `ops-service`, …). The regex made every one of them unremovable before a single API
  call was made. `add-user` may impose the email convention on users it creates;
  `remove-user` operates on what already
  exists. The regex was also implicitly protecting two hand-built JSON strings, so those are now
  built with `jq -nc --arg` instead.

- **Two malformed-row guards failed open.** `load_memberships` and `load_assignments` used
  `|| continue` for a row with a missing id. A dropped row never reaches the plan, is never
  revoked, and — critically — never increments `FAILURES`, so `do_delete_user` would proceed and
  delete the identity while a grant was still live, destroying the `UserId` needed to find it
  again. Exactly the state the ordering exists to prevent. Both now `die`.

- **The restore record was destroyed by partial failure.** It was printed only on the success
  path. If a revocation failed, `delete-user` was correctly skipped, but the memberships had
  already been removed — so a re-run rebuilt the line with no `-g` flags and handed the operator
  something that looked complete while omitting every group. The line is now printed as part of
  the plan, before anything is mutated, so it survives a failed revocation, a partial teardown,
  and an interrupt.

- **The email column's fallback was dead code.** `|` binds looser than `//` in jq, so
  `(.Emails // []) | map(...) | first | .Value // (fallback)` evaluated the fallback with `.`
  bound to the primary-email object rather than the user. A user whose email carried no
  `Primary` flag showed a blank column despite having one. No current user is affected — the
  console and `add-user` both set the flag — so this was latent. Fixed with an explicit
  `as $e` binding.

- **`-j` did not deliver the unambiguous array it promised.** A comment claimed the JSON output
  kept comma-containing group names intact, but the map stored them comma-joined and the JSON
  reconstructed with `split(",")`, so `Foo, Bar` became `["Foo", " Bar"]` there too. The internal
  separator is now `FIELD_SEP`; the comma appears only where a human reads it, in the table.

- **An incorrect comment, repeated three times.** `export PROFILE_OVERRIDE` was justified by
  analogy to `export_aws_caller_identity_username.sh`. That analogy is wrong: that function
  exports because *subprocesses* read the value, whereas exported functions run in the calling
  shell and see plain globals. The export is retained only to stop shellcheck reporting SC2034
  for a cross-file read it cannot see, and the comment now says so.

Two further findings were accepted as known limitations rather than fixed, and are recorded in
the plan's Deferred section: `-y` combined with redirected stdout suppresses both the plan and
the restore line, so a scripted removal leaves no record; and there is no guard against removing
your own user.

## Error handling

| Failure | Behaviour |
| --- | --- |
| Quiet mode would hide the plan while still prompting | die in `preflight` (`remove-user` only; `list-users` has no gate) |
| Missing `aws` or `jq` | die |
| Profile or instance resolution fails | die, as `add-user` |
| `-e` not given, or not a valid email | die with usage |
| User does not exist | die — nothing to remove |
| An individual assignment or membership delete fails | report, count, continue |
| `ResourceNotFoundException` on a delete | treat as already-done |
| Any failure before `delete-user` | skip `delete-user`, report, exit 1 |
| Deletion polling times out | count as a failure, so `delete-user` is skipped |

## Verification

1. `./test.sh` passes, no new suppressions.
2. `dalmatian aws list-users` — 42 users, the 7 `DISABLED` ones visible, columns aligned.
3. `dalmatian aws list-users | grep DISABLED` returns rows, proving the payload survives a
   pipe. This is the check that would have caught the `log_msg` mistake.
4. `dalmatian aws list-users -j | jq '.[0]'` — valid JSON with a `Groups` array.
5. `dalmatian aws remove-user -n -e <a real user>` — plan lists that user's actual groups and
   grants, writes nothing.
6. `dalmatian aws remove-user -n -e nobody@example.com` — dies with "user not found".
7. `dalmatian aws remove-user -e <someone> > log` with stdin on a terminal — refuses, as
   `add-user` does.
8. `add-user` still works after the refactor: `./test.sh` plus one `-n -y` dry run. The full
   verification matrix from the previous spec is deliberately not repeated.
9. The destructive path is exercised only against a user nominated by the repo owner.
