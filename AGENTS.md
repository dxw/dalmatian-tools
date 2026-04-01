# Dalmatian Tools Context for AI Agents

## Project Overview

Dalmatian Tools is a Command Line Interface (CLI) toolkit designed to facilitate operations with the "Dalmatian" infrastructure platform. It is primarily a collection of Bash scripts that wrap AWS CLI, Terraform, and other utilities to manage cloud resources. The tools are organized by service (e.g., `aws`, `rds`, `s3`) and version (e.g., `v1`, `v2`).

## Key Technologies & Dependencies

- **Language:** primarily Bash, with some Python and Ruby.
- **Core Dependencies:** `awscli`, `jq`, `oath-toolkit`, `terraform` (via `tfenv`), `gnupg`.
- **Package Manager:** Homebrew (`Brewfile` present).
- **Testing:** `shellcheck` for static analysis.

## Project Structure

- `bin/dalmatian`: The main entry point script. It handles argument parsing, authentication (MFA, Role Assumption), and dispatching to subcommands.
- `bin/<service>/<version>/<command>`: The actual executable scripts for specific tasks.
  - Example: `bin/rds/v1/list-instances`
- `lib/bash-functions/`: Reusable Bash functions sourced by the main script and subcommands.
- `bin/configure-commands/`: Scripts for configuration tasks (setup, update, login).
- `data/`: Data files, including templates and word lists.
- `support/`: Shell completion scripts (Bash/Zsh).
- `test.sh`: The test runner, currently running `shellcheck` on scripts.

## Usage & Workflow

- **Invocation:** `dalmatian <subcommand> <command> [args]`
- **Versions:** Commands are versioned (`v1`, `v2`).
  - **Switching Versions:**
    - Check current version: `dalmatian version`
    - Switch to v2: `dalmatian version -v 2`
    - Switch to v1: `dalmatian version -v 1`
  - **v1 (Legacy):** Uses IAM User credentials + MFA.
  - **v2 (Modern):** Uses AWS IAM Identity Center (SSO).
- **Authentication (v1):**
  - `dalmatian login`: Sets up AWS credentials and MFA.
  - Credentials stored in `~/.config/dalmatian/credentials.json.enc`.
  - Handles AWS MFA automatically using `oathtool`.
- **Authentication & Setup (v2):**
  - `dalmatian setup -f setup.json`: Initial setup using a project configuration file.
  - `dalmatian aws login`: Authenticates via AWS SSO.
  - Config stored in `~/.config/dalmatian/dalmatian-sso.config`.
- **Account Management (v2):**
  - `dalmatian aws account-init`: Onboard new AWS accounts (requires ID, region, name).
  - `dalmatian deploy account-bootstrap`: Apply baseline Terraform to accounts.

## Development & Contribution

- **Testing:** Run `./test.sh` to execute `shellcheck` across the codebase.
- **Adding Commands:** Create a new script in `bin/<service>/<version>/<command>` and ensure it is executable. New commands should generally be implemented for both `v1` and `v2` unless specific constraints apply.
- **Code Style:** Follow existing Bash patterns. Use `shellcheck` to ensure compliance.
  - Use `log_info -l "Message" -q "$QUIET_MODE"` for informational output, `log_msg -l "Message" -q "$QUIET_MODE"` for normal output, `warning "Message"` for warnings, and `err "Message"` for error messages (all from `lib/bash-functions/`). Avoid using direct `echo` for these purposes to maintain consistency and correctly support quiet mode.
- **Dependencies:** Manage via `Brewfile`.

## Key Commands

- `dalmatian -l`: List all available commands.
- **v1:**
  - `dalmatian login`: Authenticate (IAM User).
  - `dalmatian aws mfa`: Refresh MFA session.
- **v2:**
  - `dalmatian setup`: Join a project/setup config.
  - `dalmatian aws login`: Authenticate (SSO).
  - `dalmatian deploy list-accounts`: List managed accounts.
  - `dalmatian deploy account-bootstrap`: Reboot/Provision account infrastructure.

