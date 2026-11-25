# `dalmatian cloudtrail`

Commands for querying CloudTrail logs via Amazon Athena.

---

## `dalmatian cloudtrail query`

**Safety:** Potentially disruptive (depends on the supplied SQL)

Submits an Athena SQL query against the account's CloudTrail table, polls until completion, and prints the JSON query results.

> [!NOTE]
> The supplied `-Q` query is passed directly to Athena without restricting it to `SELECT`. Depending on your IAM permissions and workgroup configuration, DDL/DML statements can modify tables or write data.

### Syntax

```bash
dalmatian cloudtrail query -a <dalmatian_account> -Q "<athena_query>" [-h]
```

### Required options

- `-a <dalmatian_account>` — Dalmatian account name (`<account_id>-<region>-<name>`).
- `-Q <athena_query>` — SQL query to execute. Use the placeholder `CLOUDTRAIL` in place of the full table name; the command substitutes `cloudtrail_logs_<account_id>_<project>_cloudtrail_cloudtrail`.

### Examples

```bash
dalmatian cloudtrail query -a 210987654321-eu-west-2-client-prod -Q "select * from CLOUDTRAIL limit 50;"
```

### Exit states

- `0` — Athena query reached `SUCCEEDED` and results JSON printed.
- Non-zero — Missing `-a`/`-Q`, `-h`, or Athena API failure. (Note: if the Athena query transitions to `FAILED` or `CANCELLED`, the script polls until `SUCCEEDED` or interrupted.)
