# Dalmatian Tools v1 (Legacy) Usage

> [!IMPORTANT]
> This appendix covers **version 1 (legacy)** of Dalmatian Tools, used with infrastructures launched from the private `dxw/dalmatian` repository. When SSO is configured, v1 `dalmatian login` uses AWS IAM Identity Center (SSO) and falls back to deprecated IAM User credentials + MFA only when SSO is absent.
>
> For current **v2** (AWS IAM Identity Center / SSO) documentation, see [Usage](./usage.md).

Check or switch your active version at any time:

```bash
dalmatian version        # show active version
dalmatian version -v 1   # switch to v1 (legacy)
dalmatian version -v 2   # switch to v2 (current)
```

> [!TIP]
> 1. List all available v1 commands when v1 is active with `dalmatian -l`.
> 2. Add `-h` to any command (`dalmatian <subcommand> <command> -h`) to inspect its exact options.

---

## Available v1 Command Families

When `dalmatian version` is set to `v1`, the following top-level and subcommand families are available:

- **Top-level:** `login`, `version`
- **`aws`:** `assume-infrastructure-role`, `awscli-version`, `exec`, `export-credentials`, `instance-shell`, `key-age`, `login`, `mfa`
- **`aurora`:** `count-sql-backups`, `create-database`, `download-sql-backup`, `export-dump`, `get-root-password`, `import-dump`, `list-databases`, `list-instances`, `set-root-password`, `shell`, `start-sql-backup-to-s3`, `upgrade-engine`
- **`certificate`:** `create`, `delete`, `list`
- **`ci`:** `deploy-build-logs`, `deploy-status`
- **`cloudfront`:** `clear-cache`, `generate-basic-auth-password-hash`, `logs`
- **`config`:** `list-environments`, `list-infrastructures`, `list-services`, `list-services-by-buildspec`, `services-to-tsv`
- **`ecs`:** `ec2-access`, `efs-restore`, `file-download`, `file-upload`, `instance-refresh`, `list-deployments`, `remove-from-transfer-bucket`, `upload-to-transfer-bucket`
- **`elasticache`:** `list-clusters`, `reboot`
- **`rds`:** `count-sql-backups`, `create-database`, `download-sql-backup`, `export-dump`, `get-root-password`, `import-dump`, `list-databases`, `list-instances`, `set-root-password`, `shell`, `start-sql-backup-to-s3`, `upgrade-engine`
- **`service`:** `container-access`, `copy-environment-variables`, `delete-environment-variable`, `deploy`, `deploy-build-logs`, `deploy-status`, `ecr-vulnerabilities`, `force-deployment`, `get-environment-variable`, `list-container-placement`, `list-domains`, `list-environment-variables`, `list-pipelines`, `pull-image`, `rename-environment-variable`, `restart-containers`, `run-container-command`, `set-environment-variable`, `show-deployment-status`
- **`util`:** `env`, `exec`, `generate-four-words`, `ip-port-exposed`, `list-security-group-rules`
- **`waf`:** `cf-ip-block`, `delete-ip-rule`, `list-blocked-requests`, `list-rate-limited-ips`, `set-ip-rule`

---

### `dalmatian login`

The **login** command authenticates Dalmatian Tools v1 with AWS. When AWS SSO is configured (`dalmatian version -v 2 && dalmatian setup`), `dalmatian login` signs in via SSO and exports temporary credentials. Only when SSO is unavailable does it fall back to the **deprecated** IAM User access key + MFA secret flow (encrypted with GPG in `~/.config/dalmatian/credentials.json.enc`).

`dalmatian login` only persists credentials/tokens locally; it does **not** export AWS environment variables into your current shell. To export credentials into your shell for standalone `aws` CLI commands, assign the output first so a failed retrieval stops before `eval` runs (evaluating empty output would succeed and leave previous shell credentials active):

```bash
creds="$(dalmatian aws export-credentials)" && eval "$creds"
```

