#!/usr/bin/env python
# platform: host-agnostic
import json
import re
import sys


def packages(path):
    text = open(path).read()
    blocks = re.split(r'^\[\[package\]\]\s*$', text, flags=re.M)[1:]
    if not blocks:
        raise ValueError('no package records in ' + path)
    result = {}
    for block in blocks:
        record = {}
        for key in ('name', 'version', 'source', 'checksum'):
            values = re.findall(r'^' + key + r' = (.+)$', block, re.M)
            if len(values) > 1:
                raise ValueError('ambiguous field ' + key)
            if values:
                record[key] = json.loads(values[0])
        if not record.get('name') or not record.get('version'):
            raise ValueError('missing package identity')
        identity = (record['name'], record['version'])
        if identity in result:
            raise ValueError('ambiguous package ' + '/'.join(identity))
        result[identity] = record
    return result


def locked_crate(name, path):
    matches = [p for p in packages(path).values() if p['name'] == name]
    if len(matches) != 1:
        raise ValueError(('missing' if not matches else 'ambiguous') + ' crate ' + name)
    item = matches[0]
    if item.get('source') != 'registry+https://github.com/rust-lang/crates.io-index':
        raise ValueError('not a crates.io registry package: ' + name)
    checksum = item.get('checksum', '')
    if not re.match(r'^[0-9a-f]{64}$', checksum):
        raise ValueError('missing or invalid checksum: ' + name)
    version = item['version']
    if not re.match(r'^[A-Za-z0-9_.+-]+$', name) or not re.match(r'^[A-Za-z0-9_.+-]+$', version):
        raise ValueError('invalid crate identity')
    print('%s %s https://static.crates.io/crates/%s/%s-%s.crate' %
          (version, checksum, name, name, version))


def compare(before, after, allowed):
    old = packages(before)
    new = packages(after)
    if set(old) != set(new):
        raise ValueError('package versions changed: ' + repr(sorted(set(old) ^ set(new))))
    for identity in old:
        if old[identity] == new[identity]:
            continue
        replacement = dict(old[identity])
        replacement.pop('source', None)
        replacement.pop('checksum', None)
        if identity[0] not in allowed or new[identity] != replacement:
            raise ValueError('unexpected package source/checksum change: ' + identity[0])
    print('locked package versions and checksums preserved (%d packages)' % len(old))


def main():
    if len(sys.argv) == 4 and sys.argv[1] == '--crate':
        locked_crate(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 3:
        compare(sys.argv[1], sys.argv[2], sys.argv[3:])
    else:
        raise ValueError('usage: check-lock.py BEFORE AFTER [ALLOWED-PATH-CRATE...] | --crate NAME LOCK')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, IOError, KeyError) as error:
        sys.stderr.write('lock: %s\n' % error)
        sys.exit(1)
