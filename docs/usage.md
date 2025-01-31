## Usage

>[!IMPORTANT]
>Please note the following documentation is for version 1 of Dalmatian Tools. Version 2 usage documentation is still in early draft

>[!TIP]
>1. List all available commands at any time with `dalmatian -l`
>1. Most commands include a 'help' option. Add `-h` to your command to see what available options it expects

### `dalmatian login`

The **login** command is used to authenticate Dalmatian Tools with AWS using Single Sign-On.

As dalmatian requires that a number of packages are installed to your system in order to function effectively, the login command will check these exist and install any missing dependencies on your behalf before proceeding.

Logging into Dalmatian Tools is an essential first step in getting setup.

If you haven't already, please read the [installation guide](./installation.md).

### `dalmatian version`

The **version** command allows you to switch operation modes between version 1 (legacy) and version 2.

To switch versions, simply adjust the number value for the `-v` option.

```
# Switching to Dalmatian version 2
$ dalmatian version -v 2
# Switching back to Dalmatian version 1
$ dalmatian version -v 1
```

To see what version you are currently using you can simply run
```
$ dalmatian version
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

arn:aws:acm:eu-west-2:xxx:certificate/aaa-aaa-bbb-bbb-bbb my-example-domain.org EXPIRED
_c33dc71b006c460ed5ef53b6dcf57040.my-example-domain.org. CNAME _7330c60e670977e371567a560c6c1c05.aaa.acm-validations.aws.
_4416a7c8eb42f12439788a305cfcd8a5.www.my-example-domain.org. CNAME _86d26d74a9ad4a4d4571f1ed611c2b26.bbb.acm-validations.aws.
```

#### `dalmatian certificate delete`

This command will allow an operator to delete specific certificates from AWS Certificate Manager in a particular infrastructure.

You can delete certificates that match either a specific ARN, or you can specify a domain name. By specifying a domain name you can delete all certificates that are not in either `PENDING` or `ISSUED` state.

If you are wanting to use an ARN, you may find it useful to first run `dalmatian certificate list` to find the ARN you need.

>[!CAUTION]
>This is a **destructive** action! You can add `-d` to this command to perform a dry-run and instead will print the commands it _would have_ executed to the output.

To delete a certificate using an ARN

```
$ dalmatian certificate delete \
  -i "$infrastructure" \
  -c "arn:aws:acm:eu-west-2:xxx:certificate/aaa-aaa-aaa-aaa-aaa"
```

To delete all certificate for a domain name that are not `PENDING` or `ISSUED`

```
$ dalmatian certificate delete \
  -i "$infrastructure" \
  -D "my-example-domain.org"
```

#### `dalmatian certificate create`

This command allows an operator to create a new certificate within AWS Certificate Manager for a particular infrastrcture. This certificate can be used by CloudFront and ALBs.

Create a simple certificate for a specific domain

```
$ dalmatian certificate create \
  -i "$infrastructure" \
  -d "my-domain-name.org"
```

Add additional Subject Alternative Names (SANs) to the certificate by specifing space separated domain names to the command.

```
$ dalmatian certificate create \
  -i "$infrastructure" \
  -d "my-domain-name.org" \
  -s "staging.my-domain-name.org parked.my-domain-name.org"
```

After creating the certificate in AWS, you will be provided with 2 ARNs, one for the Load Balancer (ALB) and one for CloudFront.

Additionally, you will be shown the DNS Records you need to set in order to validate your domain ownership and have the certificate transition from  `PENDING_VALIDATION` to `ISSUED`.

### `dalmatian util`

This collection of tools are generic and can be considered helpful for an operator to use during debugging, troubleshooting or investigative work.

#### `dalmatian util list-security-group-rules`

Run this command to list all open ports across all security groups in a particular AWS Account.

The output will include the **rule name**, the **port range**, and the **IP or security group** associated with the rule.

By default, this command will query the main `dalmatian` account

```
$ dalmatian util list-security-group-rules
==> Open Ports in the account
my-rule-name-1,80-80,0.0.0.0/0
my-rule-name-2,443-433,sg-xxxxxx
my-rule-name-3,0-65535,127.0.0.1/32
```