(If your active CLI version is `v2`, invoke `creds="$(/<path-to-dalmatian-tools>/bin/aws/v1/export-credentials)" && eval "$creds"` using the path to your `dalmatian-tools` checkout, or run `bin/aws/v1/export-credentials` from the checkout root.) On the SSO path this exports the `dalmatian-main` credentials used by v1 subcommands; on the deprecated IAM/MFA fallback it exports the MFA session credentials **without** Dalmatian's main-account role assumption.

As dalmatian requires that a number of packages are installed to your system in order to function effectively, the login command will check these exist and install any missing dependencies on your behalf before proceeding.

If you haven't already, please read the [installation guide](./installation.md).

### `dalmatian version`

The **version** command allows you to switch operation modes between version 1 (legacy) and version 2.

```
$ dalmatian version -v 1
==> Dalmatian Tools v1
==> The tooling available in v1 is to be used with infrastructure
==> launched with the dxw/dalmatian repo, which is private and internal
==> To use tooling for use with infrastructures deployed via dalmatian-tools,
==> switch to 'v2' by running 'dalmatian version -v 2'
```

### `dalmatian certificate`

This collection of tools allow an operator to manipulate certificates within AWS Certificate Manager.

#### `dalmatian certificate list`

This command will query AWS Certificate Manager for all certificates in a particular infrastructure and output a list containing the **ARN**, **Domain name**, and **Status** of each certificate.

```
$ dalmatian certificate list \
  -i "$infrastructure"
arn:aws:acm:eu-west-2:xxx:certificate/aaa-aaa-aaa-aaa-aaa my-example-domain.org EXPIRED
arn:aws:acm:eu-west-2:xxx:certificate/bbb-bbb-bbb-bbb-bbb my-example-domain.net ISSUED
arn:aws:acm:eu-west-2:xxx:certificate/ccc-ccc-ccc-ccc-ccc my-example-domain.com ISSUED
```

If you like to filter the output for a specific domain, you can adjust the command slightly and include the domain name as an option

```
$ dalmatian certificate list \
  -i "$infrastructure" \
  -d "my-example-domain.org"
arn:aws:acm:eu-west-2:xxx:certificate/aaa-aaa-aaa-aaa-aaa my-example-domain.org EXPIRED
arn:aws:acm:eu-west-2:xxx:certificate/aaa-aaa-bbb-bbb-bbb my-example-domain.org EXPIRED
```

If you are registering a new certificate and need to complete DNS validation, you can include both the domain and `-D` as an option to include the DNS records along with each certificate

```
$ dalmatian certificate list \
  -i "$infrastructure" \
  -d "my-example-domain.org" \
  -D
arn:aws:acm:eu-west-2:xxx:certificate/aaa-aaa-aaa-aaa-aaa my-example-domain.org EXPIRED
_c33dc71b006c460ed5ef53b6dcf57040.my-example-domain.org. CNAME _7330c60e670977e371567a560c6c1c05.aaa.acm-validations.aws.
_4416a7c8eb42f12439788a305cfcd8a5.www.my-example-domain.org. CNAME _86d26d74a9ad4a4d4571f1ed611c2b26.bbb.acm-validations.aws.
```

#### `dalmatian certificate delete`

This command will allow an operator to delete specific certificates from AWS Certificate Manager in a particular infrastructure.

You can delete certificates that match either a specific ARN, or you can specify a domain name. By specifying a domain name you can delete all certificates that are not in either `PENDING` or `ISSUED` state.

>[!CAUTION]
>This is a **destructive** action! You can add `-d` to this command to perform a dry-run and instead will print the commands it _would have_ executed to the output.
>
>When using `-D`, the script only excludes the literal statuses `PENDING` and `ISSUED`. Newly requested ACM certificates awaiting DNS validation have status `PENDING_VALIDATION` and **are eligible for deletion**.

```
$ dalmatian certificate delete \
  -i "$infrastructure" \
  -c "arn:aws:acm:eu-west-2:xxx:certificate/aaa-aaa-aaa-aaa-aaa"
```

```
$ dalmatian certificate delete \
  -i "$infrastructure" \
  -D "my-example-domain.org"
```

#### `dalmatian certificate create`

This command allows an operator to create a new certificate within AWS Certificate Manager for a particular infrastructure. This certificate can be used by CloudFront and ALBs.

