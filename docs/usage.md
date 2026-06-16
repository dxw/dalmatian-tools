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

Switching to Dalmatian version 2

```
$ dalmatian version -v 2
==> Dalmatian Tools v2
==> (Release: v0.47.0-1-g030974d)
==> The tooling available in v2 is to be used with infrastructures
==> deployed via dalmatian-tools
==> To use tooling for use with infrastructures launched with the dxw/dalmatian repo,
==> switch to 'v1' by running 'dalmatian version -v 1'
```

Switching back to Dalmatian version 1

```
$ dalmatian version -v 1
==> Dalmatian Tools v1
==> The tooling available in v1 is to be used with infrastructure
==> launched with the dxw/dalmatian repo, which is private and internal
==> To use tooling for use with infrastructures deployed via dalmatian-tools,
==> switch to 'v2' by running 'dalmatian version -v 2'
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

#### `dalmatian util generate-four-words`

This helpful command can be used to generate passphrases that can be used for limited purposes such as Basic HTTP authentication gates.

> [!Important]
> This command is not a substitute for good password hygiene. Always follow dxw's official password policy.

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

### `dalmatian config`

This collection of tools are useful for collating facts from the compiled `dalmatian-config.yml`.

>[!NOTE]
>Each of these scripts will first attempt to refresh your `dalmatian-config.yml` file if it is considered outdated.

#### `dalmatian config list-services-by-buildspec`

Output a space-separated list of infrastructures and services based on the supplied buildspec definition.

```
$ dalmatian config list-services-by-buildspec \
  -b "my_special_buildspec"

core-infra-1 web
core-infra-2 intranet
infrastructure-2 service-1
infrastructure-2 service-2
infrastructure-2 service-3
infrastructure-2 service-4
[..]
```

You can restrict the output to one specific infrastructure by including that as an additional option

```
$ dalmatian config list-services-by-buildspec \
  -b "my_special_buildspec" \
  -i "infrastructure-2"

infrastructure-2 service-1
infrastructure-2 service-2
infrastructure-2 service-3
infrastructure-2 service-4
[..]
```

#### `dalmatian config list-services`

Output a list of infrastructures and their associated services. This is essentially the same as `list-services-by-buildspec` but without the need to specify a buildspec.

```
$ dalmatian config list-services

core-infra-1: web
core-infra-2: intranet
core-infra-2: editor
core-infra-2: proxy
infrastructure-2: service-1
infrastructure-2: service-2
infrastructure-2: service-3
infrastructure-2: service-4
[..]
```

You can restrict the output to one specific infrastructure by appending it to the end of the command.

```
$ dalmatian config list-services "core-infra-2"

core-infra-2: intranet
core-infra-2: editor
core-infra-2: proxy
```

#### `dalmatian config list-environments`

Output a list of infrastructures and their associated environment names.

```
$ dalmatian config list-environments

core-infra-1: prod
core-infra-2: prod
core-infra-2: staging
infrastructure-2: prod
infrastructure-2: staging
infrastructure-2: qa
[..]
```

You can restrict the output to one specific infrastructure by appending it to the end of the command.

```
$ dalmatian config list-environments "core-infra-2"

core-infra-2: prod
core-infra-2: staging
```

#### `dalmatian config list-infrastructures`

Output a list of infrastructures. This command takes no additional options.

```
$ dalmatian config list-infrastructures
core-infra-1
core-infra-2
infrastructure-2
```

## `dalmatian ci`

This collection of tools allows you to view or monitor AWS Code Pipeline, or build logs from AWS Code Build for a specific service.

### `dalmatian ci deploy-status`

Monitoring the deployment status of the Terraform AWS Code Pipeline allows you to see build progress across each service at the same time.

```
$ dalmatian ci deploy-status
Source: Succeeded (2024-11-25T14:30:12.336000+00:00)
Build: Cancelled ()
  - Build-service-1:  ()
  - Build-service-2: Succeeded (2023-08-02T13:43:36.898000+01:00)
  - Build-service-3: Failed (2023-08-02T13:44:11.435000+01:00)
```

You can append the option `-w` to `watch` the output of this command, and re-check every 5 seconds.

### `dalmatian ci deploy-build-logs`

This command will query a particular AWS Code Build for a specified infrastructure and output the state of execution. If the build was unsuccessful, it will attempt to query for the last few logs and output them.

>[!Warning]
>Currently the automated Dalmatian pipeline is halted. This means any Terraform deployments are applied manually.
>As a result, enough time has now passed that any available logs for historic pipeline-based deployments are no longer available.
>
>**This command will fail to return any discernable output.**

```
$ dalmatian ci deploy-build-logs -I "$infrastructure"
[..]
```

## `dalmatian cloudfront`

### `dalmatian cloudfront clear-cache`

AWS CloudFront is a CDN that sits in front of web based services. It supports asset caching and sometimes you may find it useful to be able to clear that cache.

As this command targets a specific service environment you will need to supply the infrastructure name, the service name, and the environment name as options.

```
$ dalmatian cloudfront clear-cache \
  -i "$infrastructure" \
  -s "$service" \
  -e "$environment"
