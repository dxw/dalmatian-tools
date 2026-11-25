# `dalmatian rds`

Commands for connecting to RDS instances, running SQL/utility commands, managing databases and database users, retrieving root credentials, inspecting or downloading SQL backups, and upgrading minor engine versions.

---

## `dalmatian rds shell`

**Safety:** Destructive (interactive SQL session with the RDS admin credentials)

Starts an interactive database shell (`mysql` or `psql`) against an RDS instance via an ephemeral utilities container.

### Syntax

```bash
dalmatian rds shell -i <infrastructure> -r <rds_name> -e <environment> [-D <keep_alive_delay>] [-M <max_lifetime>] [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-r <rds_name>` — RDS name as defined in the Dalmatian config.
- `-e <environment>` — Environment name (e.g. `staging`, `prod`).

### Optional options

- `-D <keep_alive_delay>` — Delay in seconds to check for active `mysql`/`psql`/`bash` processes before exiting (default `60`).
- `-M <keep_alive_maximum_lifetime>` — Maximum container lifetime in seconds (default `600`).
- `-h` — Show help.

### Under the hood

Delegates to `dalmatian utilities run-command -i <infrastructure> -e <environment> -r <rds_name> -s -I`.

### Exit states

- `0` — Interactive session ended (errors inside the `mysql`/`psql` session are not reflected in the exit code).
- Non-zero — Missing `-i`/`-e`/`-r`, `-h` (`1`), RDS not found, utilities container failed to start, or `ecs execute-command` failed.

---

## `dalmatian rds run-command`

**Safety:** Destructive (runs SQL with the RDS admin credentials)

Runs a single non-interactive SQL statement in the RDS shell context via the utilities container.

### Syntax