```
$ dalmatian certificate create \
  -i "$infrastructure" \
  -d "my-domain-name.org"
```

Add additional Subject Alternative Names (SANs) to the certificate by specifying space separated domain names to `-s`:

```
$ dalmatian certificate create \
  -i "$infrastructure" \
  -d "my-domain-name.org" \
  -s "staging.my-domain-name.org parked.my-domain-name.org"
```

### `dalmatian util`

#### `dalmatian util list-security-group-rules`

Run this command to list all open ports across all security groups in a particular AWS Account.

```
$ dalmatian util list-security-group-rules
==> Open Ports in the account
my-rule-name-1,80-80,0.0.0.0/0
my-rule-name-2,443-433,sg-xxxxxx
my-rule-name-3,0-65535,127.0.0.1/32
```

Restrict to an infrastructure with `-i "$infrastructure"`.

#### `dalmatian util ip-port-exposed`

Query all security groups within an infrastructure and list rules with unrestricted IPv4 (`0.0.0.0/0`) inbound access, excluding lines matching `80` or `443`.

>[!NOTE]
>**Limitations:** This command only checks IPv4 `0.0.0.0/0` rules (IPv6 `::/0` is not checked) and filters output with `grep -E -v "80|443"`. Any line containing `80` or `443`—such as port `8080` or a security group name containing `443`—is excluded, so an empty result does not guarantee only ports 80/443 are exposed.

```
$ dalmatian util ip-port-exposed \
  -i "$infrastructure"
Searching ...
sg-aaaaaa162c8bf0303 my-security-group 3306 3306 0.0.0.0/0
Exposed port found!
Finished!
```

#### `dalmatian util env`

Print the shell environment variables for a specific infrastructure.

>[!CAUTION]
>This is a **sensitive** action! It will reveal sensitive data, including AWS Access Keys and AWS Session Tokens.
>**Do not share this information!**

#### `dalmatian util generate-four-words`

Generate passphrases for limited purposes such as Basic HTTP authentication gates (pass `-q` to suppress the warning).

#### `dalmatian util exec`

Execute a CLI command in an infrastructure (optionally pass `-i "$infrastructure"`).

### `dalmatian config`

Each of these scripts will first attempt to refresh your `dalmatian-config.yml` file if it is considered outdated (or use `DALMATIAN_CONFIG_PATH`).

- `dalmatian config list-services-by-buildspec -b "<buildspec>" [-i "<infrastructure>"]`
- `dalmatian config list-services ["<infrastructure>"]`
- `dalmatian config list-environments ["<infrastructure>"]`
- `dalmatian config list-infrastructures`
- `dalmatian config services-to-tsv`

### `dalmatian ci`

- `dalmatian ci deploy-status [-w]`
- `dalmatian ci deploy-build-logs -I "$infrastructure"`

>[!WARNING]
>Currently the automated Dalmatian v1 pipeline is halted. Any historic pipeline-based build logs are no longer available.

### `dalmatian cloudfront`

- `dalmatian cloudfront clear-cache -i "$infrastructure" -s "$service" -e "$environment" [-P "/path"]`
- `dalmatian cloudfront generate-basic-auth-password-hash`
- `dalmatian cloudfront logs -i "$infrastructure" -s "$service" -e "$environment" [-d "/path/"] [-p "YYYY-MM-DD"]` (downloads to `/tmp/$infrastructure-$service-$environment-cloudfront-logs` by default)

### `dalmatian aurora` and `dalmatian rds`

#### `dalmatian rds count-sql-backups` (and `dalmatian aurora count-sql-backups`)

>[!WARNING]
>The `dalmatian aurora count-sql-backups` wrapper drops its first argument (`${@:2}`) and always exits `0`. Call `dalmatian rds count-sql-backups` directly instead.

```
$ dalmatian rds count-sql-backups \
  -i "$infrastructure" \
  -r "$rds_name" \
  -e "$environment"
14
```

`DATE` defaults to **today** (`YYYY-MM-DD`) even when `-d` is omitted, so omitting `-d` counts today's backups rather than all retained backups. Pass `-d YYYY-MM-DD` to count backups for a specific date.