[..]
==> Finding CloudFront distribution...
==> Running invalidation on distribution EEEEEEEEEEEE ( eeeeeeeeeee.cloudfront.net ) ...
Invalidation InProgress ...
[..]
Invalidation Completed ...
```

Perhaps a feature release has just been deployed and you want to flush cache for a specific route. Add the `-P` option to the end of your command, with the expected path you want to clear cache for.

```
$ dalmatian cloudfront clear-cache \
  -i "$infrastructure" \
  -s "$service" \
  -e "$environment" \
  -P "/my-route/to-clear"
[..]
==> Finding CloudFront distribution...
==> Running invalidation on distribution EEEEEEEEEEEE ( eeeeeeeeeee.cloudfront.net ) ...
Invalidation InProgress ...
[..]
Invalidation Completed ...
```

### `dalmatian cloudfront generate-basic-auth-password-hash`

This command can be used for generating cryptographic hashes from a user-supplied input.

It will exectute a python script which will prompt you for a password to supply into the hash function.

The resulting value is generated using [pbkdf2-hmac-hash.py](../lib/pbkdf2-hmac-hash.py).

```
$ dalmatian cloudfront generate-basic-auth-password-hash
New basic auth password:
2304d0b1aaa51b5986affee30a893a8008baf7bbb9d0b7811218585323f676f0257b00584fbf41b569efdaf1fd481e057599cc73f588653572954eda34784761b18bc9762ebe5c3737c37472a545e5c06d88b324a238e5070b6322718952a503
```

### `dalmatian cloudfront logs`

You may find it useful to be able to read logs for a particular Cloudfront distribution. These logs are typically HTTP request/access logs and can aid in troubleshooting. There is limited pattern-based filtering available to help restrict the output to a given day, or output that matches a particular string e.g. `2025-02-01`.

As this command targets a specific service cloudfront you will need to supply the infrastructure name, the service name, and the environment name as options.

```
$ dalmatian cloudfront logs \
  -i "$infrastructure" \
  -s "$service" \
  -e "$environment"
[..]
==> downloading log files
download: s3://$infrastructure-$service-$environment-cloudfront-logs/EEEEEEEEEEEE.2025-01-14-13.343e95e3.gz to ../../../../tmp/$infrastructure-$service-$environment-cloudfront-logs/EEEEEEEEEEEE.2025-01-14-13.343e95e3.gz
[..]
==> logs in /tmp/$infrastructure-$service-$environment-cloudfront-logs
```

By default the logs will be downloaded to the path:

```
$DALMATIAN_TOOLS_ROOT/tmp/$infrastructure-$service-$environment-cloudfront-logs
```

If you want to override where the log files are downloaded to, pass a path to the command with `-d "/my/path/"`

You can optionally restrict the number of log files that are downloaded based on a filename filter.

Add the `-p` option and specify a date or datetime pattern in the format `YYYY-MM-DD` or `YYYY-MM-DD-HH-MM`

## `dalmatian aurora`

This collection of tools can be used for manipulating AWS Aurora instances for a particular infrastructure.

### `dalmatian aurora count-sql-backups`

>[!NOTE]
>This command is an alias of `dalmatian rds count-sql-backups`
>
>See [#dalmatian-rds-count-sql-backups](#dalmatian-rds-count-sql-backups) for usage examples.

### `dalmatian aurora shell`

>[!NOTE]
>This command's usage is identical to `dalmatian rds shell`, but has specific logic for connecting to Aurora instances.
>
>See [#dalmatian-rds-shell](#dalmatian-rds-shell) for usage examples.

### `dalmatian aurora list-instances`

>[!NOTE]
>This command's usage is identical to `dalmatian rds list-instances`, but has specific logic for connecting to Aurora instances.
>
>See [#dalmatian-rds-list-instances](#dalmatian-rds-list-instances) for usage examples.

### `dalmatian aurora export-dump`
### `dalmatian aurora list-databases`
### `dalmatian aurora start-sql-backup-to-s3`
### `dalmatian aurora download-sql-backup`
### `dalmatian aurora set-root-password`
### `dalmatian aurora get-root-password`
### `dalmatian aurora import-dump`
### `dalmatian aurora create-database`

## `dalmatian rds`

This collection of tools can be used for manipulating RDS instances for a particular infrastructure.

### `dalmatian rds count-sql-backups`

Uses the S3 API to query the number of backups for a particular RDS instance. You have to supply the infrastructure, the name of the RDS instance (as defined in `dalmatian-config.yml`) and the environment as options.

```
$ dalmatian rds count-sql-backups \
  -i "$infrastructure" \
  -r "$rds_name" \
  -e "$environment"
