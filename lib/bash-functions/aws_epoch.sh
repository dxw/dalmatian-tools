#!/bin/bash
set -e
set -o pipefail

# Returns the epoch in seconds from AWS NTP.
# This should be the most reliable current timestamp when comparing timestamps
# from AWS resources, rather than using the date/time from a local machine.
#
# @usage aws_epoch
function aws_epoch {
  AWS_NTP_SERVER="0.amazon.pool.ntp.org"

  NTP_STRING="$(sntp "$AWS_NTP_SERVER" | tail -n1)"
  AWS_DATE="$(echo "$NTP_STRING" | cut -d ' ' -f 1)"
  AWS_TIME="$(echo "$NTP_STRING" | cut -d ' ' -f 2 | cut -d '.' -f 1)"
  AWS_TZ="$(echo "$NTP_STRING" | cut -d ' ' -f 3)"

  AWS_EPOCH="$(gdate -d "$AWS_DATE $AWS_TIME $AWS_TZ" +%s)"
  echo "$AWS_EPOCH"
}
