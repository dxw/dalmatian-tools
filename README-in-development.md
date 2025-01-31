# Dalmatian Tools

CLI tools to help with working with Dalmatian

## Prerequisites

- An AWS Organisation with at least 1 Account to configure with Dalmatian
- A user assigned to a group that has an Administrative permission set
- An S3 bucket to store the Terraform state
- AWS IAM Identity Center (successor to AWS Single Sign-On) configured with the
default identity source.

## Installation

1. Clone this repository locally

1. Install the dependencies

   ```
   ./bin/setup
   ```

1. Add the dalmatian-tools `bin` directory to your `$PATH`

   To add the ability to run the `dalmatian` command, you will need to add the
   Dalmatian Tools `bin` directory to your `$PATH` variable

   Find the full path of Dalmatian Tools by changing directory into this
   repository, and run `pwd`. eg:

   ```
   $ cd ~/git-clones/dalmatian-tools
   $ pwd
   /Users/alex/git-clones/dalmatian-tools
   ```

   Add this path, plus '/bin' to the '$PATH' variable, by modifying
   either the `~/.bashrc` or `~/.zshrc` file

   ```bash
   # ~/.bashrc or ~/.zshrc
   export PATH="$PATH:/<path-to-dalmatian-tools>/bin"
   ```

   The easiest way for this to take effect is to close and open your terminal application

   Or you can run `source ~/.bashrc` or `source ~/.zshrc` on all open terminals

1. Setup Dalmatian

   If you are joining a Dalmatian project that has already been setup, skip to
  the next step 'Joining a Dalmatian Project'

   Run the `dalmatian setup` command

1. Joining a Dalmatian Project

   To join a Dalmatian project, you must have an AWS Single Sign-On user which
  has Administrative access to at least the Main Dalmatian account.

   When the Dalmatian Project was first setup, it will have generated a setup
  file, stored at `~/.config/dalmatian/setup.json`.
   Ask a member of your team for this file, and then run:
   ```
   dalmatian setup -f setup.json
   ```

   This file may also be hosted via a web url, in which case you can run:
   ```
   dalmatian setup -h https://example.com/dalmatian-setup.json
   ```

   Using either of these options will provide defaults for the prompts, so you
   should be able to press Enter for all values.

## Usage

### Help

  `dalmatian -h`

  ```
  $ dalmatian -h
  Usage: dalmatian
    SUBCOMMAND COMMAND     - dalmatian command to run
    SUBCOMMAND COMMAND -h  - show command help
      Or:
    -h                     - help
    -l
  ```

### List commands

  `dalmatian -l`

### Shell completion
**Bash (/bin/bash)**

Add the full path to the `support/bash-completion.sh` script to your `~/.bashrc` file

eg:

```
# ~/.bashrc

source /path/to/dalmatian-tools/support/bash-completion.sh
```

**Zsh (/bin/zsh)**

Add the full path to the `support/zsh-completion.sh` script to your `~/.zshrc` file

eg:

```
# ~/.zshrc

autoload -Uz +X compinit && compinit
autoload -Uz +X bashcompinit && bashcompinit
source /path/to/dalmatian-tools/support/zsh-completion.sh
```

## Managing AWS accounts with Dalmatian

### Initialising AWS accounts

To manage AWS accounts with Dalmatian, we first need to initialise the account.
This account must be part of the AWS Organisation, and the user initialising it
must have Administrative access.

To initialise the account, you will need:
- The AWS account ID (eg. 123456789012)
- The desired default region name (eg. eu-west-2)
- A friendly human readable account name (eg. my-awesome-account - This does not
  need to be the same as the AWS account alias)

When ready, run:

```
dalmatian aws-sso account-init \
  -i <aws-account-id> \
  -r <region> \
  -n <account-name>
```

### Listing Dalmatian accounts

Once an AWS account has been initialised, it will appear within the list of
available accounts that can be deployed to.

You can list the accounts by running:

```
dalmatian deploy list-accounts
```

This command will show each account with it's full account name, which is the
format that is to be used when a command asks for the account name:

```
<aws_account_id>-<aws_region>-<account_name>
```

### Re-bootstrapping AWS accounts

For the most part, Dalmatian will run the bootstrap process as and when needed
whilst running Dalmatian commands.

There may be times when the AWS accounts need to be rebootstrapped, for example
if the Terraform code has been updated to add extra features.

To do this, run:

```
dalmatian deploy account-bootstrap
```

This will cycle through all the accounts initialised with dalmatian.

If you wish to only bootstrap a specific account, you can run:

```
dalmatian deploy account-bootstrap -a <dalmatian-account>
```

Full usage:

```
Usage: account-bootstrap [OPTIONS]
  -h                     - help
  -a <dalmatian-account> - AWS Account ID (Optional - By default all accounts will be cycled through)
  -p <plan>              - Run terraform plan rather than apply
  -N                     - Non-interactive mode (auto-approves terraform apply)
```
