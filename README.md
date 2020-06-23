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

## Usage

This repository contains a number of scripts, all with the `dalmatian-` prefix.
Run them with a `-h` flag to see their usage instructions.

- `dalmatian-mfa` to set up or renew multi-factor authentication for Dalmatian
