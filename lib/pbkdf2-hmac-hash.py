#!/usr/bin/env python3
import hashlib
import sys
import os
import binascii

passwd = sys.argv[1]
salt = hashlib.sha256(os.urandom(60)).hexdigest().encode('ascii')
hashed = hashlib.pbkdf2_hmac('sha512', passwd.encode('utf-8'), salt, 2048)
hashed = binascii.hexlify(hashed)
hashed = (salt + hashed).decode('ascii')

print(hashed)
