#!/usr/bin/env python
# platform: host-agnostic
# spec: PORT.md "Upstream's own tests" -- cargo builds upstream's test binaries and, through this
#       script as its runner, records how it would run each one (working directory and the variables
#       cargo sets) instead of running it. pack copies the target's binaries beside a manifest whose
#       paths are relative to it. The binaries then run from that record, one libtest process per
#       binary, with named exclusions, here and on a machine without cargo.
"""usage: upstream-tests.py capture EXECUTABLE [ARG...]      (as cargo's runner)
       upstream-tests.py manifest SET MESSAGES CAPTURE_DIR >> MANIFEST
       upstream-tests.py pack MANIFEST DIR
       upstream-tests.py run MANIFEST EXCLUSIONS LOGDIR [--ssh-probe KEY]"""
from __future__ import print_function
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import time
sys.dont_write_bytecode = True

RESULT = re.compile(r'^test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored;', re.M)
CARGO_EXACT = ('CARGO', 'CARGO_CRATE_NAME', 'CARGO_BIN_NAME', 'CARGO_PRIMARY_PACKAGE',
               'CARGO_TARGET_TMPDIR', 'OUT_DIR', 'DYLD_FALLBACK_LIBRARY_PATH', 'DYLD_LIBRARY_PATH')
CARGO_PREFIXES = ('CARGO_PKG_', 'CARGO_MANIFEST_', 'CARGO_BIN_EXE_')
TARGET = 'x86_64-apple-darwin'


def die(message):
    sys.stderr.write('upstream-tests: %s\n' % message)
    sys.exit(2)


def capture(argv):
    directory = os.environ.get('UPSTREAM_TESTS_CAPTURE')
    if not directory:
        die('capture needs UPSTREAM_TESTS_CAPTURE')
    exe = os.path.realpath(argv[0])
    env = dict((k, v) for k, v in os.environ.items()
               if k in CARGO_EXACT or k.startswith(CARGO_PREFIXES))
    record = {'exe': exe, 'args': argv[1:], 'cwd': os.getcwd(), 'env': env}
    with open(os.path.join(directory, os.path.basename(exe) + '.json'), 'w') as out:
        json.dump(record, out, sort_keys=True)
    return 0


def package_name(package_id):
    # platform: cargo's package ids are "path+file:///dir#name@1.0", "path+file:///name#1.0" or
    #           "registry+...#name@1.0"; the name is the last path component when the fragment has none.
    location, _, fragment = package_id.partition('#')
    if '@' in fragment:
        return fragment.split('@', 1)[0]
    return location.rstrip('/').split('/')[-1]


def manifest(test_set, messages, capture_dir):
    captured = {}
    for name in os.listdir(capture_dir):
        record = json.load(open(os.path.join(capture_dir, name)))
        captured[record['exe']] = record
    keys = set()
    for line in open(messages):
        if not line.startswith('{'):
            continue
        message = json.loads(line)
        if message.get('reason') != 'compiler-artifact' or not message['profile'].get('test'):
            continue
        if not message.get('executable'):
            continue
        exe = os.path.realpath(message['executable'])
        target = message['target']
        key = '%s/%s/%s' % (package_name(message['package_id']), target['kind'][0], target['name'])
        if key in keys:
            die('two test binaries for %s in set %s' % (key, test_set))
        keys.add(key)
        record = captured.pop(exe, None)
        if record is None:
            die('cargo built %s (%s) but never ran it' % (key, exe))
        if record['args']:
            die('cargo ran %s with arguments %r' % (key, record['args']))
        print(json.dumps({'set': test_set, 'key': key, 'exe': exe, 'cwd': record['cwd'],
                          'env': record['env']}, sort_keys=True))
    if captured:
        die('cargo ran binaries it did not report: %s' % ' '.join(sorted(captured)))
    if not keys:
        die('no test binaries in %s' % messages)
    return 0


