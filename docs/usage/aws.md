# `dalmatian aws`

Commands for AWS IAM Identity Center (SSO) authentication, profile generation, user administration, account onboarding, and running AWS CLI commands against managed accounts.

---

## `dalmatian aws login`

**Safety:** Read-only (local SSO cache & browser auth)

Authenticates your local session with AWS IAM Identity Center (SSO).

### Syntax

```bash
dalmatian aws login [OPTIONS]
```

### Optional options

- `-p <aws_sso_profile>` — AWS SSO profile to authenticate with (defaults to `dalmatian-login`).
- `-f` — Force re-authentication even if an unexpired SSO session exists in `~/.aws/sso/cache/` (accepted by `getopts`, not shown in `-h`).
- `-h` — Show help.

### Expected output

If already logged in:

```text
==> Attempting AWS SSO login ...
==> You're already logged in. Your existing session will expire on 2026-11-24T18:00:00Z
```

If expired or `-f` is passed, opens the AWS SSO browser flow and prints:

```text
==> Attempting AWS SSO login ...
==> Checking AWS SSO login was successful...
==> AWS SSO login succeeded
```

### Under the hood

Reads `sso_start_url` for `dalmatian-login` from the installation's `dalmatian-sso.config`, checks `~/.aws/sso/cache/*.json` expiry against AWS NTP time (falling back to local `gdate`), and invokes `aws sso login --profile "$AWS_SSO_PROFILE"` if needed.

### Exit states

- `0` — Existing SSO session is valid, or browser SSO login succeeded and validated.
- Non-zero — Invalid flags/`-h` (`1`), missing `sso_start_url` in `dalmatian-sso.config` (`1`), SSO login validation failed (`1`), or `aws sso login` itself failed (AWS CLI exit code).

---

## `dalmatian aws account-init`

**Safety:** Potentially disruptive

Onboards an AWS account into Dalmatian by creating its Terraform `account-bootstrap` workspace, regenerating SSO profiles, refreshing tfvars, and running `deploy account-bootstrap`.

### Syntax

```bash
dalmatian aws account-init -i <aws_account_id> -r <default_region> -n <account_name> [OPTIONS]
```

### Required options

- `-i <aws_account_id>` — 12-digit AWS Account ID.
- `-r <default_region>` — Default AWS region (e.g. `eu-west-2`).
- `-n <account_name>` — Lower-case hyphenated friendly name (e.g. `client-prod`).

### Optional options

- `-d` — Enable deletion of default VPCs/resources during bootstrap (passes `-d` to `deploy account-bootstrap`).
- `-e` — Configure as an **External** AWS account (not part of the AWS SSO Organisation). Prefixes the workspace ID with `E` and prints the IAM Role trust policy required in the external account.
- `-h` — Show help.

### Expected output

Creates workspace `<account_id>-<region>-<account_name>`, runs `aws generate-config`, `terraform-dependencies get-tfvars`, and `deploy account-bootstrap`.

### Safety notes

- Passing `-d` enables default-resource deletion prompts on the **target** account's `deploy account-bootstrap` run. When `account_name` is not `dalmatian-main`, `-d` is also forwarded to the preliminary `dalmatian-main` bootstrap call, **but** because that preliminary call passes `-N` (non-interactive mode), `account-bootstrap` skips default-resource deletion on `dalmatian-main`. To delete default resources on `dalmatian-main`, pass `-d` when initialising `dalmatian-main` itself or run `dalmatian deploy delete-default-resources` / `dalmatian deploy account-bootstrap -d` against `dalmatian-main` directly.
- When `account_name` is not `dalmatian-main`, it first runs `deploy account-bootstrap -N` on `dalmatian-main`. This is an **auto-approved `terraform apply`** of any pending changes on the main account (it is what uploads the tfvars to S3), not just a file sync.

### Exit states

- `0` — Workspace created/selected and bootstrap completed, or external-account (`-e`) trust-policy prompt declined.
- Non-zero — Missing required flags (`-i`, `-r`, `-n`), `-h` (`1`), or Terraform/AWS failure.

---

## `dalmatian aws generate-config`

**Safety:** Potentially disruptive (rewrites local `dalmatian-sso.config`, re-clones the Terraform working copies, and may offer to create the state bucket)

Generates AWS SSO profiles for `dalmatian-login`, `dalmatian-main`, and every account workspace in `account-bootstrap`.

### Syntax

```bash
dalmatian aws generate-config [-h]
```

### Expected output