14
```

You can optionally filter the results by Last Modified date. Append the command with `-d` and a date value in format "YYYY-MM-DD"

### `dalmatian rds shell`

Start a MySQL shell on a particular RDS instance as the database Administrator user. This command will bridge to an RDS instance by connecting to an EC2 host using AWS Session Manager.

You will need to specify the infrastructure, the name of the RDS, and the environment as a minimum.

>[!CAUTION]
>This is a potentially **dangerous** action! Please be mindful of connecting to production databases.
>
>It is better to be safe than sorry. [Start a SQL backup](#dalmatian-rds-start-sql-backup-to-s3) if you are going to be performing manual MySQL transactions.
>
>Use this command sparingly and tread carefully.

```
$ dalmatian rds shell \
  -i "$infrastructure" \
  -r "$rds_name" \
  -e "$environment"
[..]
==> Retrieving RDS root password from Parameter Store...
==> Getting RDS info...
Engine: rds-mysql
Root username: my-root-user
ECS instance ID: i-xxxxxxxxxx
==> Starting rds-mysql session on my-rds-cluster...

Starting session with SessionId: dalmatian-tools-xxxxxxxxxxxxxxxx
mysql: [Warning] Using a password on the command line interface can be insecure.
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 64035316
Server version: 8.0.32 Source distribution

Copyright (c) 2000, 2025, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql>
```

If you want to connect to the RDS shell through a specific EC2 instance you can add `-l` to the command which will simply list all available EC2 instance IDs.

```
$ dalmatian rds shell \
  -i "$infrastructure" \
  -r "$rds_name" \
  -e "$environment" \
  -l
[..]
==> Finding ECS instances...
i-aaaaaaaaaaaaaaaaa | EC2 Node | 2025-02-12T07:21:10+00:00
i-bbbbbbbbbbbbbbbbb | EC2 Node | 2025-02-12T12:09:07+00:00
i-ccccccccccccccccc | EC2 Node | 2025-02-13T14:51:34+00:00
i-ddddddddddddddddd | EC2 Node | 2025-02-13T23:41:57+00:00
[..]
```

You can then grab the ID from the first column of output and add that into your initial command to connect directly through that EC2 instance.

```
$ dalmatian rds shell \
  -i "$infrastructure" \
  -r "$rds_name" \
  -e "$environment" \
  -I "i-ddddddddddddddddd"
[..]
```

### `dalmatian rds list-instances`

Output a list of names, engines, and endpoint addresses for all RDS instances in a given infrastructure and environment.

```
$ dalmatian rds list-instances \
  -i "$infrastructure" \
  -e "$environment"
[..]
==> Getting RDS instances in $infrastructure $environment...
Name: my-rds-1 Engine: mysql Address: my-rds-1.aaabbbcccddd.eu-west-2.rds.amazonaws.com:3306
Name: my-rds-2 Engine: mysql Address: my-rds-2.aaabbbcccddd.eu-west-2.rds.amazonaws.com:3306
[..]
```

### `dalmatian rds export-dump`

This command will connect to a target RDS instance via an EC2 Instance, perform a `mysqldump` to generate a backup `.sql` file of your target database, which is moved into an S3 "db_exports" bucket, then it is downloaded to your local machine.

```
$ dalmatian aurora export-dump \
  -i "$infrastructure" \
  -e "$environment" \
  -r "$rds_name" \
  -d "$database_name"
[..]
==> Retrieving RDS root password from Parameter Store...
==> Getting RDS info...
Engine: rds-mysql
Root username: root
ECS instance ID: i-aaaaaaaaaaaaaaaaa
Exporting "$database_name" db from my-rds-1...

Starting session with SessionId: dalmatian-tools-xxxxxxxxxxxxxxxx
[..]
Exiting session with sessionId: dalmatian-tools-xxxxxxxxxxxxxxxx.

==> Export complete
==> Starting download of $database_name-$environment-sql-export.sql from s3 bucket xxx...
download: s3://xxx/db_exports/$database_name-$environment-sql-export.sql to ./$database_name-$environment-sql-export.sql
==> Deleting sql file from S3 ...
delete: s3://xxx/db_exports/$database_name-$environment-sql-export.sql
```

You can optionally change the output path of where the SQL file is downloaded to by appending `-o "$path"` with a valid local path e.g. `-o "~/Downloads/".

If you want to select a specific EC2 Instance to execute this backup from, specify the instance id with `-I "$instance_id"`

### `dalmatian rds list-databases`
### `dalmatian rds start-sql-backup-to-s3`
### `dalmatian rds download-sql-backup`
### `dalmatian rds set-root-password`
### `dalmatian rds get-root-password`
### `dalmatian rds import-dump`
### `dalmatian rds create-database`
