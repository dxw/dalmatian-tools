# `dalmatian waf`

Commands for inspecting AWS WAFv2 Web ACLs attached to CloudFront distributions.

---

## `dalmatian waf list-rate-limited-ips`

**Safety:** Read-only

Lists IP addresses currently being rate-limited by rate-based WAF rules for an infrastructure environment.

### Syntax

```bash
dalmatian waf list-rate-limited-ips -i <infrastructure> -e <environment> [-w <waf_name>] [-h]
```

### Required options

- `-i <infrastructure>` — Infrastructure name.
- `-e <environment>` — Environment name.

### Optional options

- `-w <waf_name>` — WAF name as keyed in `infrastructure_ecs_cluster_wafs` (defaults to all matching Web ACLs).
- `-h` — Show help.

### Under the hood

Queries `aws wafv2` with `--scope CLOUDFRONT --region us-east-1` (required by the CloudFront WAF API regardless of the account's default region).

### Exit states

- `0` — Rate-limited IPs listed (or none currently rate-limited).
- Non-zero — Missing `-i`/`-e`, `-h`, no matching Web ACL found, or WAFv2 API failure.
