#!/usr/bin/env python3
"""Semneaza un fisier JSON de configurare si produce custom.txt.
Utilizare: python3 sign_custom.py <secret.b64> <config.json> <custom.txt>"""
import sys, json, base64
import nacl.signing
sec = base64.b64decode(open(sys.argv[1]).read().strip())
sk = nacl.signing.SigningKey(sec[:32])
cfg = json.dumps(json.load(open(sys.argv[2])), separators=(',', ':')).encode()
open(sys.argv[3], 'w').write(base64.b64encode(sk.sign(cfg)).decode())
print('ok', sys.argv[3])
