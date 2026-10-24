"""Interactive CLI credentials setup. Never prints key values or overwrites existing config."""
import getpass
import json
import os
from pathlib import Path

path = Path.home()/'.scp'/'cli-config.json'
if path.exists():
    raise SystemExit('Existing ~/.scp/cli-config.json found: inspect privately and reuse it; not overwritten.')
region = input('리전 [kr-west1]: ').strip() or 'kr-west1'
assert region, 'Region is required'
access = getpass.getpass('Access Key (hidden): ')
secret = getpass.getpass('Access Secret Key (hidden): ')
assert access and secret
path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as f:
    json.dump(dict(auth_url='https://iam.e.samsungsdscloud.com/v1/endpoints',
                   access_key=access, access_secret_key=secret, default_scp_region=region), f)
print('PASS: created private CLI configuration; key values not displayed')
