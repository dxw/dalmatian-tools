# AWS SSO for Dalmatian v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `dalmatian` v1 obtain its entry AWS credentials from AWS IAM Identity Center (SSO), reusing the configuration `dalmatian setup` (v2) already writes, while keeping the existing GPG/TOTP IAM-user path as an automatic fallback.

**Architecture:** v1 keeps handing credentials to every subcommand as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` environment variables. Only the source of those variables changes: a new `bin/aws/v1/export-credentials` resolves the `dalmatian-main` SSO profile with `aws configure export-credentials` and prints `export` lines, which `bin/dalmatian` evaluates. Detection of "is SSO usable" is a single new bash function shared by every caller. On the SSO path the redundant `assume-role` hop into the main Dalmatian account is dropped.

**Tech Stack:** Bash 4+, aws-cli v2 (>= 2.9), `jq`, `gdate` (coreutils), `gpg` and `oathtool` (fallback path only), `shellcheck` for tests.

**Specs:**
- `docs/superpowers/specs/2026-08-03-aws-sso-for-dalmatian-v1-design.md` (this repo's portion)
- `../dalmatian/docs/superpowers/specs/2026-08-03-aws-sso-for-dalmatian-v1-design.md` (authoritative cross-repo design; read it first — where the two disagree, it wins)

## Global Constraints

- **aws-cli 2.9 or later is required** on the SSO path. `aws configure export-credentials` does not exist before then.
- **Main Dalmatian account is `511700466171`.** It is already in the dxw Identity Center with an `admin` permission set. No IAM, trust-policy or Terraform changes are in scope.
- **v2 behaviour must not change.** Nothing under `bin/*/v2/` changes except `bin/aws/v2/login`, and that change must be a no-op when `AWS_CONFIG_FILE` is already set (which it always is under v2).
- **v1 must not set `AWS_PROFILE` or `AWS_CONFIG_FILE` globally.** v1 exports static credentials instead, and v1 users have large unrelated `~/.aws/config` files that must keep working for their other tooling.
- **No v1-specific setup command.** v1 only ever *reads* `~/.config/dalmatian/setup.json` and `~/.config/dalmatian/dalmatian-sso.config`; `bin/aws/v2/generate-config` remains free to rewrite the latter wholesale.
- **`bin/aws/v1/export-credentials` stdout contains nothing but `export KEY=value` lines.** `log_info`/`log_msg` write to stdout and `aws sso login` prints its browser prompt to stdout, so every diagnostic in that script uses `err`, `warning`, or an explicit `>&2`.
- **Logging conventions:** `log_info -l "..." -q "$QUIET_MODE"` for informational output, `log_msg` for plain output, `warning "..."` and `err "..."` (both stderr) for warnings and errors. Never bare `echo` for these.
- **Do not remove the GPG/TOTP path.** It is the fallback; deleting it is a separate change once the team has migrated.
- **`bin/aws/v1/assume-infrastructure-role`, `bin/aws/v1/mfa` and `bin/dalmatian-refresh-config` are not modified.**
- **Deprecation wording, used verbatim wherever the legacy path is mentioned:** ``Run `dalmatian version -v 2 && dalmatian setup` to switch to AWS SSO``.

## Decisions already taken

Both were put to the human before execution began, and both are settled:

1. **The legacy GPG/TOTP block is duplicated between `bin/aws/v1/export-credentials` (Task 4) and `bin/dalmatian` (Task 5), and stays that way.** `bin/dalmatian` needs its own copy for `dalmatian aws mfa`'s forced refresh, the spec mandates the shape, and both copies are deleted together when the legacy path is removed. Do not de-duplicate it.
2. **Verification stays as scratch scripts, uncommitted.** This repo's only test harness is `test.sh` running shellcheck; adding a test directory is out of scope. Verification evidence belongs in the implementer's report, not in the repo.

## Amendments made during execution

The code below was written before implementation; where the shipped code now differs, the code is authoritative. Recorded here so the plan stays an honest record:

1. **`eval "$(...)"` became assign-then-`eval`** in both `bin/dalmatian` (Task 5) and `bin/configure-commands/v1/login` (Task 7). A command substitution used as a *command argument* discards its exit status under `set -e`, so a failed credential resolution continued silently and could run against whatever ambient AWS identity the user's shell held. The code blocks in Tasks 5 and 7 below were corrected; the amendment is commit `9b79333`.
2. **Nine review findings were fixed after Task 8**, in commits `76f316e`, `386826c`, `6c807d6`, `1d6a66b`, `43d7bc7`. The plan's code blocks were not retrospectively rewritten for these. They are: the README's `dalmatian login` transcript was missing the unconditional Session Manager install line, and its deprecation note now says no removal date is set; `bin/aws/v1/export-credentials` builds its legacy output in an assignment before printing, so a `jq` failure cannot emit a partial credential set; `bin/dalmatian` unsets `DALMATIAN_CREDENTIAL_EXPORTS` after the `eval` and moves `MFA_CONFIGURED` / `ASSUME_MAIN_ROLE_CONFIGURED` into the legacy branch that reads them; `bin/aws/v2/login` no longer sends `jq`'s stderr to `/dev/null` when reading the SSO token cache; and three cosmetic fixes (bracket consistency in `dalmatian_v1_sso_available`, a comment recording the version-regex invariant in `awscli-version`, and a distinct log line for the SSO branch of `dalmatian login`).
3. **Three of the plan's own verification steps were wrong**, found by implementers: Task 1 Step 2's expected RED output (7 of 8 checks accidentally pass before the function exists, because "command not found" is non-zero and so reads as `UNAVAILABLE`); Task 2 Step 3's prediction for the unparseable-version case (the old script already rejected it, for a different reason); and Task 3 Step 1's `run_login` helper, which cannot work as written because `bin/aws/v2/login` runs as a child process and so needs `export -f` on the sourced functions. Also note that jq 1.8.2 treats `string + null` as an identity operation rather than an error, so the partial-output hazard fix 2 closes is triggered by a wrong-*typed* field rather than a null one.

## Baseline facts you will need

Verified in this repo on 2026-08-13, before any of this work started:

- `./test.sh` **exits 0 but prints one pre-existing error**: `SC2148` against `./bin/custom/v2/.gitkeep`. That is not your bug and must not be fixed here. `test.sh` masks the exit status of the `./bin` pass, so always *read* the output rather than trusting the exit code.
- `find ./bin ... -type f` in `test.sh` does not match symlinks, so `bin/configure-commands/v1/version` is not shellchecked today and the new `bin/aws/v1/login` symlink will not be either. Shellcheck the symlink *target* instead.
- Installed aws-cli here: `aws-cli/2.36.22`. `AWS_CONFIG_FILE=~/.config/dalmatian/dalmatian-sso.config aws configure export-credentials --profile dalmatian-main --format env` prints exactly four lines: `export AWS_ACCESS_KEY_ID=…`, `export AWS_SECRET_ACCESS_KEY=…`, `export AWS_SESSION_TOKEN=…`, `export AWS_CREDENTIAL_EXPIRATION=…`.
- `~/.config/dalmatian/setup.json` contains `aws_sso.start_url`, `aws_sso.region`, `aws_sso.registration_scopes`, `aws_sso.default_admin_role_name`, `main_dalmatian_account_id`, `default_region`, `project_name`, `backend.s3.*`.
- `~/.config/dalmatian/dalmatian-sso.config` contains `[profile dalmatian-login]` (start URL, sso region, registration scopes) and `[profile dalmatian-main]` (`sso_account_id = 511700466171`, `sso_role_name = admin`, `region = eu-west-2`), followed by one profile per infrastructure account.
- Every lib file in `lib/bash-functions/` declares exactly one function, starting at column 0 with the literal word `function`. `bin/dalmatian` sources every file in that directory and `export -f`s each name it finds with `grep "^function" | cut -d" " -f2`, so a new file following that shape is automatically available (and exported) to every subcommand.
- Scripts that may be run *without* going through `bin/dalmatian` repeat a bootstrap block that sets `APP_ROOT`, sources `lib/bash-functions/*`, calls `check_bash_version` and defaults `QUIET_MODE` — see `bin/aws/v1/mfa:7-25`. `bin/aws/v1/key-age` deliberately does **not** have it (it is always run via `bin/dalmatian`).
- Only `bin/aws/v1/key-age` consumes `AWS_CALLER_IDENTITY_USERNAME`. `bin/{rds,aurora}/v1/start-sql-backup-to-s3` and `bin/ecs/v1/efs-restore` call `sts get-caller-identity --query Account`, but all three require `-i <infrastructure>` and so always run inside an assumed infrastructure-account role. That is the whole of the "commands that inspect their own identity" audit the spec asks for.
- `ACCOUNT_ID` and `DALMATIAN_ROLE` read from `~/.config/dalmatian/config.json` in `bin/dalmatian` are used only by the main-account `assume-role`, i.e. only by the legacy path.

Every code block in this plan was dry-run in a scratch copy of the repo while the plan was written: Task 1's function passes its eight checks, Task 2's replacement passes its seven, and the new and modified files in Tasks 1-5 are `shellcheck -x` clean. The Task 5 `bin/dalmatian` edits were applied by line number against the current `main` and the result passes `bash -n` and `shellcheck -x`, so the line numbers quoted below are correct as long as nothing else has touched that file.

## File structure

| File | Responsibility | Task |
| --- | --- | --- |
| `lib/bash-functions/dalmatian_v1_sso_available.sh` | **New.** Single source of truth for "is the AWS SSO configuration usable". Four callers. | 1 |
| `bin/aws/v1/awscli-version` | Modify. Raise the requirement from "major version 2" to ">= 2.9". | 2 |
| `bin/aws/v2/login` | Modify. Default `AWS_CONFIG_FILE`; fail clearly when the SSO config is missing; remove reliance on unset variables coercing to 0. | 3 |
| `bin/aws/v1/login` | **New symlink** to `../v2/login`. | 3 |
| `bin/aws/v1/export-credentials` | **New.** Prints `export` lines for the current credentials: SSO first, GPG/TOTP fallback. Consumed by `bin/dalmatian`, `bin/configure-commands/v1/login`, and (later, in the `dxw/dalmatian` repo) `scripts/bin/{test,plan,deploy}`. | 4 |
| `lib/bash-functions/export_aws_caller_identity_username.sh` | **New.** Exports `AWS_CALLER_IDENTITY_USERNAME` from the caller ARN; needed at two different points in `bin/dalmatian`. | 5 |
| `bin/dalmatian` | Modify. Hoist the shared config paths, early-dispatch `aws login`/`aws export-credentials`, branch the v1 credential setup, make the main-account `assume-role` legacy-only. | 5 |
| `bin/aws/v1/key-age` | Modify. Refuse to run on the SSO path. | 6 |
| `bin/configure-commands/v1/login` | Modify. Keep the environment setup unconditional; make the credential setup SSO-aware. | 7 |
| `README.md` | Modify. Document SSO sign-in; mark the IAM-user flow deprecated. | 8 |

## Testing approach

This repo has no unit-test framework — `test.sh` runs `shellcheck` only, and adding a framework is out of scope. So each task's "failing test" is an **executable verification command with an expected output**, run before and after the change. Where a command needs real AWS access it is marked **(needs an SSO session)**; run `dalmatian version -v 1` first, and if you cannot reach AWS, stop and report rather than guessing.

Restore-safe fallback-path harness, used in several tasks. It renames the SSO config so `dalmatian_v1_sso_available` returns false, and always puts it back:

```bash
sso_off() {
  local cfg="$HOME/.config/dalmatian/dalmatian-sso.config"
  trap 'mv -f "$cfg.plantest" "$cfg" 2>/dev/null || true' RETURN
  mv "$cfg" "$cfg.plantest"
  "$@"
}
```

---

### Task 1: `dalmatian_v1_sso_available` bash function

**Files:**
- Create: `lib/bash-functions/dalmatian_v1_sso_available.sh`
- Test: none (verified by the commands below)

**Interfaces:**
- Produces: `dalmatian_v1_sso_available` — takes no arguments, produces no output, returns `0` when the SSO configuration is usable and `1` otherwise. Reads `$CONFIG_SETUP_JSON_FILE` and `$CONFIG_AWS_SSO_FILE`, each falling back to its `$HOME/.config/dalmatian/...` default so the function works when called from a script that has not been through `bin/dalmatian`. Because it returns non-zero, callers must only ever call it in a conditional (`if dalmatian_v1_sso_available`, `if ! dalmatian_v1_sso_available`); a bare call under `set -e` would exit the script.

- [ ] **Step 1: Write the failing verification script**

Create `/tmp/verify-task1.sh` (a scratch file; do not commit it):

```bash
#!/usr/bin/env bash
# Verifies lib/bash-functions/dalmatian_v1_sso_available.sh
# Run from the repository root.

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

good_setup="$tmp/setup.json"
good_config="$tmp/sso.config"
printf '{"aws_sso":{"start_url":"https://dxw.awsapps.com/start#/"}}\n' > "$good_setup"
printf '[profile dalmatian-login]\nsso_start_url = https://dxw.awsapps.com/start#/\n\n[profile dalmatian-main]\nsso_account_id = 511700466171\n' > "$good_config"

printf '{"aws_sso":{"start_url":""}}\n' > "$tmp/empty-url.json"
printf '{"project_name":"dalmatian"}\n' > "$tmp/no-sso.json"
printf 'not json at all\n' > "$tmp/broken.json"
printf '[profile dalmatian-login]\nsso_start_url = https://dxw.awsapps.com/start#/\n' > "$tmp/no-main.config"

check() {
  local name="$1" expected="$2" setup="$3" config="$4" actual
  actual="$(
    CONFIG_SETUP_JSON_FILE="$setup" CONFIG_AWS_SSO_FILE="$config" \
      bash -c 'source lib/bash-functions/dalmatian_v1_sso_available.sh
               if dalmatian_v1_sso_available; then echo AVAILABLE; else echo UNAVAILABLE; fi'
  )"
  if [ "$actual" == "$expected" ]; then
    echo "PASS $name"
  else
    echo "FAIL $name (expected $expected, got $actual)"
  fi
}

check "both files present and valid" AVAILABLE "$good_setup" "$good_config"
check "neither file exists"          UNAVAILABLE "$tmp/nope.json" "$tmp/nope.config"
check "setup.json missing"           UNAVAILABLE "$tmp/nope.json" "$good_config"
check "sso config missing"           UNAVAILABLE "$good_setup" "$tmp/nope.config"
check "start_url empty"              UNAVAILABLE "$tmp/empty-url.json" "$good_config"
check "no aws_sso key"               UNAVAILABLE "$tmp/no-sso.json" "$good_config"
check "setup.json not valid json"    UNAVAILABLE "$tmp/broken.json" "$good_config"
check "no dalmatian-main profile"    UNAVAILABLE "$good_setup" "$tmp/no-main.config"
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash /tmp/verify-task1.sh`

Expected: every line reports `FAIL` (with `got` empty), because the function does not exist yet.

- [ ] **Step 3: Write the function**

Create `lib/bash-functions/dalmatian_v1_sso_available.sh`:

```bash
#!/usr/bin/env bash
set -e
set -o pipefail

# Check whether the AWS SSO configuration that Dalmatian v1 needs is usable.
#
# v1 only ever reads this configuration; `dalmatian setup` (v2) writes it.
# Returns non-zero, so only ever call this in a conditional.
#
# @usage if dalmatian_v1_sso_available; then ... fi
# @return 0 when the AWS SSO configuration is usable, 1 otherwise
function dalmatian_v1_sso_available {
  local setup_json_file aws_sso_file start_url

  setup_json_file="${CONFIG_SETUP_JSON_FILE:-$HOME/.config/dalmatian/setup.json}"
  aws_sso_file="${CONFIG_AWS_SSO_FILE:-$HOME/.config/dalmatian/dalmatian-sso.config}"

  if [[ ! -f "$setup_json_file" || ! -f "$aws_sso_file" ]]
  then
    return 1
  fi

  start_url="$(
    jq -r 'select((.aws_sso.start_url | type) == "string") | .aws_sso.start_url' \
      < "$setup_json_file" 2>/dev/null || true
  )"

  if [ -z "$start_url" ]
  then
    return 1
  fi

  if ! grep -q '^\[profile dalmatian-main\]' "$aws_sso_file"
  then
    return 1
  fi

  return 0
}
```

- [ ] **Step 4: Run the verification and shellcheck**

Run: `bash /tmp/verify-task1.sh && shellcheck -x lib/bash-functions/dalmatian_v1_sso_available.sh && ./test.sh`

Expected: eight `PASS` lines; no shellcheck output for the new file; `./test.sh` prints only the pre-existing `./bin/custom/v2/.gitkeep` `SC2148` error.

- [ ] **Step 5: Confirm the real configuration is detected**

With no environment overrides, the function must find the configuration `dalmatian setup` wrote:

```bash
bash -c 'source lib/bash-functions/dalmatian_v1_sso_available.sh
         if dalmatian_v1_sso_available; then echo AVAILABLE; else echo UNAVAILABLE; fi'
```

Expected: `AVAILABLE` on a machine that has run `dalmatian setup` (this one has). If it prints `UNAVAILABLE`, stop — the `$HOME/.config/dalmatian/...` defaults are wrong.

- [ ] **Step 6: Commit**

```bash
git add lib/bash-functions/dalmatian_v1_sso_available.sh
git commit -m "Add dalmatian_v1_sso_available bash function"
```

---

### Task 2: Require aws-cli 2.9 or later

**Files:**
- Modify: `bin/aws/v1/awscli-version:50-72`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `bin/aws/v1/awscli-version` exits 0 when the installed aws-cli is >= 2.9, and non-zero otherwise. Callers: `bin/configure-commands/v1/login` (Task 7) and `bin/aws/v1/export-credentials` (Task 4), which calls it as `QUIET_MODE=1 "$APP_ROOT/bin/aws/v1/awscli-version" > /dev/null`.

Why here: `aws configure export-credentials` was added in aws-cli 2.9. The current script only inspects the major version, so a 2.4 install would fail deep inside `export-credentials` with an unhelpful message.

- [ ] **Step 1: Record the current behaviour**

Run: `bin/aws/v1/awscli-version; echo "exit=$?"`

Expected (on this machine, aws-cli 2.36.22): `==> Detected AWS CLI major version: 2` and `exit=0`.

- [ ] **Step 2: Write the failing test**

Create `/tmp/verify-task2.sh` (scratch, do not commit). It shims a fake `aws` binary onto `$PATH` so several versions can be exercised:

```bash
#!/usr/bin/env bash
# Verifies bin/aws/v1/awscli-version. Run from the repository root.

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

check() {
  local name="$1" version_string="$2" expected="$3" actual
  cat > "$tmp/bin/aws" <<EOF
#!/usr/bin/env bash
echo "$version_string"
EOF
  chmod +x "$tmp/bin/aws"
  if PATH="$tmp/bin:$PATH" QUIET_MODE=1 bin/aws/v1/awscli-version > /dev/null 2>&1
  then
    actual=OK
  else
    actual=REJECTED
  fi
  if [ "$actual" == "$expected" ]; then
    echo "PASS $name"
  else
    echo "FAIL $name (expected $expected, got $actual)"
  fi
}

check "2.36.22"              "aws-cli/2.36.22 Python/3.14.6 Darwin/25.6.0 source/arm64" OK
check "2.9.0 (the floor)"    "aws-cli/2.9.0 Python/3.9.11 Darwin/22.1.0 source/arm64"   OK
check "2.8.13 (below floor)" "aws-cli/2.8.13 Python/3.9.11 Darwin/22.1.0 source/arm64"  REJECTED
check "2.4.6 (below floor)"  "aws-cli/2.4.6 Python/3.8.8 Darwin/21.1.0 source/x86_64"   REJECTED
check "1.29.0 (v1)"          "aws-cli/1.29.0 Python/3.11.4 Darwin/22.6.0 botocore/1.31" REJECTED
check "3.1.0 (future major)" "aws-cli/3.1.0 Python/3.14.0 Darwin/25.6.0 source/arm64"   OK
check "unparseable"          "some other tool 1.2.3"                                    REJECTED
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bash /tmp/verify-task2.sh`

Expected: `PASS` for the three cases the current script already gets right (`2.36.22`, `2.9.0`, `1.29.0`), and `FAIL` for `2.8.13`, `2.4.6`, `3.1.0` and `unparseable`.

- [ ] **Step 4: Replace the version check**

In `bin/aws/v1/awscli-version`, replace everything from `# Suppress errors and capture the major version number` (line 50) to the end of the file with:

```bash
AWSCLI_MINIMUM_MAJOR_VERSION=2
AWSCLI_MINIMUM_MINOR_VERSION=9

# Suppress errors and capture the full version number, eg "2.36.22"
version=$(aws --version 2>/dev/null | grep -oE 'aws-cli/[0-9]+\.[0-9]+\.[0-9]+' | cut -d '/' -f 2 || true)

if [ -z "$version" ]
then
  err "Could not determine the installed awscli version"
  exit 1
fi

major_version=$(echo "$version" | cut -d '.' -f 1)
minor_version=$(echo "$version" | cut -d '.' -f 2)

log_info -l "Detected AWS CLI version: $version" -q "$QUIET_MODE"

if [ "$major_version" -lt "$AWSCLI_MINIMUM_MAJOR_VERSION" ]
then
  err "awscli version $AWSCLI_MINIMUM_MAJOR_VERSION is not installed which is required for dalmatian-tools"

  if [ "$QUIET_MODE" == "0" ]
  then
    echo
    echo "If you have manually installed AWS CLI 1, you should run: "
    echo "    sudo rm -rf /usr/local/aws"
    echo "    sudo rm /usr/local/bin/aws"
    echo
    echo "If you installed it using Homebrew, you should run:"
    echo "    brew remove awscli awscli@1"
    echo "    brew install awscli"
  fi

  exit 1
fi

if [[
  "$major_version" -eq "$AWSCLI_MINIMUM_MAJOR_VERSION" &&
  "$minor_version" -lt "$AWSCLI_MINIMUM_MINOR_VERSION"
]]
then
  err "awscli $version is installed, but $AWSCLI_MINIMUM_MAJOR_VERSION.$AWSCLI_MINIMUM_MINOR_VERSION or later is required for dalmatian-tools"
  err "\`aws configure export-credentials\`, which Dalmatian uses to sign in with AWS SSO, was added in awscli $AWSCLI_MINIMUM_MAJOR_VERSION.$AWSCLI_MINIMUM_MINOR_VERSION"

  if [ "$QUIET_MODE" == "0" ]
  then
    echo
    echo "If you installed it using Homebrew, you should run:"
    echo "    brew upgrade awscli"
  fi

  exit 1
fi
```

Note the `grep -oE` now needs a full `x.y.z`, and `|| true` keeps `set -o pipefail` from killing the script when the pattern does not match — the explicit `-z` check reports that case properly.

- [ ] **Step 5: Run the tests**

Run: `bash /tmp/verify-task2.sh && shellcheck -x bin/aws/v1/awscli-version && bin/aws/v1/awscli-version`

Expected: seven `PASS` lines, no shellcheck output, and `==> Detected AWS CLI version: 2.36.22`.

- [ ] **Step 6: Commit**

```bash
git add bin/aws/v1/awscli-version
git commit -m "Require awscli 2.9 or later"
```

---

### Task 3: `dalmatian aws login` for v1

**Files:**
- Modify: `bin/aws/v2/login:33-46`
- Create: `bin/aws/v1/login` (symlink to `../v2/login`)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `dalmatian aws login` works under v1 as well as v2. `bin/aws/v1/login` is a symlink, matching the existing `bin/configure-commands/v1/version -> ../v2/version` pattern. It accepts `-p <aws_sso_profile>` (default `dalmatian-login`), `-f` (force re-login) and `-h`. It is a no-op while the cached SSO token is valid, so callers may run it unconditionally. Task 4 and Task 5 both invoke it as `"$APP_ROOT/bin/dalmatian" aws login [-q]`.

Why the `AWS_CONFIG_FILE` default: v2 exports `AWS_CONFIG_FILE="$CONFIG_AWS_SSO_FILE"` globally (`bin/dalmatian:236`) but v1 must not (Global Constraints). Without a local default, `aws configure get sso_start_url --profile dalmatian-login` and `aws sso login --profile …` would read the user's own `~/.aws/config`, where those profiles do not exist.

- [ ] **Step 1: Write the failing test**

`bin/aws/v2/login` needs the bash functions that `bin/dalmatian` normally sources and exports, and the bug only shows with `AWS_CONFIG_FILE` unset — which `bin/dalmatian` never does under v2. So invoke it directly, with the functions sourced by hand. Define this helper in your shell; Step 4 uses it again:

```bash
run_login() {
  env -u AWS_CONFIG_FILE bash -c '
    for f in lib/bash-functions/*; do
      # shellcheck disable=SC1090
      [ -f "$f" ] && source "$f"
    done
    QUIET_MODE=0
    bin/aws/v2/login "$@"
  ' -- "$@"
}
```

Run: `run_login; echo "exit=$?"`

Expected before the change: with `AWS_CONFIG_FILE` unset, `aws configure get sso_start_url --profile dalmatian-login` finds nothing in your own `~/.aws/config`, so `set -e` aborts with no explanation and a non-zero exit. Record exactly what you see. (If your personal `~/.aws/config` happens to contain a `dalmatian-login` profile, this will instead succeed — note that and rely on Step 4's check instead.)

- [ ] **Step 2: Default `AWS_CONFIG_FILE` and stop relying on unset variables**

In `bin/aws/v2/login`, replace lines 33-46 (from `START_URL=` down to and including the `]]` that closes the `if`) with:

```bash
# v1 does not export AWS_CONFIG_FILE globally, so default it here
if [ -z "$AWS_CONFIG_FILE" ]
then
  AWS_CONFIG_FILE="${CONFIG_AWS_SSO_FILE:-$HOME/.config/dalmatian/dalmatian-sso.config}"
  export AWS_CONFIG_FILE
fi

START_URL="$(aws configure get sso_start_url --profile dalmatian-login || true)"
if [ -z "$START_URL" ]
then
  err "Could not read 'sso_start_url' for the 'dalmatian-login' profile from $AWS_CONFIG_FILE"
  err "Run \`dalmatian version -v 2 && dalmatian setup\` to switch to AWS SSO"
  exit 1
fi

AWS_SSO_CACHE_JSON="$(grep -h -e "\"$START_URL\"" ~/.aws/sso/cache/*.json || true)"
EXPIRES_AT="$(echo "$AWS_SSO_CACHE_JSON" | jq -r 'select(.expiresAt != null) | .expiresAt' 2>/dev/null || true)"
EPOCH=0
EXPIRES_AT_SEC=0
log_info -l "Attempting AWS SSO login ..." -q "$QUIET_MODE"
if [ -n "$EXPIRES_AT" ]
then
  EXPIRES_AT_SEC="$(gdate -d "$EXPIRES_AT" +%s)"
  EPOCH="$(aws_epoch)"
fi
if [[
  "$EPOCH" -gt "$EXPIRES_AT_SEC" ||
  -z "$EXPIRES_AT" ||
  "$FORCE_RELOG" == "1"
  ]]
```

Leave lines 47-66 (the body of the `if` and the trailing "already logged in" message) exactly as they are. The `EPOCH=0` / `EXPIRES_AT_SEC=0` initialisation is behaviour-preserving: when `EXPIRES_AT` is empty the `-gt` comparison is `0 -gt 0` (false) and the `-z "$EXPIRES_AT"` clause still forces a login, which is what the old empty-string coercion did by accident.

Keep `--profile dalmatian-login` hardcoded on the `aws configure get` line. `-p` only ever overrides the profile passed to `aws sso login` (see `bin/aws/v2/generate-config:35`, the only caller that passes it, and it passes `dalmatian-login`); widening that is not this change's job.

- [ ] **Step 3: Create the v1 symlink**

```bash
ln -s ../v2/login bin/aws/v1/login
```

Verify: `ls -l bin/aws/v1/login` shows `bin/aws/v1/login -> ../v2/login`.

- [ ] **Step 4: Verify v2 is unaffected and v1 works** (needs an SSO session)

```bash
dalmatian version -v 2 && dalmatian aws login
dalmatian version -v 1 && dalmatian aws login
```

Expected: both print `==> Attempting AWS SSO login ...` followed by `==> You're already logged in. Your existing session will expire on <timestamp>` (or open a browser and report success if the token has expired). Note that until Task 5 lands, the v1 invocation reaches `bin/aws/v1/login` only if `dalmatian` gets that far — if the v1 run instead prompts for GPG or errors before printing the login message, that is expected at this point; re-run this check at the end of Task 5.

Also verify the missing-config error path, using the `run_login` helper from Step 1 so the bash functions are available:

```bash
sso_off() { local cfg="$HOME/.config/dalmatian/dalmatian-sso.config"; trap 'mv -f "$cfg.plantest" "$cfg" 2>/dev/null || true' RETURN; mv "$cfg" "$cfg.plantest"; "$@"; }
sso_off run_login; echo "exit=$?"
```

Expected: `[!] Error: Could not read 'sso_start_url' for the 'dalmatian-login' profile from /Users/<you>/.config/dalmatian/dalmatian-sso.config` followed by the `dalmatian version -v 2 && dalmatian setup` line, and `exit=1`. Afterwards confirm the config file is back: `ls ~/.config/dalmatian/dalmatian-sso.config`.

- [ ] **Step 5: Shellcheck**

Run: `shellcheck -x bin/aws/v2/login && ./test.sh`

Expected: no output for `bin/aws/v2/login`; `./test.sh` prints only the pre-existing `.gitkeep` error. (The symlink is not shellchecked; its target is.)

- [ ] **Step 6: Commit**

```bash
git add bin/aws/v2/login bin/aws/v1/login
git commit -m "Make aws login usable from dalmatian v1"
```

---

### Task 4: `bin/aws/v1/export-credentials`

**Files:**
- Create: `bin/aws/v1/export-credentials`

**Interfaces:**
- Consumes: `dalmatian_v1_sso_available` (Task 1); `bin/aws/v1/awscli-version` (Task 2); `dalmatian aws login` (Task 3).
- Produces: `dalmatian aws export-credentials` — prints `export KEY=value` lines on stdout and nothing else, for use as `eval "$(dalmatian aws export-credentials)"`. On the SSO path it prints `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` and `AWS_CREDENTIAL_EXPIRATION`; on the legacy path the first three only. Exits 1 with an explanatory error when neither credential source is configured. Consumed by `bin/dalmatian` (Task 5), `bin/configure-commands/v1/login` (Task 7) and, in a follow-up change in the `dxw/dalmatian` repo, `scripts/bin/{test,plan,deploy}`.

The legacy branch duplicates the GPG/TOTP logic that also remains in `bin/dalmatian` (Task 5). That is deliberate: `bin/dalmatian` must keep its own copy to support `dalmatian aws mfa`'s forced refresh, and both copies are deleted together when the legacy path is removed. Do not try to unify them here.

**Ordering note.** This script calls `"$APP_ROOT/bin/dalmatian" aws login -q`. The early dispatch that stops that call falling into v1's credential setup does not exist until Task 5, so while verifying this task the `aws login` call first runs the legacy GPG/MFA/assume-role chain — expect extra stderr output, and a GPG passphrase prompt if your MFA session has expired. That is transient and disappears in Task 5; it is not a bug in this script. If it blocks you, run `dalmatian aws mfa` once first to get a fresh 12h MFA session.

- [ ] **Step 1: Write the failing test**

Create `/tmp/verify-task4.sh` (scratch, do not commit):

```bash
#!/usr/bin/env bash
# Verifies bin/aws/v1/export-credentials. Run from the repository root.
# Needs a valid AWS SSO session.

fail=0

echo "== stdout contains only export lines =="
out="$(bin/aws/v1/export-credentials 2>/dev/null)"
if [ -z "$out" ]; then
  echo "FAIL produced no output"
  fail=1
else
  bad="$(echo "$out" | grep -cv '^export ' || true)"
  if [ "$bad" == "0" ]; then echo "PASS"; else echo "FAIL $bad non-export line(s)"; fail=1; fi
fi

echo "== the exported credentials work =="
if (eval "$(bin/aws/v1/export-credentials 2>/dev/null)"
    unset AWS_PROFILE
    export AWS_DEFAULT_REGION=eu-west-2
    aws sts get-caller-identity --query Account --output text) 2>/dev/null | grep -q '^511700466171$'
then echo "PASS"; else echo "FAIL did not reach account 511700466171"; fail=1; fi

echo "== all four SSO variables are present =="
for key in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_CREDENTIAL_EXPIRATION; do
  if echo "$out" | grep -q "^export $key="; then echo "PASS $key"; else echo "FAIL $key missing"; fail=1; fi
done

echo "== -h prints usage on stderr and exits non-zero =="
if bin/aws/v1/export-credentials -h > "/tmp/task4-h-stdout" 2>/dev/null
then echo "FAIL exited 0"; fail=1
else
  if [ -s /tmp/task4-h-stdout ]; then echo "FAIL usage went to stdout"; fail=1; else echo "PASS"; fi
fi

exit "$fail"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/verify-task4.sh`

Expected: every check `FAIL`s — the script does not exist.

- [ ] **Step 3: Write the script**

Create `bin/aws/v1/export-credentials` with this exact content, then `chmod +x bin/aws/v1/export-credentials`:

```bash
#!/usr/bin/env bash

# exit on failures
set -e
set -o pipefail

if [ -z "$APP_ROOT" ]; then
  APP_ROOT="$( cd "$(dirname "${BASH_SOURCE[0]}")"/../../.. && pwd -P)"
fi

if ! command -v log_info > /dev/null; then
  for f in "$APP_ROOT"/lib/bash-functions/*; do
    if [ -f "$f" ]; then
      # shellcheck disable=SC1090
      source "$f"
      while IFS='' read -r function_name; do
        export -f "${function_name?}"
      done < <(grep "^function" "$f" | cut -d" " -f2)
    fi
  done
fi

check_bash_version

QUIET_MODE="${QUIET_MODE:-0}"

usage() {
  echo "Print 'export' statements for the current Dalmatian AWS credentials" 1>&2
  echo "" 1>&2
  echo "Usage: $(basename "$0") [OPTIONS]" 1>&2
  echo "  -h  - help" 1>&2
  echo "" 1>&2
  echo "Only the credentials are written to stdout, so the output can be" 1>&2
  echo "evaluated directly:" 1>&2
  echo "  eval \"\$(dalmatian aws export-credentials)\"" 1>&2
  exit 1
}

while getopts "h" opt; do
  case $opt in
    h)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

DALMATIAN_CONFIG_STORE="${CONFIG_DIR:-$HOME/.config/dalmatian}"
DALMATIAN_CONFIG_FILE="$DALMATIAN_CONFIG_STORE/config.json"
DALMATIAN_CREDENTIALS_FILE="$DALMATIAN_CONFIG_STORE/credentials.json.enc"
DALMATIAN_MFA_CREDENTIALS_FILE="$DALMATIAN_CONFIG_STORE/mfa_credentials.json"

if dalmatian_v1_sso_available
then
  if ! QUIET_MODE=1 "$APP_ROOT/bin/aws/v1/awscli-version" > /dev/null
  then
    exit 1
  fi

  # `aws sso login` writes its browser prompt to stdout, which would corrupt
  # the credentials this script prints
  "$APP_ROOT/bin/dalmatian" aws login -q >&2

  AWS_CONFIG_FILE="${CONFIG_AWS_SSO_FILE:-$DALMATIAN_CONFIG_STORE/dalmatian-sso.config}" \
    aws configure export-credentials \
    --profile dalmatian-main \
    --format env
  exit 0
fi

if [ ! -f "$DALMATIAN_CONFIG_FILE" ]
then
  err "No AWS SSO configuration was found, and you are not logged into Dalmatian"
  err "Run \`dalmatian version -v 2 && dalmatian setup\` to switch to AWS SSO"
  exit 1
fi

warning "Dalmatian v1 is using a deprecated IAM user access key and MFA secret"
warning "Run \`dalmatian version -v 2 && dalmatian setup\` to switch to AWS SSO"

MFA_CONFIGURED=0
if [ -f "$DALMATIAN_MFA_CREDENTIALS_FILE" ]
then
  DALMATIAN_MFA_EXPIRATION=$(jq -r '.aws_session_expiration' < "$DALMATIAN_MFA_CREDENTIALS_FILE")
  DALMATIAN_MFA_EXPIRATION_SECONDS=$(gdate -d "$DALMATIAN_MFA_EXPIRATION" +%s)
  EPOCH=$(gdate +%s)
  if [ "$DALMATIAN_MFA_EXPIRATION_SECONDS" -lt "$EPOCH" ]
  then
    err "MFA credentials have expired"
  else
    MFA_CONFIGURED=1
  fi
fi

if [ "$MFA_CONFIGURED" == 0 ]
then
  DALMATIAN_CREDENTIALS_JSON_STRING=$(
    gpg --decrypt \
      --quiet \
      < "$DALMATIAN_CREDENTIALS_FILE"
  )

  AWS_ACCESS_KEY_ID=$(echo "$DALMATIAN_CREDENTIALS_JSON_STRING" | jq -r '.aws_access_key_id')
  AWS_SECRET_ACCESS_KEY=$(echo "$DALMATIAN_CREDENTIALS_JSON_STRING" | jq -r '.aws_secret_access_key')
  export AWS_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY

  AWS_MFA_SECRET=$(echo "$DALMATIAN_CREDENTIALS_JSON_STRING" | jq -r '.aws_mfa_secret')
  MFA_CODE="$(oathtool --base32 --totp "$AWS_MFA_SECRET")"

  log_info -l "Requesting new MFA credentials..." -q "$QUIET_MODE" >&2
  QUIET_MODE=1 "$APP_ROOT/bin/aws/v1/mfa" -m "$MFA_CODE" > /dev/null
fi

jq -r '
  "export AWS_ACCESS_KEY_ID=" + .aws_access_key_id,
  "export AWS_SECRET_ACCESS_KEY=" + .aws_secret_access_key,
  "export AWS_SESSION_TOKEN=" + .aws_session_token
' < "$DALMATIAN_MFA_CREDENTIALS_FILE"
```

- [ ] **Step 4: Run the tests**

Run: `bash /tmp/verify-task4.sh; echo "exit=$?"` then `shellcheck -x bin/aws/v1/export-credentials && ./test.sh`

Expected: all `PASS`, `exit=0`; no shellcheck output for the new script; `./test.sh` prints only the pre-existing `.gitkeep` error.

- [ ] **Step 5: Verify the legacy path**

```bash
sso_off() { local cfg="$HOME/.config/dalmatian/dalmatian-sso.config"; trap 'mv -f "$cfg.plantest" "$cfg" 2>/dev/null || true' RETURN; mv "$cfg" "$cfg.plantest"; "$@"; }
sso_off bin/aws/v1/export-credentials > /tmp/task4-legacy.txt
grep -cv '^export ' /tmp/task4-legacy.txt
```

Expected: the deprecation warnings on stderr, `0` from the `grep -c`, and three `export` lines in `/tmp/task4-legacy.txt`. If the MFA session has expired this will ask for your GPG passphrase first; that is correct. Then confirm the SSO config was restored: `ls ~/.config/dalmatian/dalmatian-sso.config`.

Also verify the "nothing configured" error:

```bash
tmp="$(mktemp -d)"; mkdir -p "$tmp/.config/dalmatian"
HOME="$tmp" bin/aws/v1/export-credentials; echo "exit=$?"
rm -rf "$tmp"
```

Expected: the two `err` lines about SSO configuration, and `exit=1`.

- [ ] **Step 6: Commit**

```bash
git add bin/aws/v1/export-credentials
git commit -m "Add aws export-credentials command"
```

---

### Task 5: Wire AWS SSO into `bin/dalmatian` for v1

**Files:**
- Create: `lib/bash-functions/export_aws_caller_identity_username.sh`
- Modify: `bin/dalmatian` — insert config exports before line 181; delete lines 201, 202 and 205; replace lines 309-447

**Interfaces:**
- Consumes: `dalmatian_v1_sso_available` (Task 1), `bin/aws/v1/export-credentials` (Task 4), `bin/aws/v1/login` (Task 3).
- Produces:
  - `CONFIG_DIR`, `CONFIG_SETUP_JSON_FILE` and `CONFIG_AWS_SSO_FILE` exported for **both** versions and for every configure-command.
  - `export_aws_caller_identity_username` — takes no arguments, exports `AWS_CALLER_IDENTITY_USERNAME` (consumed by `bin/aws/v1/key-age`, Task 6).
  - v1 credentials in `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` (plus `AWS_CREDENTIAL_EXPIRATION` on the SSO path) for every v1 subcommand — unchanged contract, new source.

Four separate edits. Do them in order.

- [ ] **Step 1: Write the failing test**

Create `/tmp/verify-task5.sh` (scratch, do not commit). Needs a valid SSO session.

Two command interfaces it relies on, both easy to get wrong:
- `dalmatian util exec <command…>` runs any command with the main-account credentials in its environment (`-i` is optional and buggy — do not pass it).
- `dalmatian aws exec -i <infrastructure> <aws-subcommand…>` prepends `aws` itself, so pass `sts get-caller-identity`, **not** `aws sts get-caller-identity`, and **no** `--`.

```bash
#!/usr/bin/env bash
# Verifies bin/dalmatian's v1 AWS SSO path. Run from the repository root.

fail=0
dalmatian version -v 1 > /dev/null

echo "== config paths are exported under v1 =="
if dalmatian util exec sh -c 'echo "$CONFIG_AWS_SSO_FILE"' 2>/dev/null | grep -q 'dalmatian-sso.config'
then echo "PASS"; else echo "FAIL CONFIG_AWS_SSO_FILE not exported"; fail=1; fi

echo "== no main-account assume-role on the SSO path =="
before="$(md5 -q "$HOME/.config/dalmatian/assume_role_credentials.json" 2>/dev/null || echo none)"
dalmatian util exec aws sts get-caller-identity > /tmp/task5-identity.json 2>/dev/null
after="$(md5 -q "$HOME/.config/dalmatian/assume_role_credentials.json" 2>/dev/null || echo none)"
if [ "$before" == "$after" ]; then echo "PASS"; else echo "FAIL assume_role_credentials.json was rewritten"; fail=1; fi

echo "== identity is the SSO role in the main account =="
if grep -q 'AWSReservedSSO' /tmp/task5-identity.json
then echo "PASS"; else echo "FAIL not an SSO identity:"; cat /tmp/task5-identity.json; fail=1; fi
if grep -q '511700466171' /tmp/task5-identity.json
then echo "PASS"; else echo "FAIL wrong account"; fail=1; fi

echo "== AWS_PROFILE is not set for subcommands =="
if [ -z "$(dalmatian util exec sh -c 'echo "$AWS_PROFILE"' 2>/dev/null | tail -n1)" ]
then echo "PASS"; else echo "FAIL AWS_PROFILE leaked through"; fail=1; fi

echo "== AWS_CALLER_IDENTITY_USERNAME is your username, not a session name =="
username="$(dalmatian util exec sh -c 'echo "$AWS_CALLER_IDENTITY_USERNAME"' 2>/dev/null | tail -n1)"
if [ -n "$username" ] && [ "$username" != "dalmatian-tools" ]
then echo "PASS ($username)"; else echo "FAIL got '$username'"; fail=1; fi

echo "== aws export-credentials does not recurse =="
if timeout 120 dalmatian aws export-credentials > /dev/null 2>&1
then echo "PASS"; else echo "FAIL non-zero exit or timeout"; fail=1; fi

echo "== main-account access with no -i =="
if dalmatian config list-infrastructures > /dev/null 2>&1
then echo "PASS"; else echo "FAIL"; fail=1; fi

echo "== aws mfa is refused on the SSO path =="
if dalmatian aws mfa 2>&1 | grep -q 'does not apply'
then echo "PASS"; else echo "FAIL"; fail=1; fi

exit "$fail"
```

`timeout` comes from coreutils (`brew install coreutils` provides it as `timeout` on recent Homebrew; use `gtimeout` if `timeout` is not found).

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/verify-task5.sh; echo "exit=$?"`

Expected: failures throughout, and (unless your MFA session is still valid) a GPG passphrase prompt, because v1 still uses the IAM-user path. `exit=1`.

- [ ] **Step 3: Hoist the shared config paths**

In `bin/dalmatian`, insert this immediately **before** the `if [[ (-f "$APP_ROOT/bin/configure-commands/$VERSION/$SUBCOMMAND" ...` block at line 181 — above the configure-commands dispatch, so that `dalmatian login` (Task 7) sees these too:

```bash
# Configuration paths shared by v1 and v2. v1 reads the AWS SSO configuration
# that `dalmatian setup` writes, but never writes it itself.
export CONFIG_DIR="$HOME/.config/dalmatian"
export CONFIG_SETUP_JSON_FILE="$CONFIG_DIR/setup.json"
export CONFIG_AWS_SSO_FILE="$CONFIG_DIR/dalmatian-sso.config"

```

- [ ] **Step 4: Delete the now-duplicated exports from the v2 block**

Delete these three lines from inside `if [[ "$VERSION" == "v2" ]]` (originally lines 201, 202 and 205):

```bash
  export CONFIG_DIR="$HOME/.config/dalmatian"
  export CONFIG_SETUP_JSON_FILE="$CONFIG_DIR/setup.json"
  export CONFIG_AWS_SSO_FILE="$CONFIG_DIR/dalmatian-sso.config"
```

Leave every other export in that block where it is — in particular `AWS_CONFIG_FILE` and `AWS_PROFILE` must stay v2-only.

- [ ] **Step 5: Add the caller-identity function**

Create `lib/bash-functions/export_aws_caller_identity_username.sh`:

```bash
#!/usr/bin/env bash
set -e
set -o pipefail

# Export the username portion of the current AWS caller identity ARN.
#
# Handles both an IAM user ARN
# (arn:aws:iam::<account>:user/dalmatian_admins/<username>) and an assumed role
# ARN (arn:aws:sts::<account>:assumed-role/<role>/<username>).
#
# @usage export_aws_caller_identity_username
# @export $AWS_CALLER_IDENTITY_USERNAME
function export_aws_caller_identity_username {
  local caller_identity_arn

  caller_identity_arn="$(aws sts get-caller-identity | jq -r '.Arn')"
  AWS_CALLER_IDENTITY_USERNAME="${caller_identity_arn##*/}"
  export AWS_CALLER_IDENTITY_USERNAME
}
```

This replaces `bin/dalmatian:390-392`, which split the *quoted* ARN on `/`, took field 3 and stripped its last character to remove the closing quote. That returned an empty string for any ARN without a path component; `${caller_identity_arn##*/}` is correct for both ARN shapes.

- [ ] **Step 6: Replace the v1 credential block**

Replace `bin/dalmatian` lines 309-447 — everything from `DALMATIAN_CONFIG_STORE="$HOME/.config/dalmatian"` down to and including the second `export AWS_SESSION_TOKEN` (the one after the "export assume role credentials" comment) — with:

```bash
DALMATIAN_CONFIG_STORE="$CONFIG_DIR"
DALMATIAN_CONFIG_FILE="$DALMATIAN_CONFIG_STORE/config.json"
DALMATIAN_CREDENTIALS_FILE="$DALMATIAN_CONFIG_STORE/credentials.json.enc"
DALMATIAN_MFA_CREDENTIALS_FILE="$DALMATIAN_CONFIG_STORE/mfa_credentials.json"
DALMATIAN_ASSUME_MAIN_ROLE_CREDENTIALS_FILE="$DALMATIAN_CONFIG_STORE/assume_role_credentials.json"
MFA_CONFIGURED=0
ASSUME_MAIN_ROLE_CONFIGURED=0

AWS_DEFAULT_REGION="eu-west-2" # London
export AWS_DEFAULT_REGION

# `aws login` and `aws export-credentials` have to be dispatched before any
# credential setup, otherwise `aws export-credentials` recurses into itself
if [[
  "$SUBCOMMAND" == "aws" &&
  ( "$COMMAND" == "login" || "$COMMAND" == "export-credentials" )
]]
then
  "$APP_ROOT/bin/aws/$VERSION/$COMMAND" "${COMMAND_ARGS[@]}"
  exit 0
fi

if dalmatian_v1_sso_available
then
  if [[ "$SUBCOMMAND" == "aws" && "$COMMAND" == "mfa" ]]
  then
    err "\`dalmatian aws mfa\` does not apply when Dalmatian is signing in with AWS SSO"
    err "Run \`dalmatian aws login\` to refresh your AWS SSO session"
    exit 1
  fi

  # Show the AWS SSO login output when dalmatian is called from another script
  if [[ "$IS_PARENT_SCRIPT" == 1 && "$QUIET_MODE" == 0 ]]
  then
    "$APP_ROOT/bin/dalmatian" aws login
  fi

  # `export-credentials` writes nothing but `export` statements to stdout.
  # Assign before evaluating: a command substitution used as a command argument
  # discards its exit status, so `eval "$(...)"` would silently continue with no
  # credentials if credential resolution failed. An assignment propagates it.
  DALMATIAN_CREDENTIAL_EXPORTS="$("$APP_ROOT/bin/aws/$VERSION/export-credentials")"
  eval "$DALMATIAN_CREDENTIAL_EXPORTS"

  # An AWS_PROFILE inherited from the user's environment would take precedence
  # over the credentials exported above
  unset AWS_PROFILE

  export_aws_caller_identity_username

  # The AWS SSO 'admin' permission set already has full access to the main
  # Dalmatian account, so there is no main-account role to assume
else
  if [ ! -f "$DALMATIAN_CONFIG_FILE" ]
  then
    err "No AWS SSO configuration was found, and you are not logged into Dalmatian"
    err "Run \`dalmatian version -v 2 && dalmatian setup\` to switch to AWS SSO"
    exit 1
  fi

  warning "Dalmatian v1 is using a deprecated IAM user access key and MFA secret"
  warning "Run \`dalmatian version -v 2 && dalmatian setup\` to switch to AWS SSO"

  DALMATIAN_CONFIG_JSON_STRING=$(cat "$DALMATIAN_CONFIG_FILE")
  ACCOUNT_ID=$(echo "$DALMATIAN_CONFIG_JSON_STRING" | jq -r '.account_id')
  DALMATIAN_ROLE=$(echo "$DALMATIAN_CONFIG_JSON_STRING" | jq -r '.dalmatian_role')

  # If MFA credentials exist, check if they have expired
  if [ -f "$DALMATIAN_MFA_CREDENTIALS_FILE" ]
  then
    DALMATIAN_MFA_CREDENTIALS_JSON_STRING=$(cat "$DALMATIAN_MFA_CREDENTIALS_FILE")
    DALMATIAN_MFA_EXPIRATION=$(echo "$DALMATIAN_MFA_CREDENTIALS_JSON_STRING" | jq -r '.aws_session_expiration')
    DALMATIAN_MFA_EXPIRATION_SECONDS=$(gdate -d "$DALMATIAN_MFA_EXPIRATION" +%s)
    EPOCH=$(gdate +%s)
    if [ "$DALMATIAN_MFA_EXPIRATION_SECONDS" -lt "$EPOCH" ]
    then
      err "MFA credentials have expired"
    else
      MFA_CONFIGURED=1
    fi
  fi

  if [[ "$SUBCOMMAND" == "aws" && "$COMMAND" == "mfa" ]]
  then
    RUN_AWS_MFA=1
  fi

  # Update MFA credentials if needed, or if the dalmatian aws mfa command is ran
  if [[ -n "$RUN_AWS_MFA" || "$MFA_CONFIGURED" == 0 ]]
  then
    DALMATIAN_CREDENTIALS_JSON_STRING=$(
      gpg --decrypt \
        --quiet \
        < "$DALMATIAN_CREDENTIALS_FILE"
    )

    AWS_ACCESS_KEY_ID=$(echo "$DALMATIAN_CREDENTIALS_JSON_STRING" | jq -r '.aws_access_key_id')
    AWS_SECRET_ACCESS_KEY=$(echo "$DALMATIAN_CREDENTIALS_JSON_STRING" | jq -r '.aws_secret_access_key')
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY

    AWS_MFA_SECRET=$(echo "$DALMATIAN_CREDENTIALS_JSON_STRING" | jq -r '.aws_mfa_secret')
    MFA_CODE="$(oathtool --base32 --totp "$AWS_MFA_SECRET")"

    log_info -l "Requesting new MFA credentials..." -q "$QUIET_MODE"
    "$APP_ROOT/bin/aws/$VERSION/mfa" -m "$MFA_CODE"

    if [ -n "$RUN_AWS_MFA" ]
    then
      exit 0
    fi
  fi

  # export MFA credentials
  DALMATIAN_MFA_CREDENTIALS_JSON_STRING=$(cat "$DALMATIAN_MFA_CREDENTIALS_FILE")
  AWS_ACCESS_KEY_ID=$(echo "$DALMATIAN_MFA_CREDENTIALS_JSON_STRING" | jq -r '.aws_access_key_id')
  AWS_SECRET_ACCESS_KEY=$(echo "$DALMATIAN_MFA_CREDENTIALS_JSON_STRING" | jq -r '.aws_secret_access_key')
  AWS_SESSION_TOKEN=$(echo "$DALMATIAN_MFA_CREDENTIALS_JSON_STRING" | jq -r '.aws_session_token')
  export AWS_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY
  export AWS_SESSION_TOKEN

  export_aws_caller_identity_username

  # Check if the assume role credentials have expired
  if [ -f "$DALMATIAN_ASSUME_MAIN_ROLE_CREDENTIALS_FILE" ]
  then
    DALMATIAN_ASSUME_MAIN_ROLE_CREDENTIALS_JSON_STRING=$(cat "$DALMATIAN_ASSUME_MAIN_ROLE_CREDENTIALS_FILE")
    DALMATIAN_ASSUME_MAIN_ROLE_CREDENTIALS_EXPIRATION=$(echo "$DALMATIAN_ASSUME_MAIN_ROLE_CREDENTIALS_JSON_STRING" | jq -r '.aws_session_expiration')
    DALMATIAN_ASSUME_MAIN_ROLE_CREDENTIALS_EXPIRATION_SECONDS=$(gdate -d "$DALMATIAN_ASSUME_MAIN_ROLE_CREDENTIALS_EXPIRATION" +%s)
    EPOCH=$(gdate +%s)
    if [ "$DALMATIAN_ASSUME_MAIN_ROLE_CREDENTIALS_EXPIRATION_SECONDS" -lt "$EPOCH" ]
    then
      err "'Assume role' credentials have expired"
    else
      ASSUME_MAIN_ROLE_CONFIGURED=1
    fi
  fi

  # Update assume role credentials if needed
  if [ "$ASSUME_MAIN_ROLE_CONFIGURED" == "0" ]
  then
    log_info -l "Requesting 'Assume Role' credentials ..." -q "$QUIET_MODE"
    ASSUME_ROLE_RESULT=$(
      aws sts assume-role \
      --role-arn "arn:aws:iam::$ACCOUNT_ID:role/$DALMATIAN_ROLE" \
      --role-session-name dalmatian-tools \
      --external-id dalmatian-tools
    )
    AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_RESULT" | jq -r '.Credentials.AccessKeyId')
    AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_RESULT" | jq -r '.Credentials.SecretAccessKey')
    AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_RESULT" | jq -r '.Credentials.SessionToken')
    AWS_SESSION_EXPIRATION=$(echo "$ASSUME_ROLE_RESULT" | jq -r '.Credentials.Expiration' | awk -F':' -v OFS=':' '{ print $1, $2, $3$4 }')
    DALMATIAN_ASSUME_MAIN_ROLE_CREDENTIALS_JSON_STRING=$(
      jq -n \
      --arg aws_access_key_id "$AWS_ACCESS_KEY_ID" \
      --arg aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" \
      --arg aws_session_token "$AWS_SESSION_TOKEN" \
      --arg aws_session_expiration "$AWS_SESSION_EXPIRATION" \
      '{
        aws_access_key_id: $aws_access_key_id,
        aws_secret_access_key: $aws_secret_access_key,
        aws_session_token: $aws_session_token,
        aws_session_expiration: $aws_session_expiration
      }'
    )

    echo "$DALMATIAN_ASSUME_MAIN_ROLE_CREDENTIALS_JSON_STRING" > "$DALMATIAN_ASSUME_MAIN_ROLE_CREDENTIALS_FILE"
  fi

  # export assume role credentials
  DALMATIAN_MFA_CREDENTIALS_JSON_STRING=$(cat "$DALMATIAN_ASSUME_MAIN_ROLE_CREDENTIALS_FILE")
  AWS_ACCESS_KEY_ID=$(echo "$DALMATIAN_MFA_CREDENTIALS_JSON_STRING" | jq -r '.aws_access_key_id')
  AWS_SECRET_ACCESS_KEY=$(echo "$DALMATIAN_MFA_CREDENTIALS_JSON_STRING" | jq -r '.aws_secret_access_key')
  AWS_SESSION_TOKEN=$(echo "$DALMATIAN_MFA_CREDENTIALS_JSON_STRING" | jq -r '.aws_session_token')
  export AWS_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY
  export AWS_SESSION_TOKEN
fi
```

Two deliberate differences from the code you are replacing, both inside the legacy branch:

1. The `if [ "${DALMATIAN_MFA_EXPIRATION: -1}" == "Z" ]` conditional at old lines 335-340 is gone. Both of its arms ran the identical `gdate` command.
2. The caller-identity lines at old 390-392 are replaced by `export_aws_caller_identity_username`, called at the same point — **before** the main-account `assume-role`. Do not move it after: at that point the ARN is `arn:aws:sts::…:assumed-role/dalmatian-admin/dalmatian-tools` and the username would become the session name.

Everything from `i=1` (old line 449, the `-i` argument scan) to the end of the file is unchanged and must stay outside the `if`/`else`.

- [ ] **Step 7: Run the tests**

Run: `shellcheck -x bin/dalmatian lib/bash-functions/export_aws_caller_identity_username.sh && ./test.sh && bash /tmp/verify-task5.sh; echo "exit=$?"`

Expected: no shellcheck output; `./test.sh` prints only the pre-existing `.gitkeep` error; every `verify-task5.sh` check `PASS`es with `exit=0`.

- [ ] **Step 8: Verify infrastructure role assumption still works** (needs an SSO session)

Substitute an infrastructure you have access to for `<infrastructure>` (`dalmatian config list-infrastructures` lists them):

```bash
dalmatian rds list-instances -i <infrastructure>
dalmatian aws exec -i <infrastructure> sts get-caller-identity
```

Expected: the RDS instances for that infrastructure, and an ARN of the form `arn:aws:sts::<infrastructure-account-id>:assumed-role/dalmatian-admin/dalmatian-tools`.

- [ ] **Step 9: Verify the fallback path is intact**

```bash
sso_off() { local cfg="$HOME/.config/dalmatian/dalmatian-sso.config"; trap 'mv -f "$cfg.plantest" "$cfg" 2>/dev/null || true' RETURN; mv "$cfg" "$cfg.plantest"; "$@"; }
sso_off dalmatian config list-infrastructures
ls ~/.config/dalmatian/dalmatian-sso.config
```

Expected: the two deprecation warnings on stderr, then the infrastructure list; `assume_role_credentials.json` is used or refreshed as before; the SSO config file is back afterwards.

- [ ] **Step 10: Verify v2 is unaffected**

```bash
dalmatian version -v 2 && dalmatian deploy list-accounts
dalmatian version -v 1
```

Expected: the account list, exactly as before this change.

- [ ] **Step 11: Commit**

```bash
git add bin/dalmatian lib/bash-functions/export_aws_caller_identity_username.sh
git commit -m "Sign v1 in with AWS SSO when it is configured"
```

---

### Task 6: Stop `key-age` running under SSO

**Files:**
- Modify: `bin/aws/v1/key-age:22-26`

**Interfaces:**
- Consumes: `dalmatian_v1_sso_available` (Task 1) — available because `bin/dalmatian` `export -f`s every lib function, which is also how this script already gets `err` and `warning`.
- Produces: nothing consumed elsewhere.

`aws iam list-access-keys --user-name …` is meaningless once there is no IAM user, and under SSO `AWS_CALLER_IDENTITY_USERNAME` is an Identity Center username rather than an IAM one, so the call fails with `NoSuchEntity`.

- [ ] **Step 1: Write the failing test**

Run: `dalmatian version -v 1 && dalmatian aws key-age; echo "exit=$?"`

Expected before the change: one of two things, depending on whether an IAM user with the same name as your Identity Center username still exists in `511700466171`. Either it lists that IAM user's access keys — misleading, because those keys have nothing to do with the credentials Dalmatian is now using — or it fails with `NoSuchEntity` / access denied and a non-zero exit. Record which you get.

- [ ] **Step 2: Add the guard**

In `bin/aws/v1/key-age`, insert immediately after the `while getopts … done` block (line 21) and before the `if [ -z "$AWS_CALLER_IDENTITY_USERNAME" ];` block:

```bash
if dalmatian_v1_sso_available
then
  err "Access key rotation does not apply when Dalmatian is signing in with AWS SSO"
  err "Your AWS credentials are short-lived and are issued by AWS IAM Identity Center"
  exit 1
fi

```

- [ ] **Step 3: Run the test**

Run: `dalmatian aws key-age; echo "exit=$?"`

Expected:

```
[!] Error: Access key rotation does not apply when Dalmatian is signing in with AWS SSO
[!] Error: Your AWS credentials are short-lived and are issued by AWS IAM Identity Center
exit=1
```

- [ ] **Step 4: Verify the legacy path still reports key ages**

```bash
sso_off() { local cfg="$HOME/.config/dalmatian/dalmatian-sso.config"; trap 'mv -f "$cfg.plantest" "$cfg" 2>/dev/null || true' RETURN; mv "$cfg" "$cfg.plantest"; "$@"; }
sso_off dalmatian aws key-age
```

Expected: `Access key ID: …`, `Created on: …`, `Age in days: …` for your IAM user's keys.

- [ ] **Step 5: Shellcheck and commit**

```bash
shellcheck -x bin/aws/v1/key-age && ./test.sh
git add bin/aws/v1/key-age
git commit -m "Do not check access key age when using AWS SSO"
```

---

### Task 7: SSO-aware `dalmatian login`

**Files:**
- Modify: `bin/configure-commands/v1/login:27` and `:62-171`

**Interfaces:**
- Consumes: `dalmatian_v1_sso_available` (Task 1), `bin/aws/v1/awscli-version` (Task 2), `dalmatian aws login` (Task 3), `bin/aws/v1/export-credentials` (Task 4), and the hoisted `CONFIG_*` exports (Task 5 — hoisted above the configure-commands dispatch precisely so this script sees them).
- Produces: nothing consumed elsewhere.

The script has two concerns. Everything down to line 60 — Homebrew, `brew bundle install`, `install_session_manager`, the `tfenv` link, the AWS CLI version check — is environment setup that both paths need and stays unconditional. Only the credential setup from line 62 becomes conditional.

- [ ] **Step 1: Write the failing test**

Run: `dalmatian version -v 1 && dalmatian login`

Expected before the change: after the brew/tfenv/session-manager output it prompts `Email associated with GPG key:` even though AWS SSO is configured. Answer nothing — press Ctrl-C — and record that it prompted.

- [ ] **Step 2: Reword the opening note**

Replace line 27:

```bash
echo "Note: You must have a Dalmatian Admin account to use Dalmatian Tools"
```

with:

```bash
echo "Note: You must have a Dalmatian admin account in the dxw AWS IAM Identity Center to use Dalmatian Tools"
```

- [ ] **Step 3: Make the credential setup conditional**

Insert this immediately after the AWS CLI version check block that ends at line 60 (`fi`), and before `DALMATIAN_CONFIG_STORE="$HOME/.config/dalmatian"`:

```bash
if dalmatian_v1_sso_available
then
  log_info -l "Signing in with AWS SSO ..." -q "$QUIET_MODE"
  "$APP_ROOT/bin/dalmatian" aws login

  # `aws sts get-caller-identity` needs a region, and this script does not go
  # through the credential setup in `bin/dalmatian` that would provide one
  export AWS_DEFAULT_REGION="eu-west-2"

  log_info -l "Checking credentials..." -q "$QUIET_MODE"
  # Assign before evaluating: a command substitution used as a command argument
  # discards its exit status, so `eval "$(...)"` would silently continue with no
  # credentials if credential resolution failed. An assignment propagates it.
  DALMATIAN_CREDENTIAL_EXPORTS="$("$APP_ROOT/bin/aws/v1/export-credentials")"
  eval "$DALMATIAN_CREDENTIAL_EXPORTS"
  # An AWS_PROFILE inherited from the user's environment would take precedence
  # over the credentials exported above
  unset AWS_PROFILE

  CALLER_ID=$(aws sts get-caller-identity)
  log_info -l "User ID: $(echo "$CALLER_ID" | jq -r '.UserId')" -q "$QUIET_MODE"
  log_info -l "Account: $(echo "$CALLER_ID" | jq -r '.Account')" -q "$QUIET_MODE"
  log_info -l "Arn:     $(echo "$CALLER_ID" | jq -r '.Arn')" -q "$QUIET_MODE"
  log_info -l "Login success!" -q "$QUIET_MODE"
  exit 0
fi

warning "Dalmatian v1 is being configured with a deprecated IAM user access key and MFA secret"
warning "Run \`dalmatian version -v 2 && dalmatian setup\` to switch to AWS SSO"

```

Everything from `DALMATIAN_CONFIG_STORE="$HOME/.config/dalmatian"` to the end of the file is unchanged.

- [ ] **Step 4: Run the test** (needs an SSO session)

Run: `dalmatian login`

Expected: the brew/tfenv/session-manager output and the AWS CLI version line as before, then:

```
==> Signing in with AWS SSO ...
==> Attempting AWS SSO login ...
==> You're already logged in. Your existing session will expire on <timestamp>
==> Checking credentials...
==> User ID: AROA…:<your-username>
==> Account: 511700466171
==> Arn:     arn:aws:sts::511700466171:assumed-role/AWSReservedSSO_admin_<id>/<your-username>
==> Login success!
```

No GPG, access key, secret key or MFA prompts, and no new `~/.config/dalmatian/config.json` or `credentials.json.enc`.

- [ ] **Step 5: Verify the legacy prompts survive**

```bash
sso_off() { local cfg="$HOME/.config/dalmatian/dalmatian-sso.config"; trap 'mv -f "$cfg.plantest" "$cfg" 2>/dev/null || true' RETURN; mv "$cfg" "$cfg.plantest"; "$@"; }
sso_off dalmatian login
```

Expected: the two deprecation warnings, then `Email associated with GPG key:`. Ctrl-C out — do not re-enter your access key. Confirm the SSO config file is back with `ls ~/.config/dalmatian/dalmatian-sso.config`.

- [ ] **Step 6: Shellcheck and commit**

```bash
shellcheck -x bin/configure-commands/v1/login && ./test.sh
git add bin/configure-commands/v1/login
git commit -m "Use AWS SSO for dalmatian login when it is configured"
```

---

### Task 8: Document AWS SSO sign-in

**Files:**
- Modify: `README.md:41-95`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing consumed elsewhere.

- [ ] **Step 1: Replace the "Login to dalmatian" step**

Replace README.md lines 41-78 (the numbered `1. Login to dalmatian` step, from `1. Login to dalmatian` up to and including `Once you're signed in you can safely close the AWS Access Key dialog.`) with:

````markdown
1. Configure AWS SSO

  Dalmatian signs in with AWS IAM Identity Center. The configuration is written
  by `dalmatian setup`, and is shared by v1 and v2:

  ```
  $ dalmatian version -v 2
  $ dalmatian setup
  ```

  You only need to do this once. See
  [README-in-development.md](README-in-development.md) for what `dalmatian setup`
  asks for.

1. Login to dalmatian

  Run the `dalmatian login` command. It installs and updates the dependencies
  Dalmatian Tools needs, then signs you in with AWS SSO, opening your browser if
  your session has expired.

  ```
  $ dalmatian login
  Note: You must have a Dalmatian admin account in the dxw AWS IAM Identity Center to use Dalmatian Tools

  ==> Updating brew packages ...
  ==> Ensuring tfenv is configured ...
  ==> Checking AWS CLI is the correct version ...
  ==> Detected AWS CLI version: 2.36.22
  ==> Signing in with AWS SSO ...
  ==> Attempting AWS SSO login ...
  ==> You're already logged in. Your existing session will expire on 2026-08-13T22:15:31Z
  ==> Checking credentials...
  ==> User ID: XXXXXXXXXXXXXXXXXXXXX:alex
  ==> Account: XXXXXXXXXXXX
  ==> Arn:     arn:aws:sts::XXXXXXXXXXXX:assumed-role/AWSReservedSSO_admin_XXXXXXXXXXXXXXXX/alex
  ==> Login success!
  ```

  Your session lasts about 8 hours. Any `dalmatian` command refreshes it for you
  when it expires, or you can run `dalmatian aws login` yourself.

  To use the credentials in your own shell:

  ```
  $ eval "$(dalmatian aws export-credentials)"
  ```

### Deprecated: IAM user credentials

Before AWS SSO, Dalmatian v1 signed in with a long-lived IAM user access key and
a TOTP MFA secret, held GPG-encrypted in
`~/.config/dalmatian/credentials.json.enc`. That path still works, and is used
automatically if no AWS SSO configuration is found, but it is deprecated and
will be removed. If you see

```
[!] Warning: Dalmatian v1 is using a deprecated IAM user access key and MFA secret
```

run `dalmatian version -v 2 && dalmatian setup` to switch to AWS SSO.
````

- [ ] **Step 2: Move the oathtool FAQ under the deprecation heading**

The `### Why am I seeing "oathtool: base32 decoding failed…"` FAQ entry (lines 82-95 of the original) only applies to the deprecated path. Leave the text as it is, but add this as its first line:

```markdown
This applies only to the deprecated IAM user credentials described above.
```

- [ ] **Step 3: Check the result reads correctly**

Run: `grep -n "SSO\|deprecated\|MFA" README.md`

Expected: the SSO instructions appear in the installation steps; every remaining MFA/access-key reference sits under the deprecation heading or the FAQ.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "Document signing in with AWS SSO"
```

---

## Final verification

Run all of it, in this order, and paste the output into the PR description:

- [ ] `./test.sh` — output contains only the pre-existing `./bin/custom/v2/.gitkeep` `SC2148` error.
- [ ] `git diff --stat main` — touches only the ten files in the File structure table.
- [ ] `dalmatian version -v 1 && dalmatian aws export-credentials | grep -cv '^export '` — prints `0`.
- [ ] `bash /tmp/verify-task1.sh`, `/tmp/verify-task2.sh`, `/tmp/verify-task4.sh`, `/tmp/verify-task5.sh` — all `PASS`.
- [ ] `dalmatian config list-infrastructures` — main-account access with no `-i`.
- [ ] `dalmatian rds list-instances -i <infrastructure>` — infrastructure role assumption.
- [ ] `dalmatian aws exec -i <infrastructure> sts get-caller-identity` — ARN is `…assumed-role/dalmatian-admin/dalmatian-tools` in the infrastructure account. (`aws exec` prepends `aws` itself; do not pass `aws` or `--`.)
- [ ] `dalmatian aws login` twice in a row — the second run reports the existing expiry and does nothing.
- [ ] `dalmatian login` — runs the brew/tfenv/session-manager setup and signs in with SSO, with no credential prompts.
- [ ] `dalmatian aws key-age` — refuses, explaining that SSO credentials are short-lived.
- [ ] `dalmatian aws mfa` — refuses, pointing at `dalmatian aws login`.
- [ ] `sso_off dalmatian config list-infrastructures` — the legacy path still authenticates, warns, and assumes the main-account role; `~/.config/dalmatian/dalmatian-sso.config` is restored afterwards.
- [ ] `dalmatian version -v 2 && dalmatian deploy list-accounts` — v2 unaffected. Then `dalmatian version -v 1`.
- [ ] `rm -f /tmp/verify-task*.sh /tmp/task4-* /tmp/task5-*` — none of the scratch verification scripts are committed.

## Follow-ups, explicitly out of scope

1. `dxw/dalmatian` repo: replace the GPG/TOTP block in `scripts/bin/{test,plan,deploy}` with `eval "$(dalmatian aws export-credentials)"`, rewrite `docs/aws-credential-profile-configuration-and-mfa.md`, and add ADR `0057-use-aws-sso-for-authentication.md` superseding 0054. Sequenced after this repo's change, which provides the command.

   Three things that work needs, found during this one:

   - **It is five copies, not three.** `scripts/bin/remove:146` and `scripts/bin/bootstrap-account:49` carry the same block as `test`, `plan` and `deploy`. Both specs undercount it.
   - **Decide the v2 route to `export-credentials`.** The command is v1-only. A colleague sitting on v2 now gets a clear "not available in v1/v2" error rather than exit 127, but the consuming scripts will still fail for them. `bin/aws/v1/export-credentials` would in fact work unchanged under v2 (`dalmatian_v1_sso_available` is true there, `AWS_CONFIG_FILE`/`AWS_PROFILE` are already set, and `--profile dalmatian-main` is explicit), so a `bin/aws/v2/export-credentials -> ../v1/export-credentials` symlink would close it for one file — deliberately not done here, because this change was constrained not to add v2 files.
   - **`export-credentials` runs `aws sso login` unconditionally**, which is wrong for the non-interactive and CI callers among those five scripts. A `--no-login` flag is the obvious answer; it was not built here because its consumer does not exist yet. Note `bin/util/v1/env` is prior art worth reading first — it already prints `export` lines and, because `bin/dalmatian` scans for `-i` itself, `dalmatian util env -i <infra>` yields infrastructure-account credentials, which `export-credentials` cannot. Two commands printing credentials to stdout under different contracts is a trap; consider retiring the overlap. (Its `getopts "irh"` optstring is also wrong — `i` takes no argument — so `-i` does not bind there.)
2. Comms to the team: engineers who have never run `dalmatian setup` stay on the deprecated path silently apart from the warning.
3. Removing the GPG/TOTP path, the IAM users and groups, and narrowing the role trust policies from `:root` to the SSO role ARN — each a separate change, and only once everyone has migrated.
4. `test.sh` masks the exit status of its `./bin` shellcheck pass and flags `bin/custom/v2/.gitkeep`. Worth fixing, but not here. Written up in `TODO.md`.
5. `bin/dalmatian` never initialises `INFRASTRUCTURE_NAME` before scanning the arguments for `-i`, so an ambient `INFRASTRUCTURE_NAME` in a user's shell silently makes commands run with no `-i` assume a role into that infrastructure's account. It happened twice during this work, once sending a verification run into a client's account. Deliberately deferred; written up in `TODO.md`.
6. **Qualify the specs' central premise about role trust.** Both specs state that because the `dalmatian-admin` trust policies name `arn:aws:iam::511700466171:root`, any sufficiently privileged principal in the main account can assume them — on the strength of three sampled accounts. That is not universally true. Probing eight infrastructures found `caselaw` and `caselaw-stg` deny `sts:AssumeRole` for `dalmatian-admin`, and they deny it for the legacy path's principal too (verified by assuming main-account `dalmatian-admin` first, then attempting the hop), so it is **not** a regression from dropping the main-account hop. The mechanism: both are registered as external, client-owned accounts — their tfvars are `100-E276505630421-…` and `100-E626206937213-…`, and that `E` prefix comes from `bin/aws/v2/account-init`'s `ACCOUNT_EXTERNAL` branch. External accounts are not provisioned by dxw's `account_bootstrap`; `account-init` emits a bespoke trust relationship for the client to apply themselves, so they sit outside the premise. Worth a sentence in the cross-repo spec, because the follow-on work runs Terraform against these accounts.
7. `bin/aws/v1/export-credentials` and a v1 subcommand see **different identities on the legacy path**: `bin/dalmatian` assumes main-account `dalmatian-admin` after getting the MFA session, `export-credentials` stops at the MFA session. This matches what the five consuming scripts in `dxw/dalmatian` actually do, so it is correct rather than a bug, and it is now documented in the script's `usage()` — but the cross-repo spec bills this as "a single credential-loading implementation", which glosses over it.

