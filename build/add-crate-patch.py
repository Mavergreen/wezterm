#!/usr/bin/env python
# platform: host-agnostic
import json
import re
import sys

try:
    path, name, crate_path = sys.argv[1:]
    if not re.match(r'^[A-Za-z0-9_-]+$', name):
        raise ValueError('invalid crate patch name')
    text = open(path).read()
    headers = list(re.finditer(r'^\[.*\]\s*$', text, re.M))
    sections = [m for m in headers if m.group().strip() == '[patch.crates-io]']
    if len(sections) > 1:
        raise ValueError('ambiguous crates.io patch section')
    if re.search(r'^\[patch\.crates-io\.' + re.escape(name) + r'\]', text, re.M):
        raise ValueError('crate patch already present: ' + name)
    if sections:
        start = sections[0].end()
        end = next((m.start() for m in headers if m.start() > start), len(text))
        if re.search(r'^' + re.escape(name) + r'\s*=', text[start:end], re.M):
            raise ValueError('crate patch already present: ' + name)
        text = text[:start] + '\n%s = { path = %s }\n' % (name, json.dumps(crate_path)) + text[start:]
    else:
        text += '\n[patch.crates-io]\n%s = { path = %s }\n' % (name, json.dumps(crate_path))
    with open(path, 'w') as target:
        target.write(text)
except (ValueError, IOError) as error:
    sys.stderr.write('crate patch: %s\n' % error)
    sys.exit(1)