```text
==> Generating Dalmatian SSO configuration ...
```

### Under the hood

Stages a new `dalmatian-sso.config` atomically, preserving any custom/hand-edited sections not managed by Dalmatian. Runs `aws login`, `terraform-dependencies clone`, and `terraform-dependencies initialise`, then iterates `workspace list` to append a profile for each managed account.

### Exit states

- `0` — `dalmatian-sso.config` updated atomically.
- Non-zero — Invalid flags/positional args (`1`), `-h` (`1`), or failure in `aws login`, `terraform-dependencies`, or workspace listing. The live file has already had its `dalmatian-login`/`dalmatian-main` profiles refreshed by then; the other account profiles are kept as they were.

---

## `dalmatian aws list-profiles`

**Safety:** Read-only

Lists the friendly account names (AWS SSO profile names) derived from all `account-bootstrap` Terraform workspaces.

### Syntax

```bash
dalmatian aws list-profiles
```

### Expected output

```text
dalmatian-main
client-staging
client-prod
```

### Exit states

- `0` — Profiles listed. Also returned, with empty output, when listing the `account-bootstrap` workspaces fails ([#522](https://github.com/dxw/dalmatian-tools/issues/522)).

---

## `dalmatian aws list-users`

**Safety:** Read-only (also creates `dalmatian-identity-center` local profile if missing)

Lists every user in the AWS IAM Identity Center directory with their status and group memberships.

### Syntax

```bash
dalmatian aws list-users [-j] [-p <profile>] [-h]
```

### Optional options

- `-j` — Output JSON instead of a table.
- `-p <profile>` — AWS profile used to administer Identity Center (defaults to `dalmatian-identity-center`, created automatically if missing).
- `-h` — Show help.

### Expected output

Table of `USERNAME`, `STATUS`, `DISPLAY NAME`, `EMAIL`, and `GROUPS` (pipe-safe; `dalmatian aws list-users | grep DISABLED` works cleanly).

### Exit states

- `0` — Users listed (table or JSON).
- Non-zero — Invalid flags/`-h` (`1`), missing `aws`/`jq` (`1`), or Identity Center API failure.

---

## `dalmatian aws add-user`

**Safety:** Potentially disruptive

Creates a user in AWS IAM Identity Center, adds them to groups, and grants permission sets on accounts. Idempotent: re-running tops up missing memberships/grants.

### Syntax

```bash
dalmatian aws add-user [-e <email>] [-f <first>] [-l <last>] [-g <group>]... [-a <permset:account>]... [-p <profile>] [-n] [-y] [-h]
```

### Optional options

- `-e <email>` — Email address (also used as username; prompted if omitted).
- `-f <first>` — Given name (derived from email if omitted).
- `-l <last>` — Family name (derived from email if omitted).
- `-g <group>` — Group display name to join (repeatable).
- `-a <permset:account>` — Grant a permission set on an account (`account` may be a 12-digit ID or account name; repeatable).
- `-p <profile>` — AWS profile for Identity Center administration (defaults to `dalmatian-identity-center`).
- `-n` — Dry run: prints the plan without making AWS changes (still creates the local `dalmatian-identity-center` profile if missing).
- `-y` — Non-interactive: skips confirmation and takes groups/grants only from `-g`/`-a` (pass `-f`/`-l` too when scripting).
- `-h` — Show help.

### Safety notes

- AWS has no API to send the Identity Center invitation email; after running, send the login link from the AWS console URL printed in the summary.

### Exit states

- `0` — User created/updated, dry-run (`-n`) plan printed, or confirmation prompt declined.
- Non-zero — Invalid flags/`-h`, invalid email, missing `aws`/`jq`, interactive EOF, or Identity Center API failure.

### Examples

```bash
dalmatian aws add-user -e jane.doe@example.com
dalmatian aws add-user -e jane.doe@example.com -f Jane -l Doe -g Admin -a AdministratorAccess:123456789012 -y
```

---

## `dalmatian aws remove-user`

**Safety:** Destructive

Removes a user from AWS IAM Identity Center by revoking all direct account assignments, removing all group memberships, and then deleting the user record.

### Syntax

```bash
dalmatian aws remove-user -e <username> [-p <profile>] [-n] [-y] [-h]
```

### Required options

- `-e <username>` — Identity Center username (as shown in `dalmatian aws list-users`, which is not always an email address).

### Optional options

- `-p <profile>` — AWS profile for Identity Center administration.
- `-n` — Dry run: print the revocation and deletion plan without making AWS changes.
- `-y` — Skip the confirmation prompt.
- `-h` — Show help.

### Safety notes

- **Irreversible deletion:** The AWS API exposes `UserStatus` as read-only, so this command deletes rather than disables the user. Disabling a user must be done in the AWS console.
- Revokes assignments before deleting the user; if any teardown step fails, the user record is intentionally kept so grants are not orphaned.

### Exit states

- `0` — User and all direct assignments/memberships removed, dry-run (`-n`) plan printed, or confirmation declined.
- Non-zero — Missing `-e <username>`, `-h`, user not found (`ResourceNotFoundException`), or any revocation/deletion failure.

---

## `dalmatian aws put-secret`

**Safety:** Sensitive / Potentially disruptive

Stores a secret in AWS SSM Parameter Store at `/<infrastructure>/<environment>/<secret-name>` as a `SecureString` and prints its ARN.

### Syntax

```bash
dalmatian aws put-secret -i <infrastructure> -e <environment> -n <secret-name> [-v <secret-value>] [-k <kms-key-id>] [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-e <environment>` — Environment name (e.g. `staging`, `prod`).
- `-n <secret-name>` — Name/suffix of the secret (leading slashes are stripped).

### Optional options

- `-v <secret-value>` — Secret value. If omitted on a TTY, prompts securely without echoing; if piped via stdin, reads stdin (supports multiline secrets).
- `-k <kms-key-id>` — KMS key ID or alias (defaults to `alias/aws/ssm`).
- `-h` — Show help.

### Safety notes

- Avoid passing `-v` on the command line in shared shells or CI logs; prefer interactive prompting or stdin piping. Either way the value is passed to `aws ssm put-parameter` as a process argument (visible to `ps` while it runs), and is traced to stderr if `DALMATIAN_TOOLS_DEBUG` is set.
- **Overwrites without confirmation:** `put-secret` always passes `--overwrite` to `aws ssm put-parameter`, so writing to an existing secret name immediately replaces the stored value without prompting.

### Exit states

- `0` — Secret stored in SSM Parameter Store and ARN printed to stdout.
- Non-zero — Missing required flags (`-i`, `-e`, `-n`), `-h`, empty secret value (`1`), or AWS SSM failure.

---

## `dalmatian aws exec`

**Safety:** Potentially disruptive (depends on the AWS CLI subcommand executed)

Runs any `aws` CLI command against the resolved profile for an infrastructure and environment.

### Syntax

```bash
dalmatian aws exec -i <infrastructure> -e <environment> <aws subcommand...>
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-e <environment>` — Environment name.

### Under the hood

Delegates to `dalmatian aws run-command -i <infrastructure> -e <environment> <aws subcommand...>`.

### Examples

```bash
dalmatian aws exec -i my-infra -e staging s3 ls
```

### Exit states

- Propagates the exit code of the underlying `aws` CLI command (`1` on missing `-i`/`-e` or `-h`).

---

## `dalmatian aws run-command`

**Safety:** Potentially disruptive (depends on the AWS CLI subcommand executed)

Runs any `aws` CLI command using a resolved infrastructure/environment profile, an explicit Dalmatian account name, or an explicit AWS SSO profile.

### Syntax

```bash
dalmatian aws run-command [-p <aws_sso_profile> | -a <account_name> | -i <infrastructure> -e <environment>] <aws subcommand...>
```

### Options

- `-p <aws_sso_profile>` — Explicit AWS SSO profile name.
- `-a <dalmatian_account>` — Dalmatian account workspace, `<account_id>-<region>-<account_name>` (alternative to `-i`/`-e`; `-p` and `-i`/`-e` take precedence if also given).
- `-i <infrastructure_name>` — Infrastructure name (paired with `-e`).
- `-e <environment>` — Environment name (paired with `-i`).
- `-h` — Show help.

### Safety notes

- See the global [account resolution convention](../usage.md#2-global-usage-conventions): when multiple accounts share the same `<infrastructure>` and `<environment>` pair, `-i`/`-e` silently resolves to the first matching account workspace (`keys[0]`) and ignores `-a`. To target a specific account unambiguously, pass `-p <aws_sso_profile>`, or pass `-a <dalmatian_account>` **without** `-i`/`-e`.

### Examples

```bash
dalmatian aws run-command -a 123456789012-eu-west-2-client-prod sts get-caller-identity
```

### Exit states

- Propagates the exit code of the underlying `aws` CLI command (`1` on missing target flags or `-h`).
