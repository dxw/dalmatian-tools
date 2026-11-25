# `dalmatian cognito`

Commands for inspecting Cognito user pools and clients, and exporting/importing Cognito users.

---

## `dalmatian cognito list-pools`

**Safety:** Read-only

Lists Cognito user pools for an infrastructure environment as JSON (ID, ARN, deletion protection, tier, estimated user count).

### Syntax

```bash
dalmatian cognito list-pools -i <infrastructure> -e <environment> [-h]
```

### Exit states

- `0` — JSON printed.
- Non-zero — Missing `-i`/`-e`, `-h`, or Cognito API failure.

---

## `dalmatian cognito show-client`

**Safety:** Read-only (redacted by default) / Sensitive (when `-s` is passed)

Displays details for a Cognito user pool app client.

### Syntax

```bash
dalmatian cognito show-client -i <infrastructure> -e <environment> -p <pool> -c <client> [-s] [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-e <environment>` — Environment name.
- `-p <pool>` — Pool name (as defined in `infrastructure_cognito_user_pools`).
- `-c <client>` — Client name (as defined under the pool's clients).

### Optional options

- `-s` — Show the client secret (redacted by default).

### Exit states

- `0` — Client details printed.
- Non-zero — Missing `-i`/`-e`/`-p`/`-c`, `-h`, pool or client not found, or Cognito API failure.

---

## `dalmatian cognito export-users`

**Safety:** Sensitive (writes user PII to local CSV)

Exports users from a Cognito user pool into a CSV in Cognito's user-import format. The export is lossy: `cognito:username` is written as the email address, `cognito:mfa_enabled` is forced to `FALSE`, `email_verified` to `TRUE`, and no passwords or enabled/disabled state are carried, so re-imported users land in `RESET_REQUIRED` and must reset their passwords.

### Syntax

```bash
dalmatian cognito export-users -i <infrastructure> -e <environment> -p <pool> -o <csv_file> [-h]
```

### Required options

- `-i <infrastructure>`, `-e <environment>`, `-p <pool>`
- `-o <csv_file>` — Output CSV path (must not already exist; refuses to overwrite).

### Exit states

- `0` — Users exported atomically to `<csv_file>`.
- Non-zero — Missing required flags, `-h`, `<csv_file>` already exists, pool not found, or Cognito API failure.

---

## `dalmatian cognito import-users`

**Safety:** Potentially disruptive / Sensitive

Validates a CSV header against the target Cognito pool's `get-csv-header` schema and imports users into the pool.

### Syntax

```bash
dalmatian cognito import-users -i <infrastructure> -e <environment> -p <pool> -f <csv_file> [-F] [-h]
```

### Required options

- `-i <infrastructure>`, `-e <environment>`, `-p <pool>`
- `-f <csv_file>` — Readable CSV file matching the pool's import format.

### Optional options

- `-F` — Force import even if the pool already contains users.

### Safety notes

- **Partial imports and still-running jobs:** A non-zero exit does **not** mean no changes were made. Cognito may have already imported a subset of rows (`ImportedUsers > 0`) before failing, or the import job may still be running in AWS if status polling timed out (~1 hour / 720 polls) or `describe-user-import-job` failed 3 consecutive times. Always inspect the job status (`aws cognito-idp describe-user-import-job`) and CloudWatch logs (`/aws/cognito/userpools/<pool_id>/<job_id>`) before retrying (and pass `-F` only after checking, since the pool is now non-empty).

### Exit states

- `0` — CSV validated and Cognito import job succeeded (existing usernames are skipped via `SkippedUsers` without failing).
- Non-zero — Missing required flags, `-h`, unreadable CSV, CSV header mismatch, pool already has users without `-F`, polling timeout/failure, or import job failure (`Status != Succeeded` or `FailedUsers != 0`).