def pack(manifest_path, directory):
    if os.path.exists(directory) or os.path.islink(directory):
        die('%s already exists' % directory)
    rows = [json.loads(line) for line in open(manifest_path) if line.strip()]
    kept, names = [], {}
    for row in rows:
        if TARGET not in row['exe'].split(os.sep):
            # platform: a proc macro's test binary is host code, which loads the toolchain's libstd
            #           and has no tests
            sys.stderr.write('upstream-tests: %s is a host test binary, left out of the pack (%s)\n'
                             % (row['key'], row['exe']))
            continue
        name = os.path.basename(row['exe'])
        if name in names:
            die('two test binaries named %s: %s and %s' % (name, names[name], row['key']))
        names[name] = row['key']
        kept.append(row)
    if not kept:
        die('no target test binaries in %s' % manifest_path)
    staging = directory + '.partial'
    if os.path.exists(staging):
        shutil.rmtree(staging)
    os.makedirs(os.path.join(staging, 'bin'))
    os.mkdir(os.path.join(staging, 'work'))
    with open(os.path.join(staging, 'manifest.jsonl'), 'w') as out:
        for row in kept:
            name = os.path.basename(row['exe'])
            shutil.copy2(row['exe'], os.path.join(staging, 'bin', name))
            # spec: PORT.md "Upstream's own tests" -- the build host's paths do not exist where
            #       the pack runs, and its toolchain's library paths are not wanted there
            env = dict((k, '/nonexistent' + v if v.startswith('/') else v)
                       for k, v in row['env'].items() if not k.startswith('DYLD_'))
            out.write(json.dumps({'set': row['set'], 'key': row['key'], 'exe': 'bin/' + name,
                                  'cwd': 'work', 'env': env}, sort_keys=True) + '\n')
    os.rename(staging, directory)
    print('packed %d test binaries into %s' % (len(kept), directory))
    return 0


def read_exclusions(path):
    exclusions = {}
    for line in open(path):
        line = line.rstrip('\n')
        if not line:
            continue
        if ' ' not in line:
            die('exclusion needs "KEY TEST": %r' % line)
        key, test = line.split(' ', 1)
        if test in exclusions.setdefault(key, []):
            die('duplicate exclusion: %s' % line)
        exclusions[key].append(test)
    return exclusions


def ssh_shim(logdir):
    # spec: PORT.md "Upstream's own tests" -- wezterm-ssh's end-to-end tests return early, and so
    #       pass, when their probe of /usr/sbin/sshd with the ssh client on PATH fails. A recording
    #       ssh ahead of the real one shows whether that probe succeeded.
    real = None
    for directory in os.environ.get('PATH', '').split(os.pathsep):
        candidate = os.path.join(directory, 'ssh')
        if directory and os.access(candidate, os.X_OK):
            real = candidate
            break
    if real is None:
        die('no ssh client on PATH for the sshd probe')
    shim_dir = os.path.join(logdir, 'ssh-shim')
    os.mkdir(shim_dir)
    record = os.path.join(logdir, 'ssh-exits')
    quote = lambda s: "'" + s.replace("'", "'\\''") + "'"
    with open(os.path.join(shim_dir, 'ssh'), 'w') as shim:
        shim.write('#!/bin/sh\n%s "$@"\nstatus=$?\necho "$status" >> %s\nexit "$status"\n'
                   % (quote(real), quote(record)))
    os.chmod(os.path.join(shim_dir, 'ssh'), stat.S_IRWXU)
    return shim_dir, record


