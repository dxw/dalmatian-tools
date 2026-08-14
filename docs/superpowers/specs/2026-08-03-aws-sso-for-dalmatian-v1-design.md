# Design Spec: AWS SSO for Dalmatian v1 (dalmatian-tools)

Date: 2026-08-03

This spec covers the `dalmatian-tools` portion of a cross-repository change. The
authoritative design, including the rationale, the validation evidence and the changes to
the `dxw/dalmatian` repo, lives at
`dalmatian/docs/superpowers/specs/2026-08-03-aws-sso-for-dalmatian-v1-design.md`. Read
that first. Where the two disagree, the cross-repo spec wins.

## Overview

Make `dalmatian` v1 authenticate via AWS IAM Identity Center (SSO), reusing the
configuration and login flow v2 already has, instead of a GPG-encrypted IAM access key
pair and a TOTP MFA seed.

Only the entry credential changes. `bin/aws/v1/assume-infrastructure-role` and every v1
subcommand continue to work exactly as they do today, because v1 still receives its
credentials as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN`
environment variables.

## Background

v1 and v2 target the same main Dalmatian account (`511700466171`), which is already in the
dxw Identity Center with an `admin` permission set. The v1 `dalmatian-admin` and
`dalmatian-read` roles in each infrastructure account trust that account's `:root` with an
`sts:ExternalId` condition, so an SSO principal can assume them with no IAM changes. This
was verified live against three infrastructure accounts; see the cross-repo spec for the
evidence table.

## Goals

- v1 signs in with `aws sso login`, using the `setup.json` and `dalmatian-sso.config`
  that `dalmatian setup` already writes.
- The existing IAM-user path remains as an automatic fallback.
- One implementation of credential loading, consumable by the `dxw/dalmatian` repo.
- `./test.sh` (shellcheck) passes.

## Non-goals

- No changes to v2.
- No v1-specific setup command. v1 only ever reads the shared config, so v2's
  `bin/aws/v2/generate-config` remains free to rewrite `dalmatian-sso.config` wholesale.
- Removing the GPG/TOTP path. That is a follow-up change once the team has migrated.

## Design

### Decision: materialise static credentials

v1 resolves the `dalmatian-main` SSO profile into environment variables with
`aws configure export-credentials`, rather than setting `AWS_PROFILE`. All 81 v1
subcommands and three scripts in the `dxw/dalmatian` repo already expect credentials in
the environment, so this keeps the shape identical and confines the change to one place.
Requires aws-cli 2.9 or later.

### Decision: drop the main-account role assumption on the SSO path

`bin/dalmatian` currently assumes `dalmatian-admin` in `511700466171` before running any
command. Under SSO the `admin` permission set already has full access to that account, so
the hop is redundant, and keeping it would add a third link to the chain
(SSO role → main `dalmatian-admin` → infrastructure `dalmatian-admin`). Dropping it keeps
the infrastructure assumption a single hop with its full 1h session.
`assume_role_credentials.json` is unused on the SSO path. The legacy path is unchanged.

### Decision: auto-detect

SSO is used when both of the following hold:

- `$CONFIG_SETUP_JSON_FILE` exists and `.aws_sso.start_url` is a non-empty string.
- `$CONFIG_AWS_SSO_FILE` exists and contains a `[profile dalmatian-main]` section.

Otherwise the GPG/TOTP path runs and emits a deprecation warning. If neither is available,
fail with an explicit instruction to run `dalmatian version -v 2 && dalmatian setup`.

## Changes

### `bin/dalmatian`

1. **Hoist the shared config paths.** Move `CONFIG_DIR`, `CONFIG_SETUP_JSON_FILE` and
   `CONFIG_AWS_SSO_FILE` out of the `if [[ "$VERSION" == "v2" ]]` block (currently
   lines 201-217) to above the version branch, so both versions export them. Leave the
   remaining v2-only exports where they are.

   Do **not** hoist `AWS_CONFIG_FILE` or `AWS_PROFILE` (lines 236-237). v1 must not have
   `AWS_PROFILE` set globally, because it exports static credentials instead; and v1 users
   have a large unrelated `~/.aws/config` that must keep working for their other tooling.

1. **Extend the early-exit guard.** The v1 branch must dispatch `aws login` and
   `aws export-credentials` *before* attempting credential setup, or
   `dalmatian aws export-credentials` recurses infinitely. This mirrors the v2 guard at
   lines 270-281.

1. **Replace the v1 credential block** (lines 309-388: config.json read, MFA expiry check,
   GPG decrypt, `oathtool`, `bin/aws/v1/mfa` call, credential export) with:

   ```
   if SSO available:
     eval "$("$APP_ROOT/bin/aws/v1/export-credentials")"
   else:
     <existing GPG/TOTP block, plus deprecation warning>
   ```

   `AWS_DEFAULT_REGION=eu-west-2` (lines 323-324) stays as it is.

1. **Make the main-account assume-role conditional** (lines 394-447). Run it only on the
   legacy path.

1. **`AWS_CALLER_IDENTITY_USERNAME`** (lines 390-392) can stay as written. It splits the
   caller ARN on `/` and takes the third field minus its trailing character. Under SSO the
   ARN is `arn:aws:sts::511700466171:assumed-role/AWSReservedSSO_admin_<id>/<username>`,
   so it yields the correct username — better than today, where it yields the session name
   `dalmatian-tools`. Its only consumer is `bin/aws/v1/key-age`.

1. **Add v1 auto-login** before dispatching a command, so an expired SSO session is
   refreshed transparently. Model on the v2 block at lines 270-281, including its
   `IS_PARENT_SCRIPT` and `QUIET_MODE` handling so nested invocations stay quiet.

### `bin/aws/v1/login` (new)

Symlink to `../v2/login`, following the existing
`bin/configure-commands/v1/version -> ../v2/version` pattern.

`bin/aws/v2/login` needs one change to be safe under v1: default `AWS_CONFIG_FILE` to
`$CONFIG_AWS_SSO_FILE` when it is unset, since v1 does not export it globally. Without
this, `aws configure get sso_start_url --profile dalmatian-login` and
`aws sso login --profile …` read the user's own `~/.aws/config`, where those profiles do
not exist. This must not change v2 behaviour, where `AWS_CONFIG_FILE` is already set.

While in that file, tidy the unset-variable handling at lines 37-46: when `EXPIRES_AT` is
empty, `EPOCH` and `EXPIRES_AT_SEC` are never assigned and the `-gt` comparison relies on
bash coercing empty strings to 0. It works, but only incidentally.

### `bin/aws/v1/export-credentials` (new)

Prints shell `export` statements for the current credentials.

```
Usage: dalmatian aws export-credentials [OPTIONS]
  -h  - help
