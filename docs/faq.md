## FAQ

### Why am I seeing "oathtool: base32 decoding failed: Base32 string is invalid"

Probably you've entered your 6 digit MFA code rather than the underlying MFA
secret which is a long alphanumeric string. This secret is available:

- at the time you set up MFA in the AWS Console (Security Credentials | Manage MFA), and

- in 1Password if you're using that software to generate MFA codes. You need to
  go into 'edit' mode to view. You're looking for the string of letters and
  numbers after `?secret=`.

If you are using an 'app' such as Google Authenticator on your phone you may not
be able to access this initial secret without removing your MFA in the AWS
Console and setting it up afresh.
