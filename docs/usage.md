# Dalmatian Tools Usage (v2)

> [!IMPORTANT]
> This guide documents **Dalmatian Tools v2** (AWS IAM Identity Center / SSO).
>
> If you are operating legacy infrastructure launched with the private `dxw/dalmatian` repository, see the [v1 Legacy Usage Appendix](./usage-v1-legacy.md).

---

## 1. Version Model

Dalmatian Tools supports two command versions (`v1` and `v2`). Check or switch your active version at any time:

```bash
dalmatian version        # Show active version and release tag
dalmatian version -v 2   # Switch to v2 (current)
dalmatian version -v 1   # Switch to v1 (legacy)
```

---

## 2. Global Usage Conventions

- **List commands:** `dalmatian -l` prints all commands available in the active version.
- **Command help:** `dalmatian <subcommand> <command> -h` (or `dalmatian <command> -h` for top-level commands) prints the canonical flags and usage.
- **Quiet mode:** Pass `-q` to suppress informational `==>` output. Quiet mode is also enabled automatically when stdout is not a terminal (e.g. piped or redirected), except for v2 `setup` and `update`, which only go quiet with an explicit `-q`.
- **Interactive selection:** Commands that prompt from a list (such as `installation use` or `installation remove` without a name) use `fzf` when installed; set `DALMATIAN_FZF_ENABLED=0` for a numbered menu.
- **Multi-installation targeting:** Commands run against the default installation unless `DALMATIAN_INSTALLATION=<name>` is set. Under v2, when `DALMATIAN_INSTALLATION` overrides the default, the CLI prints a warning naming the active installation before running (not for `installation` or `version`).
- **Account resolution (`-i`/`-e`):** Commands that target `-i <infrastructure>` and `-e <environment>` resolve the AWS account from `dalmatian deploy list-infrastructures`. If multiple accounts share the same infrastructure/environment pair, the first matching workspace (`keys[0]`, sorted by workspace name) is selected silently without warning—and most commands (including `s3 empty-and-delete-bucket`, `cognito import-users`, `rds *`, and `service *`) do not accept `-p` or `-a`. Before running a mutating or destructive command, verify with `dalmatian deploy list-infrastructures` that the pair uniquely identifies the intended account; where a command supports `-p` or `-a` (such as `aws run-command`), prefer those.
- **Automatic update:** Under v2, top-level commands (other than `setup`, `update`, `installation`, and `version`) first run `dalmatian update -q`, which automatically pulls updates, re-clones Terraform working copies, and refreshes `.tfvars` if a newer GitHub release is available—even before `Read-only` commands—potentially discarding local changes in those working copies. Set `DALMATIAN_SKIP_UPDATE_CHECK=1` to prevent these automatic updates. Set `DALMATIAN_SKIP_UPDATE_PROMPT=1` to skip prompts when you have local changes in the `dalmatian-tools` checkout.
- **Exit codes:** Unless a command documents a specific non-standard exit code (e.g., `0` on a cancelled prompt, or `4`/`5` on `rds`), failures propagate the underlying tool's exit code (such as AWS CLI `252–255` or Terraform's own code).

---

## 3. Safety Taxonomy

Every command in the reference is classified using one of four safety levels, scoped to the requested command's own effects (note that the automatic pre-command updater runs unless `DALMATIAN_SKIP_UPDATE_CHECK=1` is set):

| Level | Meaning |
| --- | --- |
| **Read-only** | Makes no changes to AWS infrastructure or remote data for the requested command (local side effects documented on specific commands—such as writing SSO profiles, local `.cache/` files, or downloading logs/exports—and the pre-command updater may still occur). |
| **Sensitive** | Outputs or handles secrets, credentials, passwords, or PII (e.g. DB root passwords, env vars, user exports). Never paste output into tickets or chat. |
| **Potentially disruptive** | Mutates live infrastructure, configuration, deployments, or opens interactive sessions on live hosts/databases. Review targets and plans carefully. |
| **Destructive** | Permanently deletes data, buckets, databases, users, or local installations. Some commands prompt for confirmation (with `-y` to bypass, though prompts like `s3 empty-and-delete-bucket` and `deploy account-bootstrap -d` default to yes); others execute immediately without prompting (such as `deploy delete-default-resources -a <workspace>`, `rds shell`, and `rds run-command`). |