You can further restrict the query by including an infrastructure as an option
```
$ dalmatian util list-security-group-rules \
  -i "$infrastructure"
==> Open Ports in the account
my-rule-name-2,443-433,sg-xxxxxx
```

#### `dalmatian util ip-port-exposed`

This command will query all security groups within an infrastructure and list out rules where there is unrestricted inbound access for any ports that are not `443` (HTTPS) or `80` (HTTP)

```
$ dalmatian util ip-port-exposed \
  -i "$infrastructure"
Searching ...
sg-aaaaaa162c8bf0303 my-security-group 3306 3306 0.0.0.0/0
Exposed port found!
Finished!
```

#### `dalmatian util generate-four-words`

This helpful command can be used to generate passphrases that can be used for limited purposes such as Basic HTTP authentication gates.

>[!Important]
>This command is not a substitute for good password hygiene. Always follow dxw's official password policy.

Generate a password that is suitable for use in basic auth

```
$ dalmatian util generate-four-words
Please note that the phrases generated here should not be used as login
passwords or to hide secrets. Please use 1Password in those cicumstances.
If you have any questions, please ask the Technical Operations team for advice.

width-males-minded-random
```

To suppress the warning, add `-q` to the command

```
$ dalmatian util generate-four-words -q
away-naught-wagner-mimic
```

#### `dalmatian util env`

Print the shell environment variables for a specific infrastructure. You should not expect to need to use this command for anything other than debugging a significant issue with Dalmatian.

This command is intended for administrators or powerusers.

>[!CAUTION]
>This is a **sensitive** action! It will reveal sensitive data, including AWS Access Keys and AWS Session Tokens.
>
>**Do not share this information!**

Query the default shell variables for any `export` lines that include `AWS`

```
$ dalmatian util env
export AWS_SESSION_TOKEN=[redacted]
export AWS_DEFAULT_REGION=[redacted]
export AWS_SECRET_ACCESS_KEY=[redacted]
export AWS_ACCESS_KEY_ID=[redacted]
export AWS_CALLER_IDENTITY_USERNAME=[redacted]
export BASH_FUNC_aws_epoch%%=() {  AWS_NTP_SERVER="time.aws.com";
export NTP_STRING="$(sntp "$AWS_NTP_SERVER" | tail -n1)";
export AWS_DATE="$(echo "$NTP_STRING" | cut -d ' ' -f 1)";
export AWS_TIME="$(echo "$NTP_STRING" | cut -d ' ' -f 2 | cut -d '.' -f 1)";
export AWS_TZ="$(echo "$NTP_STRING" | cut -d ' ' -f 3)";
export AWS_EPOCH="$(gdate -d "$AWS_DATE $AWS_TIME $AWS_TZ" +%s)";
...
```

You can set the target infrastructure name with `-i` which may adjust the values of some of the data.

#### `dalmatian util exec`

This command allows an operator to execute a cli command in an infrastructure. It can be useful for bootstrapping new accounts, getting AWS env vars, or running generic scripts against a remote infrastructure.

This command is intended for administrators or powerusers.

Get a list of IAM users within the default dalmatian AWS account

```
$ dalmatian util exec aws iam list-users | jq '.Users.[].UserName'
user-1
user-2
user-3
user-4
user-5
```

Adding the `-i` option allows you to adjust the scope of your command to a specific infrastructure.

Get information for the region opt-in status of a specific infrastructure

```
$ dalmatian util exec -i "$infrastructure" aws account list-regions | less
==> Assuming role to provide access to infrastructure account ...
{
  "Regions": [
    {
      "RegionName": "af-south-1",
      "RegionOptStatus": "DISABLED"
    },
    {
      "RegionName": "ap-east-1",
      "RegionOptStatus": "DISABLED"
    },
    {
      "RegionName": "ap-northeast-1",
      "RegionOptStatus": "ENABLED_BY_DEFAULT"
    },
    {
      "RegionName": "ap-northeast-2",
      "RegionOptStatus": "ENABLED_BY_DEFAULT"
    },
    [..]
```