def run(manifest_path, exclusions_path, logdir, ssh_probe):
    exclusions = read_exclusions(exclusions_path)
    rows = [json.loads(line) for line in open(manifest_path) if line.strip()]
    # platform: a packed manifest's paths are relative to it; a manifest's own are absolute
    base = os.path.dirname(os.path.abspath(manifest_path))
    for row in rows:
        row['exe'] = os.path.join(base, row['exe'])
        row['cwd'] = os.path.join(base, row['cwd'])
    failures = []
    known = set(row['key'] for row in rows)
    for key in sorted(exclusions):
        if key not in known:
            failures.append('exclusion names an unknown test binary: %s' % key)
    if ssh_probe and ssh_probe not in known:
        failures.append('--ssh-probe names an unknown test binary: %s' % ssh_probe)
    totals = dict(binaries=0, listed=0, passed=0, failed=0, ignored=0, excluded=0)
    crates = set()
    for row in sorted(rows, key=lambda r: (r['set'], r['key'])):
        key = row['key']
        env = dict(os.environ)
        env.update(row['env'])
        probe = None
        if key == ssh_probe:
            shim_dir, probe = ssh_shim(logdir)
            env['PATH'] = shim_dir + os.pathsep + env.get('PATH', '')
        listing = subprocess.Popen([row['exe'], '--list', '--format', 'terse'], cwd=row['cwd'],
                                   env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        text = listing.communicate()[0].decode('utf-8', 'replace')
        if listing.returncode != 0:
            failures.append('%s %s: --list exited %d: %s' % (row['set'], key, listing.returncode,
                                                             text.strip()[-300:]))
            continue
        tests = [l[:-len(': test')] for l in text.splitlines() if l.endswith(': test')]
        skip = exclusions.get(key, [])
        for test in skip:
            if test not in tests:
                failures.append('%s: excluded test does not exist: %s' % (key, test))
        args = [row['exe'], '--exact']
        for test in skip:
            args += ['--skip', test]
        log = os.path.join(logdir, '%s__%s.log' % (row['set'], key.replace('/', '__')))
        started = time.time()
        with open(log, 'wb') as out:
            status = subprocess.call(args, cwd=row['cwd'], env=env, stdout=out,
                                     stderr=subprocess.STDOUT)
        elapsed = time.time() - started
        body = open(log, 'rb').read().decode('utf-8', 'replace')
        found = RESULT.findall(body)
        totals['binaries'] += 1
        totals['listed'] += len(tests)
        totals['excluded'] += len(skip)
        if tests:
            crates.add(key.split('/')[0])
        if len(found) != 1:
            failures.append('%s %s: exited %d without one test result line (%s)'
                            % (row['set'], key, status, log))
            continue
        verdict, passed, failed, ignored = found[0][0], int(found[0][1]), int(found[0][2]), \
            int(found[0][3])
        totals['passed'] += passed
        totals['failed'] += failed
        totals['ignored'] += ignored
        print('%-9s %-58s %4d listed %4d passed %2d failed %2d ignored %2d excluded %6.1fs'
              % (row['set'], key, len(tests), passed, failed, ignored, len(skip), elapsed))
        sys.stdout.flush()
        if status != 0 or verdict != 'ok' or failed:
            names = re.findall(r'^    (\S+)$', body.split('\nfailures:\n')[-1], re.M)
            failures.append('%s %s: exited %d, %d failed (%s): %s'
                            % (row['set'], key, status, failed, log, ' '.join(names)))
        if passed + failed + ignored != len(tests) - len(skip):
            failures.append('%s %s: %d listed - %d excluded != %d run' % (
                row['set'], key, len(tests), len(skip), passed + failed + ignored))
        if tests and not passed:
            failures.append('%s %s: has %d tests but 0 passed' % (row['set'], key, len(tests)))
        if probe is not None:
            exits = open(probe).read().split() if os.path.exists(probe) else []
            if '0' not in exits:
                failures.append('%s: its sshd probe never succeeded (ssh exits: %s), so its '
                                'end-to-end tests passed without running' % (key, ' '.join(exits)))
    print('binaries %(binaries)d, tests listed %(listed)d, passed %(passed)d, failed %(failed)d, '
          'ignored %(ignored)d, excluded %(excluded)d' % totals)
    print('crates with tests (%d): %s' % (len(crates), ' '.join(sorted(crates))))
    for failure in failures:
        print('FAIL: ' + failure)
    return 1 if failures else 0


def main(argv):
    if len(argv) >= 3 and argv[1] == 'capture':
        return capture(argv[2:])
    if len(argv) == 5 and argv[1] == 'manifest':
        return manifest(argv[2], argv[3], argv[4])
    if len(argv) == 4 and argv[1] == 'pack':
        return pack(argv[2], argv[3])
    if len(argv) in (5, 7) and argv[1] == 'run':
        ssh_probe = None
        if len(argv) == 7:
            if argv[5] != '--ssh-probe':
                die(__doc__)
            ssh_probe = argv[6]
        return run(argv[2], argv[3], argv[4], ssh_probe)
    sys.stderr.write(__doc__ + '\n')
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
