#!/usr/bin/env python
# platform: host-agnostic
import json
import sys

try:
    data = json.load(open(sys.argv[1]))
    supplied = dict(item.split('=', 1) for item in sys.argv[3:])
    if data['commit'] != sys.argv[2] or data['gitlinks'] != supplied:
        raise ValueError('gitlink pins do not match the recorded parent tree')
except (ValueError, KeyError, IOError) as error:
    sys.stderr.write('gitlinks: %s\n' % error)
    sys.exit(1)