---

## 4. Common Operator Workflows

| Task | Command(s) |
| --- | --- |
| Set up a new or existing Dalmatian installation | `dalmatian setup` ([details](./usage/configure.md#dalmatian-setup)) |
| Switch between client/project installations | `dalmatian installation list` / `use` ([details](./usage/configure.md#dalmatian-installation)) |
| Authenticate via AWS SSO | `dalmatian aws login` ([details](./usage/aws.md#dalmatian-aws-login)) |
| Onboard and bootstrap an AWS account | `dalmatian aws account-init` (bootstraps the target account and `dalmatian-main` when needed) ([details](./usage/aws.md#dalmatian-aws-account-init)) |
| Deploy an infrastructure | `dalmatian deploy infrastructure` ([details](./usage/deploy.md#dalmatian-deploy-infrastructure)) |
| Deploy a service or check logs | `dalmatian service deploy` / `logs` ([details](./usage/service.md)) |
| Open a database shell or download a backup | `dalmatian rds shell` / `download-sql-backup` ([details](./usage/rds.md)) |
| Upgrade a database to a newer minor engine version | `dalmatian rds upgrade-engine` ([details](./usage/rds.md#dalmatian-rds-upgrade-engine)) |
| Clear CloudFront cache or fetch CDN logs | `dalmatian cloudfront clear-cache` / `logs` ([details](./usage/cloudfront.md)) |

---

## 5. Command Reference by Subcommand

### Configuration & Lifecycle
- **[Top-level configure commands](./usage/configure.md)** — `setup`, `installation`, `version`, `update`

### AWS & Accounts
- **[`dalmatian aws`](./usage/aws.md)** — `login`, `account-init`, `add-user`, `remove-user`, `list-users`, `list-profiles`, `generate-config`, `put-secret`, `exec`, `run-command`
- **[`dalmatian deploy`](./usage/deploy.md)** — `list-accounts`, `account-bootstrap`, `delete-default-resources`, `infrastructure`, `list-infrastructures`
- **[`dalmatian terraform-dependencies`](./usage/terraform-dependencies.md)** — `initialise`, `clone`, `get-tfvars`, `view-tfvars`, `set-tfvars`, `set-global-tfvars`, `clean-tfvars-cache`, `create-import-file`, `link-import-file`, `run-terraform-command`

### Compute & Services
- **[`dalmatian service`](./usage/service.md)** — `list-services`, `deploy`, `logs`, `container-access`, `get-environment-variables`, `set-environment-variables`, `run-scheduled-task`
- **[`dalmatian ec2`](./usage/ec2.md)** — `shell`, `access`, `port-forward`
- **[`dalmatian ecs`](./usage/ecs.md)** — `ec2-access`, `list-deployments`

### Databases
- **[`dalmatian rds`](./usage/rds.md)** — `shell`, `run-command`, `get-root-password`, `create-database`, `remove-database`, `create-user`, `update-user`, `remove-user`, `count-sql-backups`, `download-sql-backup`, `upgrade-engine`

### Edge, Storage, Identity & Auditing
- **[`dalmatian cloudfront`](./usage/cloudfront.md)** — `clear-cache`, `logs`
- **[`dalmatian waf`](./usage/waf.md)** — `list-rate-limited-ips`
- **[`dalmatian s3`](./usage/s3.md)** — `list-bucket-properties`, `empty-and-delete-bucket`
- **[`dalmatian cognito`](./usage/cognito.md)** — `list-pools`, `show-client`, `export-users`, `import-users`
- **[`dalmatian cloudtrail`](./usage/cloudtrail.md)** — `query`
- **[`dalmatian utilities`](./usage/utilities.md)** — `run-command`

---

## 6. Related Documentation

- [Installation](./installation.md)
- [Shell integration](./shell-integration.md)
- [FAQ](./faq.md)
- [v1 Legacy Usage Appendix](./usage-v1-legacy.md)
