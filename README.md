# Dalmatian Tools

CLI tools to help with working with Dalmatian

## Installation

1. Clone this repository locally

1. Install the dependencies

   ```
   brew bundle install
   ```

1. Symlink the scripts to somewhere on your path

   Our recommendation is to add the repository's `bin` directory to your path:

   ```bash
   # ~/.bashrc or ~/.zshrc
   export PATH="$PATH:/absolute/path/to/bin"
   ```

1. Set up AWS credentials

   Create a `~/.aws/config/ file which looks like

   ```
   [default]
   region = eu-west-2
   [profile dalmatian-admin]
   region=eu-west-2
   cli_follow_urlparam=false
   role_arn = arn:aws:iam::[REDACTED AWS ACCOUNT NUMBER]:role/dalmatian-admin
   source_profile = mfa
   ```

   the AWS Account number is the core dalmatian AWS account.

   and create a `~/.aws/credentials` file that looks like

   ```
   [default]
   aws_access_key_id = [REDACTED AWS ACCESS KEY]
   aws_secret_access_key = [REDACTED AWS SECRET ACCESS KEY]
   ```

## Usage

This repository contains a number of scripts, all with the `dalmatian-` prefix.
Run them with a `-h` flag to see their usage instructions.

- `dalmatian-mfa` to set up or renew multi-factor authentication for Dalmatian
