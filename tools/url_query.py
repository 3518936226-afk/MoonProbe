"""Real stdlib URL-form integration; no injected fault or schema verdict logic.

The consumer contract requires one decoded value, including an empty value.
The unconfigured parser uses its actual documented default. The configuration
fix is the normal keep_blank_values option, not a replacement parser.
"""
import argparse
import json
import sys
from urllib.parse import parse_qs, urlencode

parser = argparse.ArgumentParser()
parser.add_argument('--keep-blank-values', action='store_true')
options = parser.parse_args()
payload = json.load(sys.stdin)
query = urlencode(payload)
decoded = parse_qs(query, keep_blank_values=options.keep_blank_values)
json.dump({'values': decoded.get('value', [])}, sys.stdout, ensure_ascii=True, allow_nan=False)
sys.stdout.write('\n')
