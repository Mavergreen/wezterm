#!/usr/bin/env python
# platform: macOS-only -- launches and observes only the owned local acceptance app
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
sys.dont_write_bytecode = True
from artifacts import assert_acceptance_stage, assert_gui_idle, digest, stage


def write_json(path, value):
    with open(path + '.new', 'w') as target:
        json.dump(value, target, indent=2, sort_keys=True)
        target.write('\n')
    os.rename(path + '.new', path)


def call(arguments, timeout=30):
    output = tempfile.TemporaryFile()
    process = subprocess.Popen(arguments, stdout=output, stderr=subprocess.PIPE)
    deadline = time.time() + timeout
    while process.poll() is None and time.time() < deadline:
        time.sleep(0.1)
    if process.poll() is None:
        process.kill()
        process.wait()
        raise ValueError('owned GUI observer timed out; check that the desktop is unlocked')
    error = process.stderr.read()
    output.seek(0)
    result = output.read()
    output.close()
    if process.returncode:
        raise ValueError('owned GUI observer failed: ' + error.decode('utf-8', 'replace'))
    return result


def owned_run(work, run):
    run = os.path.realpath(run)
    evidence = os.path.realpath(os.path.join(work, 'evidence'))
    if not run.startswith(evidence + os.sep):
        raise ValueError('GUI evidence must be inside the owned evidence directory')
    if os.stat(run).st_uid != os.getuid() or os.stat(run).st_mode & 0o022:
        raise ValueError('GUI evidence directory is not private and owned')
    return run


def helper(repo, work):
    path = os.path.join(work, 'evidence/gui-helper')
    subprocess.check_call(['sh', os.path.join(repo, 'build/environment.sh'), 'sh', '-c',
        '"$CC" -fno-objc-arc "$1" -framework AppKit -framework ApplicationServices -framework ImageIO -framework CoreServices -o "$2"',
        'sh', os.path.join(repo, 'tests/fixtures/gui-helper.m'), path])
    return path


def snapshot(repo, work, run, label):
    run = owned_run(work, run)
    receipt = json.load(open(os.path.join(run, 'launch.json')))
    app = os.path.join(work, 'stage/Mavericks WezTerm.app')
    executable = os.path.join(app, 'Contents/MacOS/wezterm-gui')
    if digest(executable) != receipt['gui_sha256']:
        raise ValueError('GUI binary changed during acceptance')
    observer = os.path.join(work, 'evidence/gui-helper')
    rows = json.loads(call([observer, 'windows', app, str(receipt['pid'])]))
    windows = [row for row in rows if receipt['nonce'] in row['title']]
    if len(windows) != 1:
        raise ValueError('no uniquely identified owned test window')
    window = windows[0]
    call([observer, 'capture', app, str(receipt['pid']), str(window['id']), os.path.join(run, label + '.png')])
    write_json(os.path.join(run, 'window-' + label + '.json'), window)
    return window


def launch(repo, work, mode):
    assert_gui_idle(work, repo)
    app = os.path.join(work, 'stage/Mavericks WezTerm.app')
    staged = stage(work, repo, app)
    if staged != json.load(open(os.path.join(app, '.mavergreen-stage.json'))):
        raise ValueError('modified staged bundle')
    assert_acceptance_stage(app)
    observer = helper(repo, work)
    run = tempfile.mkdtemp(prefix='gui-' + mode + '.', dir=os.path.join(work, 'evidence'))
    os.chmod(run, 0o700)
    home_target = os.path.join(run, 'home')
    os.mkdir(home_target, 0o700)
    alias = tempfile.mkdtemp(prefix='mwz-qa.', dir='/private/tmp')
    os.chmod(alias, 0o700)
    with open(os.path.join(alias, '.owner'), 'w') as target:
        target.write(run + '\n')
    home = os.path.join(alias, 'h')
    os.symlink(home_target, home)
    if len(home + '/.local/share/wezterm/gui-sock-999999') >= 104:
        raise ValueError('isolated GUI runtime path exceeds native Unix socket limit')
    nonce = 'mav-' + uuid.uuid4().hex[:10]
    shell = os.path.join(run, 'fixture.sh')
    shutil.copyfile(os.path.join(repo, 'tests/fixtures/gui-terminal.sh'), shell)
    config = os.path.join(run, 'config.lua')
    template = open(os.path.join(repo, 'tests/fixtures/gui-config.lua')).read()
    for name, value in [('RUN', run), ('NONCE', nonce), ('SHELL', shell), ('MODE', mode)]:
        template = template.replace('@' + name + '@', json.dumps(value))
    with open(config, 'w') as target:
        target.write(template)
    receipt = {'owner': repo, 'mode': mode, 'run': run, 'nonce': nonce,
               'private_home_alias': home, 'milestone_passed': False,
               'stage_receipt': staged, 'gui_sha256': digest(os.path.join(app, 'Contents/MacOS/wezterm-gui')),
               'fixture_sha256': digest(shell), 'config_sha256': digest(config),
               'observer_sha256': digest(observer)}
    receipt.update(json.loads(call([observer, 'launch', app, run, config, home])))
    write_json(os.path.join(run, 'launch.json'), receipt)
    write_json(os.path.join(work, 'gui-active.json'), {'owner': repo, 'pid': receipt['pid'], 'run': run})
    print(json.dumps({'run': run, 'nonce': nonce, 'pid': receipt['pid'], 'state': 'pending'}))
    sys.stdout.flush()
    for attempt in range(20):
        rows = json.loads(call([observer, 'windows', app, str(receipt['pid'])]))
        if any(nonce in row['title'] for row in rows):
            time.sleep(2)
            snapshot(repo, work, run, 'before')
            print('Owned window capture: ' + os.path.join(run, 'before.png'))
            break
        time.sleep(0.2)
    else:
        raise ValueError('owned test window did not appear')
    if mode == 'replay':
        deadline = time.time() + 45
        while time.time() < deadline:
            if not json.loads(call([observer, 'status', app, str(receipt['pid'])]))['running']:
                break
            time.sleep(0.2)
        else:
            raise ValueError('replay GUI did not terminate normally')
        log = os.path.join(run, 'home/.local/share/wezterm/wezterm-gui-log-%s.txt' % receipt['pid'])
        text = open(log).read()
        if open(os.path.join(run, 'shell-exit.txt')).read().strip() != '0' or 'Destroyed' not in text or 'OpenGL initialized!' not in text or ' ERROR ' in text or 'panic at' in text:
            raise ValueError('replay did not complete its actual CGL/PTY/window lifecycle')
        write_json(os.path.join(run, 'replay.json'), {'normal_teardown_observed': True,
            'visual_confirmation': 'pending', 'gui_sha256': receipt['gui_sha256'],
            'screenshot_sha256': digest(os.path.join(run, 'before.png'))})
        print('Replay completed; inspect its owned PNG before confirming visual output.')
    else:
        print('Type ' + nonce + ' and Return. Resize; run --snapshot before exit. Test notify/expire; then exit.')
    return run


if __name__ == '__main__':
    try:
        action, repo, work = sys.argv[1:4]
        if action in ('start', 'replay'):
            launch(repo, work, 'replay' if action == 'replay' else 'interactive')
            sys.exit(2)
        elif action == 'snapshot':
            snapshot(repo, work, sys.argv[4], 'after-resize')
        else:
            raise ValueError('unknown GUI probe action')
    except (ValueError, OSError, IOError, KeyError, IndexError) as error:
        sys.stderr.write('gui-probe: %s\n' % error)
        sys.exit(1)