```bash
dalmatian rds run-command -i <infrastructure> -r <rds_name> -e <environment> -c "<sql>" [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-r <rds_name>` — RDS name.
- `-e <environment>` — Environment name.
- `-c <sql>` — SQL statement to run (passed to `mysql -e` / `psql -c` as the RDS admin user; see [#556](https://github.com/dxw/dalmatian-tools/issues/556) for unquoted PostgreSQL handling).

### Exit states

- Propagates the exit status of the command run in the utilities container (`1` on missing `-i`/`-e`/`-r`/`-c`, `-h`, or task failure).

---

## `dalmatian rds get-root-password`

**Safety:** Sensitive

Retrieves the RDS-managed master root username and password from AWS Secrets Manager.

### Syntax

```bash
dalmatian rds get-root-password -i <infrastructure> -r <rds_name> -e <environment> [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-r <rds_name>` — RDS name.
- `-e <environment>` — Environment name.

### Safety notes

- Outputs plaintext database administrator credentials. In quiet mode (`-q` or piped), prints only the password. Never share or log this output.

### Exit states

- `0` — Root credentials retrieved and printed.
- Non-zero — Missing `-i`/`-e`/`-r`, `-h`, RDS has no RDS-managed root secret, or Secrets Manager failure.

---

## `dalmatian rds create-database`

**Safety:** Potentially disruptive / Sensitive (creates SSM password parameter)

Creates a database and a corresponding database user, storing the user's password in SSM Parameter Store at `/<infrastructure>/<environment>/rds/<rds_name>/<user_name>/password`.

### Syntax

```bash
dalmatian rds create-database -i <infrastructure> -r <rds_name> -e <environment> -d <db_name> -u <user_name> [-p | -f] [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-r <rds_name>` — RDS name.
- `-e <environment>` — Environment name.
- `-d <db_name>` — Database name to create.
- `-u <user_name>` — Database user name to create.

### Optional options

- `-p` — Read the user's password from a hidden prompt (or stdin when piped) instead of generating a random one.
- `-f` — Rerun after a failure: reuse the stored SSM password and skip whatever already exists (cannot be used with `-p`).
- `-h` — Show help.

### Exit states

- `0` — Database and user created (or verified with `-f`; note that `-f` leaves an existing user's database password unchanged without verifying it against SSM—use `dalmatian rds update-user` if you need to set a matching password in both places).
- Non-zero — Missing required flags, `-p` combined with `-f`, invalid DB/user name, password already stored in SSM without `-f`, or SQL/SSM failure.

---

## `dalmatian rds remove-database`

**Safety:** Destructive

Drops a database from the RDS instance (and on MySQL, revokes grants on it, which otherwise outlive `DROP DATABASE`).

### Syntax

```bash
dalmatian rds remove-database -i <infrastructure> -r <rds_name> -e <environment> -d <db_name> [-y] [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-r <rds_name>` — RDS name.
- `-e <environment>` — Environment name.
- `-d <db_name>` — Database name to drop.

### Optional options

- `-y` — Skip confirmation prompt.
- `-h` — Show help.

### Safety notes

- Permanently destroys the database and all its data.
- Leaves database users and their SSM parameters intact; remove users separately with `dalmatian rds remove-user`.
- PostgreSQL refuses to drop a database while active connections exist.

### Exit states

- `0` — Database dropped (or did not exist), or confirmation prompt declined.
- Non-zero — Missing required flags, `-h`, attempting to drop a system database, active PostgreSQL connections blocking drop, or SQL/task failure.

---

## `dalmatian rds create-user`

**Safety:** Potentially disruptive / Sensitive

Creates a database user with full privileges on an existing database (or database owner role on PostgreSQL) and stores its password in SSM Parameter Store at `/<infrastructure>/<environment>/rds/<rds_name>/<user_name>/password`.

### Syntax

```bash
dalmatian rds create-user -i <infrastructure> -r <rds_name> -e <environment> -d <db_name> -u <user_name> [-p | -f] [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-r <rds_name>` — RDS name.
- `-e <environment>` — Environment name.
- `-d <db_name>` — Existing database name to grant access to.
- `-u <user_name>` — User name to create.

### Optional options

- `-p` — Read password from hidden prompt or stdin instead of generating one.
- `-f` — Rerun after failure (cannot be combined with `-p`).

### Exit states

- `0` — User created and granted database access (or reconciled with `-f`; note that `-f` leaves an existing user's database password unchanged without verifying it against SSM—use `dalmatian rds update-user` if you need to set a matching password in both places).
- Non-zero — Missing required flags, `-p` combined with `-f`, invalid names (including MySQL user names over 32 characters), password already stored in SSM without `-f`, or SQL/SSM failure.
- `4` — Database does not exist (the SSM parameter stored by this run is removed).
- `5` — Database is owned by a privileged role; `create-user` only adds users to databases made by `create-database` (the SSM parameter stored by this run is removed).

---

## `dalmatian rds update-user`

**Safety:** Potentially disruptive / Sensitive

Rotates a database user's password in both the database and SSM Parameter Store (`/<infrastructure>/<environment>/rds/<rds_name>/<user_name>/password`).

### Syntax

```bash
dalmatian rds update-user -i <infrastructure> -r <rds_name> -e <environment> -u <user_name> [-p] [-y] [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-r <rds_name>` — RDS name.
- `-e <environment>` — Environment name.
- `-u <user_name>` — User name whose password to update.

### Optional options

- `-p` — Read new password from hidden prompt or stdin (piping stdin requires `-y`).
- `-y` — Skip confirmation prompt.

### Safety notes

- Services using this user will fail to connect until they pick up the new password.

### Exit states

- `0` — Password updated in both SSM Parameter Store and the RDS instance, or confirmation prompt declined.
- Non-zero — Missing required flags, `-h`, `-p` piped without `-y`, target user is the RDS root user, or SQL/SSM failure.
- `4` — User does not exist in the database. `update-user` attempts to restore the previous SSM parameter version (or delete it if none existed before), but still exits `4` if cleanup fails. Check the diagnostic output on stderr; `unknown` or other failures can also leave SSM holding the new password while the database outcome is uncertain.

---

## `dalmatian rds remove-user`

**Safety:** Destructive

Drops a user from the RDS instance and deletes its password parameter from SSM Parameter Store.

### Syntax

```bash
dalmatian rds remove-user -i <infrastructure> -r <rds_name> -e <environment> -u <user_name> [-y] [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-r <rds_name>` — RDS name.
- `-e <environment>` — Environment name.
- `-u <user_name>` — User name to remove (cannot be the RDS root username).

### Optional options

- `-y` — Skip confirmation prompt.

### Safety notes

- On PostgreSQL, a user that owns a database cannot be dropped; remove the database first.

### Exit states

- `0` — User dropped from RDS (or did not exist) and SSM parameter deleted, or confirmation prompt declined.
- Non-zero — Missing required flags, `-h`, target user is the RDS root user, PostgreSQL role owns a database, or SQL/SSM failure.

---

## `dalmatian rds count-sql-backups`

**Safety:** Read-only

Counts SQL backup objects in the `<prefix>-infrastructure-rds-s3-backups` S3 bucket matching a date prefix.

### Syntax

```bash
dalmatian rds count-sql-backups -i <infrastructure> -r <rds_name> -e <environment> [-d <date>] [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-r <rds_name>` — RDS name.
- `-e <environment>` — Environment name.

### Optional options

- `-d <date>` — Date prefix (`YYYY-MM-DD`, `YYYY-MM`, or `YYYY`; defaults to today).

### Exit states

- `0` — Backup count printed.
- Non-zero — Missing required flags, `-h`, invalid `-d` date format, or S3 API failure.

---

## `dalmatian rds download-sql-backup`

**Safety:** Sensitive (downloads database backup to local disk)

Lists and downloads a SQL backup from `<prefix>-infrastructure-rds-s3-backups` to `~/Downloads/<backup>` (or `-o`).

### Syntax

```bash
dalmatian rds download-sql-backup -i <infrastructure> -r <rds_name> -e <environment> [-o <output_file_path>] [-d <date>] [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-r <rds_name>` — RDS name.
- `-e <environment>` — Environment name.

### Optional options

- `-o <output_file_path>` — Local output path (defaults to `~/Downloads/<backup>`).
- `-d <date>` — Date prefix (`YYYY-MM-DD`, `YYYY-MM`, or `YYYY`; defaults to today).

### Exit states

- `0` — Backup downloaded to local path.
- Non-zero — Missing required flags, `-h`, invalid `-d` date format, no matching backups found, or S3 download failure.

---

## `dalmatian rds upgrade-engine`

**Safety:** Potentially disruptive (the database restarts when the upgrade is applied)

Upgrades an RDS instance or Aurora cluster to a newer **minor** engine version. By default the upgrade is queued for the next maintenance window; `-a` applies it now. Major version upgrades are not supported.

### Syntax

```bash
dalmatian rds upgrade-engine -i <infrastructure> -e <environment> [-r <rds_name>] [-v <target_version>] [-a] [-y] [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-e <environment>` — Environment name.

### Optional options

- `-r <rds_name>` — RDS name as defined in the Dalmatian config. If omitted, picks from the environment's RDS instances and Aurora clusters (Aurora member instances are left out).
- `-v <target_version>` — Minor engine version to upgrade to. Must exactly match one of the minor targets AWS offers for the current version; if omitted, picks from them.
- `-a` — Apply immediately instead of in the next maintenance window.
- `-y` — Skip the confirmation prompt.
- `-h` — Show help.

### Under the hood

All AWS calls go through `dalmatian aws run-command -p <profile>`, with the profile resolved from `-i`/`-e`.

1. Works out whether the name is a cluster or an instance, describes it, and refuses anything that is not `available`.
2. Lists minor targets from `describe-db-engine-versions --include-all` (`ValidUpgradeTarget` with `IsMajorVersionUpgrade` false). `--include-all` means a database on a deprecated version still gets its targets.
3. Prints a summary (to stderr when prompting, so `-q` or piped output cannot hide it): current and target versions, the weekly `PreferredMaintenanceWindow` (UTC) with its next concrete date and time, or "immediately", a suggested manual snapshot command, and any pending maintenance actions with the command to opt in to each. Nothing is opted in automatically. With `-a`, it also warns about other changes already pending on the database, which AWS applies at the same time.
4. Asks `y/N` (default no), then calls `modify-db-instance` or `modify-db-cluster` with `--engine-version` and `--no-apply-immediately` (or `--apply-immediately` with `-a`). `--allow-major-version-upgrade` is never passed.
5. Reads the database back from AWS to confirm the upgrade: a pending engine version, an `upgrading` status, the target version already running, or (for a queued cluster upgrade) a new `db-upgrade` pending maintenance action or one whose description names the target.
6. Prints when to change `engine_version` in the environment's tfvars (`dalmatian terraform-dependencies view-tfvars` / `set-tfvars`).

### Safety notes

- Change `engine_version` in the tfvars **after** the upgrade has happened and **before** the next deploy. Changed earlier, the next deploy applies the upgrade straight away instead of waiting for the window. Left unchanged, the next deploy fails, because AWS will not downgrade.
- A deploy that changes the database for any other reason before the window also applies a queued upgrade then.
- Take a snapshot first; the summary prints the command.

### Exit states

- `0` — Upgrade requested and confirmed by the read-back, already on the latest minor version (nothing to upgrade), or confirmation prompt declined.
- Non-zero — Missing `-i`/`-e`, `-h`, invalid names, database not `available`, AWS has no record of the current version, `-v` not one of the offered minor targets (including major targets), no terminal for a picker, AWS failure, or the upgrade was accepted but could not be confirmed by the read-back.