```

Behaviour:

1. Detect SSO as described above.
1. **SSO path:** run `"$APP_ROOT/bin/dalmatian" aws login -q >&2`, then
   `AWS_CONFIG_FILE="$CONFIG_AWS_SSO_FILE" aws configure export-credentials --profile dalmatian-main --format env`.
1. **Legacy path:** warn to stderr, refresh the MFA session if expired using the existing
   GPG/`oathtool`/`bin/aws/v1/mfa` logic, then print `export` lines assembled from
   `mfa_credentials.json`.
1. **Neither:** `err` and exit 1.

**Contract: stdout contains nothing but `export KEY=value` lines.** `log_info` and
`log_msg` write to stdout, and `aws sso login` prints its browser prompt there too, so the
login invocation is redirected to stderr and all diagnostics use `err` or an explicit
`>&2`. `bin/dalmatian` already forces `QUIET_MODE=1` when stdout is not a TTY
(lines 49-52), which helps for the command-substitution case but is not sufficient alone.

Check for aws-cli 2.9 or later on the SSO path and fail with an upgrade instruction rather
than letting `export-credentials` fail obscurely. `bin/aws/v1/awscli-version` only checks
the major version, so this needs a minor-version check — either extend that script or
check inline.

Note that `aws configure export-credentials` also emits `AWS_CREDENTIAL_EXPIRATION`. Pass
it through; it is harmless and useful for diagnostics.

### `bin/configure-commands/v1/login`

Split the script's two concerns:

- **Keep unconditionally:** the Homebrew check and `brew bundle install` (lines 30-48),
  `install_session_manager` (line 51), the `tfenv` link (lines 53-54) and the AWS CLI
  version check (lines 56-60). These are environment setup and are needed either way.
- **Make conditional:** the credential setup (lines 62-171). If SSO config is present,
  run `dalmatian aws login` and report the resulting identity instead of prompting for an
  access key, secret and MFA seed. Otherwise keep the existing prompts and add a
  deprecation warning naming `dalmatian version -v 2 && dalmatian setup`.

The `Note: You must have a Dalmatian Admin account…` message at line 27 should be reworded
for SSO.

### `bin/aws/v1/key-age`

Calls `aws iam list-access-keys --user-name "$AWS_CALLER_IDENTITY_USERNAME"`, which is
meaningless once there is no IAM user. On the SSO path, fail with a clear message
explaining that access key rotation does not apply under SSO. Keep it working on the
legacy path.

### Unchanged

| File | Why |
| --- | --- |
| `bin/aws/v1/assume-infrastructure-role` | Calls `sts assume-role --external-id dalmatian-tools` using ambient credentials. Verified working from an SSO session. |
| `bin/aws/v1/mfa` | Still needed by the fallback path. |
| `bin/dalmatian-refresh-config` | Uses `codepipeline get-pipeline` and `codebuild batch-get-projects` in the main account. Verified accessible. |
| Everything under `bin/*/v2/` | Out of scope. |

## Error handling

- **Recursion.** `dalmatian aws export-credentials` and `dalmatian aws login` must be
  dispatched before credential setup, else infinite recursion.
- **Stdout pollution** breaks the caller's `eval` and surfaces as a confusing credential
  error. See the contract above.
- **Expired SSO token.** `bin/aws/v1/login` re-runs `aws sso login`; it is a no-op while
  the cached token is valid, so it is safe to call unconditionally.
- **aws-cli older than 2.9.** Fail with an explicit upgrade instruction.
- **No SSO config, no legacy credentials.** Fail telling the user to run
  `dalmatian version -v 2 && dalmatian setup`.

## Risks

1. **Identity changes for v1 commands run without `-i`.** They now run as the SSO role
   rather than as `dalmatian-admin`. Permissions are equivalent — both have full access to
   `511700466171` — but implementation must include a deliberate pass over the v1
   subcommands for anything that inspects its own ARN or assumes an IAM user exists.
   `key-age` is the only known case.
1. **`eval` of a subcommand's stdout is fragile.** Mitigated by the stderr discipline and
   by an explicit test.
1. **Users who have not run `dalmatian setup` silently stay on the deprecated path.**
   Mitigated by the deprecation warning; also needs a comms step.

## Testing strategy

Automated:

- `./test.sh` passes (shellcheck across all scripts, including the new ones).
- `dalmatian aws export-credentials | grep -cv '^export '` returns 0.

Manual, on `dalmatian version -v 1`:

- `dalmatian aws login` on an expired session opens the browser and succeeds; on a valid
  session it reports the existing expiry and does nothing.
- `dalmatian config list-infrastructures` — main-account access with no `-i`.
- `dalmatian rds list-instances -i <infrastructure>` — infrastructure role assumption.
- `dalmatian aws exec -i <infrastructure> -- aws sts get-caller-identity` — confirms the
  ARN is `.../dalmatian-admin/…` in the infrastructure account.
- `dalmatian login` on a machine with SSO already configured skips the credential prompts
  but still runs the brew/tfenv/session-manager setup.
- `dalmatian version -v 2 && dalmatian deploy list-accounts` — confirms v2 is unaffected
  by the hoisted config exports.

Fallback: point `CONFIG_AWS_SSO_FILE` at a nonexistent path and confirm the GPG/TOTP path
still authenticates, warns, and assumes the main-account role as before.