#### `dalmatian rds shell` (and `dalmatian aurora shell`)

Start a MySQL shell on a particular RDS/Aurora instance as the database Administrator user via an EC2 host using AWS Session Manager.

>[!CAUTION]
>This is a potentially **dangerous** action! Be mindful of connecting to production databases.

Pass `-l` to list available EC2 instance IDs, and `-I <instance_id>` to target a specific EC2 instance.

#### `dalmatian rds list-instances` (and `dalmatian aurora list-instances`)

```
$ dalmatian rds list-instances \
  -i "$infrastructure" \
  -e "$environment"
```

#### `dalmatian rds export-dump` (and `dalmatian aurora export-dump`)

>[!CAUTION]
>**Sensitive:** This command downloads a plaintext `.sql` database dump to local disk (the current working directory by default unless `-o` is specified). It also stages the dump at a fixed S3 transfer key (`s3://<infrastructure>-ecs-<environment>-dalmatian-transfer/db_exports/<database_name>-<environment>-sql-export.sql`) and deletes it after downloading, so avoid running concurrent exports for the same database and environment.

```
$ dalmatian rds export-dump \
  -i "$infrastructure" \
  -e "$environment" \
  -r "$rds_name" \
  -d "$database_name"
```

Optionally pass `-o "$HOME/Downloads/"` (avoid a literal quoted tilde `"~/Downloads/"`) for the output directory, and `-I "$instance_id"` for a specific EC2 instance.

#### `dalmatian rds upgrade-engine` and `dalmatian aurora upgrade-engine`

**Safety:** Potentially disruptive (the database restarts when the upgrade is applied)

Upgrades an RDS instance (`rds`) or an Aurora cluster (`aurora`) to a newer **minor** engine version. By default the upgrade is queued for the next maintenance window; `-a` applies it now. Major version upgrades are not supported. The two are separate scripts; combining the v1 `aurora` and `rds` commands is tracked in [#585](https://github.com/dxw/dalmatian-tools/issues/585).

```
$ dalmatian rds upgrade-engine \
  -i "$infrastructure" \
  -e "$environment" \
  [-r "$rds_name"] \
  [-v "$target_version"] \
  [-a] [-y]
```

`dalmatian aurora upgrade-engine` takes the same flags, with `-r` naming the Aurora cluster as defined in the Dalmatian config.

- `-r` — RDS or Aurora name as defined in the Dalmatian config. If omitted, picks from the environment's instances (or clusters).
- `-v` — Must exactly match one of the minor targets AWS offers for the current version (`describe-db-engine-versions --include-all`); if omitted, picks from them.
- `-a` — Apply immediately instead of in the next maintenance window.
- `-y` — Skip the `y/N` confirmation prompt (default no).

Before asking, it refuses a database that is not `available` and prints (to stderr when prompting) the current and target versions, the weekly maintenance window with its next concrete date and time (or "immediately"), a suggested `dalmatian aws exec` snapshot command, and pending maintenance actions with the command to opt in to each. Nothing is opted in automatically. With `-a` it also warns about other changes already pending on the database, which AWS applies at the same time. After the `modify-db-instance`/`modify-db-cluster` call it reads the database back from AWS and fails if the upgrade cannot be confirmed.

Afterwards it says whether `engine_version` in the infrastructure's `dalmatian-config` file (`config/infrastructures/<infrastructure>.yml`) needs changing. That value is shared by every environment, so it lists the versions the other environments are running, and suggests `major.minor` for MySQL.

>[!CAUTION]
>Change `engine_version` **after** the upgrade has happened and **before** the next deploy. Changed earlier, the next deploy applies the upgrade straight away instead of waiting for the window. Left unchanged, the next deploy fails, because AWS will not downgrade.

Exits `0` when the upgrade is requested and confirmed, when there is nothing to upgrade to, or when the confirmation prompt is declined.

#### Additional `aurora` and `rds` v1 commands

Run `dalmatian <rds|aurora> <command> -h` for exact flags:

- `list-databases`
- `start-sql-backup-to-s3`
- `download-sql-backup`
- `set-root-password`
- `get-root-password`
- `import-dump`
- `create-database`
