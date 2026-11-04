#!/usr/bin/env python
# platform: host-agnostic
import hashlib
import json
import os
import stat
import sys


def tree(path):
    rows = []
    for root, dirs, files in os.walk(path):
        dirs.sort()
        files.sort()
        for name in sorted(dirs + files):
            full = os.path.join(root, name)
            relative = os.path.relpath(full, path)
            mode = os.lstat(full).st_mode
            if stat.S_ISLNK(mode):
                value = ['link', os.readlink(full)]
            elif stat.S_ISREG(mode):
                digest = hashlib.sha256()
                with open(full, 'rb') as stream:
                    while True:
                        chunk = stream.read(1024 * 1024)
                        if not chunk:
                            break
                        digest.update(chunk)
                value = ['file', stat.S_IMODE(mode), digest.hexdigest()]
            elif stat.S_ISDIR(mode):
                value = ['dir', stat.S_IMODE(mode)]
            else:
                raise ValueError('unsupported prepared entry: ' + full)
            rows.append([relative, value])
    return hashlib.sha256(json.dumps(rows, sort_keys=True).encode('utf-8')).hexdigest()


def refuse_strays(repo, name):
    for root, dirs, files in os.walk(os.path.join(repo, name)):
        for entry in sorted(dirs + files):
            stray = os.path.relpath(os.path.join(root, entry), repo)
            if entry == '__pycache__' or entry.endswith(('.pyc', '.pyo')):
                raise ValueError('Python bytecode in the recipe would change its digest; delete ' + stray)
            # platform: macOS keeps a file's extended attributes in a ._ AppleDouble file beside it on
            #           a share without native xattrs, such as this checkout's NFS mount
            if entry.startswith('._'):
                raise ValueError('AppleDouble metadata in the recipe would change its digest; delete ' + stray)


def recipe(repo):
    names = ('build', 'components', 'patches')
    for name in names:
        refuse_strays(repo, name)
    return dict((name, tree(os.path.join(repo, name))) for name in names)


def main():
    action, work, repo = sys.argv[1:]
    manifest = os.path.join(work, 'prepared.json')
    paths = ('source', 'crates')
    if action == 'record':
        data = {'owner': repo, 'recipe': recipe(repo),
                'trees': dict((p, tree(os.path.join(work, p))) for p in paths)}
        with open(os.path.join(repo, 'components/wezterm/version')) as source:
            data['pins'] = source.read()
        with open(os.path.join(work, 'source/Cargo.lock.upstream'), 'rb') as source:
            data['original_lock_sha256'] = hashlib.sha256(source.read()).hexdigest()
        with open(os.path.join(work, 'source/Cargo.lock'), 'rb') as source:
            data['prepared_lock_sha256'] = hashlib.sha256(source.read()).hexdigest()
        data['path_overrides'] = sorted(os.listdir(os.path.join(work, 'crates')))
        with open(manifest + '.new', 'w') as target:
            json.dump(data, target, indent=2, sort_keys=True)
            target.write('\n')
        os.rename(manifest + '.new', manifest)
        return
    data = json.load(open(manifest))
    if data['owner'] != repo:
        raise ValueError('foreign preparation owner')
    for path in paths:
        if data['trees'][path] != tree(os.path.join(work, path)):
            raise ValueError('modified prepared ' + path + '; preserve edits before rebuilding')
    if action == 'verify' and data['recipe'] != recipe(repo):
        raise ValueError('recipe changed; run prepare.sh to prepare the new inputs')
    if action not in ('verify', 'owned'):
        raise ValueError('unknown provenance action ' + action)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, IOError, KeyError, OSError) as error:
        sys.stderr.write('provenance: %s\n' % error)
        sys.exit(1)
