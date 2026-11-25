# `dalmatian deploy`

Commands for listing managed AWS accounts and infrastructures, bootstrapping accounts, deleting default AWS resources, and planning or applying Terraform infrastructure deployments.

---

## `dalmatian deploy list-accounts`

**Safety:** Read-only

Lists all Dalmatian account workspaces initialised in `account-bootstrap`.

### Syntax

```bash
dalmatian deploy list-accounts
```

### Expected output

```text
123456789012-eu-west-2-dalmatian-main
210987654321-eu-west-2-client-prod
```

### Exit states

- `0` — Accounts listed. Currently also returned, with empty output, when listing the `account-bootstrap` workspaces fails ([#587](https://github.com/dxw/dalmatian-tools/issues/587)).

---

## `dalmatian deploy list-infrastructures`

**Safety:** Read-only

Outputs a JSON object mapping each account workspace to its deployed infrastructure names, environments, and Terraform workspace names.

### Syntax

```bash
dalmatian deploy list-infrastructures
```

### Expected output

```json
{"accounts":{"210987654321-eu-west-2-client-prod":{"infrastructures":{"myapp":{"environments":["staging","prod"],"workspaces":["210987654321-eu-west-2-client-prod-myapp-staging","210987654321-eu-west-2-client-prod-myapp-prod"]}}}}}
```

### Exit states

- `0` — JSON printed. Currently also returned, as `{"accounts":{}}`, when a workspace listing fails ([#587](https://github.com/dxw/dalmatian-tools/issues/587)).

---

## `dalmatian deploy account-bootstrap`

**Safety:** Potentially disruptive (Destructive if `-d` is used to delete default resources)

Runs Terraform `plan` or `apply` against the `account-bootstrap` module for a single account or all initialised accounts.

### Syntax

```bash
dalmatian deploy account-bootstrap [OPTIONS]
```

### Optional options

- `-a <dalmatian-account>` — Target account workspace name (`<account_id>-<region>-<name>`). If omitted, prompts to confirm cycling through all initialised accounts.
- `-l` — Shortcut to `dalmatian deploy list-accounts`.
- `-p` — Run `terraform plan` instead of `terraform apply`.
- `-d` — If the `delete_default_resources` Lambda exists in state, prompt to invoke it after the plan or apply. **The prompt defaults to yes**, so pressing Enter deletes the default resources.
- `-N` — Add `--auto-approve` to `terraform apply` and disable the `-d` deletion. Do not combine with `-p` (Terraform rejects `plan --auto-approve`, [#588](https://github.com/dxw/dalmatian-tools/issues/588)); the all-accounts prompt is still shown when `-a` is omitted.
- `-h` — Show help.

### Under the hood

If targeting `dalmatian-main`, first refreshes tfvars via `terraform-dependencies get-tfvars -n`. Selects each matching workspace and runs `terraform apply` (or `plan`). An apply on `dalmatian-main` uploads the local tfvars cache to the S3 tfvars bucket, so any unpublished local edits go live with it.

### Examples

```bash
# Plan bootstrap changes for one account
dalmatian deploy account-bootstrap -a 210987654321-eu-west-2-client-prod -p

# Apply bootstrap changes across all accounts
dalmatian deploy account-bootstrap
```

### Exit states

- `0` — Plan/apply succeeded, `-l` listed accounts, all-accounts prompt was declined, or target `-a` workspace was not found (prints available accounts and exits `0`).
- Non-zero — Invalid flags/`-h` (`1`), or the exit code of a failed Terraform/AWS command. In all-accounts mode the first failure stops the run; later accounts are not processed.

---

## `dalmatian deploy delete-default-resources`

**Safety:** Destructive

Invokes the `<project_name>-delete-default-resources` Lambda function in one or all initialised accounts to delete default AWS VPCs and related default resources.

### Syntax

```bash
dalmatian deploy delete-default-resources [OPTIONS]
```

### Optional options

- `-a <dalmatian-account>` — Target account workspace name. If omitted, prompts for confirmation before cycling through all initialised accounts.
- `-l` — Shortcut to `dalmatian deploy list-accounts`.
- `-h` — Show help.

> [!WARNING]
> There is no dry run or non-interactive flag. Although `getopts` accepts `-p` and `-N` in its optstring, both fall through to `*) usage` and exit `1` before invoking AWS ([#589](https://github.com/dxw/dalmatian-tools/issues/589)). When `-a` is supplied, the Lambda is invoked without prompting. Exit `0` means `aws lambda invoke` succeeded, not that the deletion succeeded; check the invocation metadata printed to stdout for a `FunctionError` (the payload is written to `/tmp/<workspace>-delete-default-resources-output`).

### Safety notes

- Permanently removes default VPCs/subnets in the target account(s). Only run on accounts intended to be managed exclusively by Dalmatian.

### Exit states

- `0` — Lambda invoked, `-l` listed accounts, all-accounts prompt was declined, or target `-a` workspace was not found (prints available accounts and exits `0`).
- Non-zero — Invalid flags/`-h` (`1`), or AWS CLI failure.

---

## `dalmatian deploy infrastructure`

**Safety:** Potentially disruptive

Runs Terraform `plan`, `apply`, or `show -json` against the `infrastructure` Terraform module for a specific workspace or across matching account/infrastructure/environment workspaces.

### Syntax

```bash
dalmatian deploy infrastructure [OPTIONS]
```

### Optional options

- `-a <dalmatian_account>` — Target Dalmatian account name.
- `-i <infrastructure_name>` — Infrastructure name (lower-case letters only).
- `-e <environment_name>` — Environment name (lower-case letters only).
- `-w <workspace_name>` — Explicit Terraform workspace name (alternative to `-a`/`-i`/`-e`).
- `-l` — Shortcut to `dalmatian deploy list-infrastructures`.
- `-p` — Run `terraform plan` instead of `terraform apply`.
- `-o` — Requires `-p`. Writes the plan to `/tmp/<dalmatian_account>-<infrastructure_name>-<environment_name>.plan` (or `/tmp/<workspace_name>.plan`). On its own it builds `terraform apply -out=…`, which Terraform rejects.
- `-s` — Run `terraform show -json` on the plan file generated by `-o`.
- `-N` — Non-interactive mode (`--auto-approve` on apply). Do not combine with `-p` ([#588](https://github.com/dxw/dalmatian-tools/issues/588)); the workspace-creation and wildcard prompts still ask.
- `-h` — Show help.

### Safety notes

- Omitting `-a`, `-i`, `-e`, and `-w` cycles through workspaces; always pass `-p` first to preview changes before applying to production.
- If `-a` and `-e` match no existing workspace, it offers to **create a new Terraform workspace** and runs `terraform-dependencies get-tfvars` (which can overwrite cached tfvars from S3) **before** executing the selected Terraform operation (`plan`, `apply`, or `show -json`)—so these workspace and tfvars side effects still occur when previewing with `-p` or `-s`. Always pass `-i` too; without it the workspace name ends up as `<account>--<environment>`.
- Infrastructure and environment names must contain only lower-case letters (`^[a-z]+$`).

### Examples

```bash
# Plan an infrastructure deployment and save the plan file
dalmatian deploy infrastructure -a 210987654321-eu-west-2-client-prod -i myapp -e prod -p -o

# Apply using explicit workspace name
dalmatian deploy infrastructure -w 210987654321-eu-west-2-client-prod-myapp-prod
```

### Exit states

- `0` — Plan/apply/show succeeded, `-l` listed infrastructures, or user declined workspace-creation or wildcard-deploy prompt.
- Non-zero — Invalid flags/`-h` (`1`), non-lowercase `-i` or `-e` (`1`), non-existent `-w` workspace (`1`), or Terraform failure (Terraform's own exit code).
