#!/usr/bin/env python
# platform: host-agnostic
import errno
import hashlib
import json
import os
import re
import stat
import sys
sys.dont_write_bytecode = True
from provenance import tree

NAMES = ('wezterm-gui', 'wezterm', 'wezterm-mux-server')


def digest(path):
    result = hashlib.sha256()
    with open(path, 'rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def binary(path):
    mode = os.lstat(path).st_mode
    if not stat.S_ISREG(mode) or not mode & 0o111:
        raise ValueError('not a regular executable: ' + path)
    return {'sha256': digest(path), 'size': os.path.getsize(path), 'mode': stat.S_IMODE(mode)}


def build(work, repo):
    identity = open(os.path.join(work, 'source/.tag')).read().strip()
    if not re.match(r'^local-[0-9a-f]{40}$', identity):
        raise ValueError('invalid local build identity')
    directory = os.path.join(work, 'target/x86_64-apple-darwin/debug')
    return {'schema': 1, 'owner': repo, 'build_identity': identity, 'upstream_sha': identity[6:],
            'prepared_sha256': digest(os.path.join(work, 'prepared.json')),
            'binaries': dict((name, binary(os.path.join(directory, name))) for name in NAMES)}


def stage(work, repo, app):
    receipt = json.load(open(os.path.join(work, 'build.json')))
    if receipt != build(work, repo):
        raise ValueError('stale build receipt; rebuild current prepared inputs')
    for name in NAMES:
        if binary(os.path.join(app, 'Contents/MacOS', name)) != receipt['binaries'][name]:
            raise ValueError('staged executable does not match the build: ' + name)
    if open(os.path.join(app, '.mavergreen-owner')).read().strip() != repo:
        raise ValueError('foreign staged bundle')
    return {'schema': 1, 'owner': repo, 'build': receipt,
            'contents_sha256': tree(os.path.join(app, 'Contents'))}


def assert_gui_idle(work, repo):
    path = os.path.join(work, 'gui-active.json')
    if not os.path.exists(path):
        return
    session = json.load(open(path))
    if session.get('owner') != repo:
        raise ValueError('foreign GUI acceptance session')
    pid = session.get('pid')
    if isinstance(pid, bool) or not isinstance(pid, int) or pid <= 0:
        raise ValueError('invalid GUI acceptance PID')
    try:
        os.kill(pid, 0)
    except OSError as error:
        if error.errno == errno.ESRCH:
            return
        raise
    raise ValueError('GUI acceptance session is active; close its window before rebuilding or restaging')


def main():
    action, work, repo = sys.argv[1:4]
    if action == 'gui-idle':
        assert_gui_idle(work, repo)
        return
    if action.endswith('stage'):
        app = sys.argv[4]
        path = os.path.join(app, '.mavergreen-stage.json')
        data = stage(work, repo, app)
    else:
        path = os.path.join(work, 'build.json')
        data = build(work, repo)
    if action in ('record-build', 'record-stage'):
        with open(path + '.new', 'w') as target:
            json.dump(data, target, indent=2, sort_keys=True)
            target.write('\n')
        os.rename(path + '.new', path)
    elif action in ('verify-build', 'verify-stage'):
        if json.load(open(path)) != data:
            raise ValueError('modified or stale artifact receipt: ' + path)
    else:
        raise ValueError('unknown artifact action: ' + action)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, IOError, OSError, KeyError, IndexError) as error:
        sys.stderr.write('artifacts: %s\n' % error)
        sys.exit(1)
