#!/usr/bin/env python
# platform: macOS-only -- records measured local acceptance, never publication eligibility
import json
import os
import re
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True
from artifacts import digest, stage
import gui_probe as probe


def read(path):
    with open(path) as source:
        return source.read()


def run(arguments, log, env=None):
    with open(log, 'w') as output:
        status = subprocess.call(arguments, stdout=output, stderr=subprocess.STDOUT, env=env)
    if status != 0:
        raise ValueError('required check failed or was unperformed (%s): %s; see %s' % (status, arguments[0], log))


def current(repo, work):
    app = os.path.join(work, 'stage/Mavericks WezTerm.app')
    data = stage(work, repo, app)
    if data != json.loads(read(os.path.join(app, '.mavergreen-stage.json'))):
        raise ValueError('staged artifact receipt no longer matches')
    return app, data


def non_gui(repo, work, scripts):
    evidence = os.path.join(work, 'evidence')
    path = os.path.join(evidence, 'non-gui-acceptance.json')
    report = {'schema': 1, 'scope': 'manual-native-local-only', 'passed': False}
    probe.write_json(path, report)
    app, staged = current(repo, work)
    report['build'] = staged['build']
    source = os.path.join(work, 'source')
    crate_patches = os.path.join(repo, 'patches/crates')
    allowed = sorted(name for name in os.listdir(crate_patches) if os.path.isdir(os.path.join(crate_patches, name)) and any(entry.endswith('.patch') for entry in os.listdir(os.path.join(crate_patches, name))))
    run([sys.executable, os.path.join(repo, 'build/check-lock.py'), os.path.join(source, 'Cargo.lock.upstream'), os.path.join(source, 'Cargo.lock')] + allowed, os.path.join(evidence, 'acceptance-lock.log'))
    scratch = tempfile.mkdtemp(prefix='non-gui.', dir=evidence)
    os.chmod(scratch, 0o700)
    env = dict(os.environ)
    home = os.path.join(scratch, 'home')
    os.mkdir(home, 0o700)
    env.update(HOME=home, XDG_CONFIG_HOME=os.path.join(home, 'config'), XDG_CACHE_HOME=os.path.join(home, 'cache'), XDG_DATA_HOME=os.path.join(home, 'data'), MAVERICKS_DEVIATIONS_ROOT=repo, MAVERICKS_ALLOW_ARCHS='x86_64', MAVERICKS_ALLOW_GUARDED_WEAK='', MAVERICKS_ALLOW_SELECTORS='')
    for key in ('WEZTERM_CONFIG_FILE', 'WEZTERM_CONFIG_DIR', 'WEZTERM_UNIX_DOMAIN', 'WEZTERM_PANE'):
        env.pop(key, None)
    binaries = []
    for name in ('wezterm-gui', 'wezterm', 'wezterm-mux-server'):
        binary = os.path.join(app, 'Contents/MacOS', name)
        binaries.append(binary)
        version = os.path.join(scratch, name + '-version.txt')
        run([binary, '--version'], version, env)
        if staged['build']['build_identity'] not in read(version):
            raise ValueError('incorrect staged executable identity: ' + name)
        run([binary, '--help'], os.path.join(scratch, name + '-help.txt'), env)
    run(['sh', os.path.join(scripts, 'assert_binary_compatible.sh')] + binaries, os.path.join(evidence, 'acceptance-binary-guard.log'), env)
    cast = os.path.join(scratch, 'recording.cast')
    run(['/usr/bin/script', '-q', os.path.join(scratch, 'transcript.txt'), binaries[1], '--skip-config', 'record', '-o', cast, '--', '/bin/sh', '-c', 'printf "MAVERGREEN_STAGED_PTY_OK\\n"'], os.path.join(scratch, 'pty-driver.log'), env)
    lines = read(cast).splitlines()
    if json.loads(lines[0])['version'] != 2 or 'MAVERGREEN_STAGED_PTY_OK' not in ''.join(item[2] for item in (json.loads(line) for line in lines[1:]) if item[1] == 'o'):
        raise ValueError('real staged CLI PTY output was not recorded')
    checks = {}
    # Compiler tests retain pinned SDK/cache paths; product executions alone need scratch HOME.
    for name in ('cocoa_compat', 'render_dependencies', 'notification_backend', 'tls_compat'):
        log = os.path.join(evidence, 'acceptance-' + name + '.log')
        run(['sh', os.path.join(repo, 'tests', name + '.sh')], log)
        checks[name] = {'exit_status': 0, 'log_sha256': digest(log)}
    report.update(passed=True, binaries_executed=True, staged_pty_output=True,
                  binary_compatibility={'architecture': 'x86_64', 'minimum_os': '10.9', 'sdk': '10.9', 'selected_sdk': os.environ['SDKROOT'], 'guard_log_sha256': digest(os.path.join(evidence, 'acceptance-binary-guard.log'))},
                  native_checks=checks, scratch=scratch,
                  unavailable_acceleration_case='real native constructor rejects a nonexistent accelerated renderer; physical GPU was not disabled')
    probe.write_json(path, report)
    print('PASS: staged binaries, immutable dependency identities, native boundary tests, compatibility guard and real CLI PTY')


def option(arguments, name, default=None):
    if name not in arguments:
        return default
    index = arguments.index(name)
    if index + 1 >= len(arguments):
        raise ValueError('missing value: ' + name)
    return arguments[index + 1]


def collect(repo, work, arguments):
    core = probe.owned_run(work, option(arguments, '--collect', ''))
    notifications = probe.owned_run(work, option(arguments, '--notifications', core))
    app, staged = current(repo, work)
    report = {'schema': 1, 'scope': 'manual-native-local-only; not a release or automerge gate',
              'passed': False, 'build': staged['build'], 'app': app,
              'staged_contents_sha256': staged['contents_sha256'], 'operations': {}, 'failures': []}
    path = os.path.join(work, 'evidence/local-acceptance.json')
    probe.write_json(path, report)
    ng = json.loads(read(os.path.join(work, 'evidence/non-gui-acceptance.json')))
    if not ng.get('passed') or ng.get('build') != staged['build']:
        raise ValueError('non-GUI acceptance is missing or stale')
    gui_hash = staged['build']['binaries']['wezterm-gui']['sha256']
    def fact(name, passed):
        report['operations'][name] = bool(passed)
        if not passed:
            report['failures'].append(name)
    def data(directory):
        launch = json.loads(read(os.path.join(directory, 'launch.json')))
        old = launch['stage_receipt']['build']
        if old['upstream_sha'] != staged['build']['upstream_sha'] or old['binaries']['wezterm-gui']['sha256'] != gui_hash:
            raise ValueError('GUI evidence is for a different source identity or executable')
        for filename, field in [('fixture.sh', 'fixture_sha256'), ('config.lua', 'config_sha256')]:
            if field in launch and digest(os.path.join(directory, filename)) != launch[field]:
                raise ValueError('changed GUI probe input: ' + filename)
        log = read(os.path.join(directory, 'home/.local/share/wezterm/wezterm-gui-log-%s.txt' % launch['pid']))
        running = json.loads(probe.call([os.path.join(work, 'evidence/gui-helper'), 'status', app, str(launch['pid'])]))['running']
        return launch, log, running
    launch, log, running = data(core)
    nonce = launch['nonce']
    images = {}
    for filename in ('before.png', 'after-resize.png'):
        image = os.path.join(core, filename)
        if read_binary(image)[:8] != b'\x89PNG\r\n\x1a\n':
            raise ValueError('missing real owned-window PNG: ' + filename)
        images[filename] = digest(image)
    renderer = re.search(r'OpenGL initialized! OpenGL: (.+?) wezterm version:', log)
    fact('actual_opengl_renderer', renderer is not None)
    fact('visible_output_and_resize_redraw', option(arguments, '--confirm-visual') == nonce)
    fact('hardware_input_nonce', read(os.path.join(core, 'keyboard.txt')).strip() == nonce)
    initial = tuple(int(value) for value in read(os.path.join(core, 'initial-size.txt')).split())
    resized = tuple(int(value) for value in read(os.path.join(core, 'resize-size.txt')).split())
    fact('pty_resize', len(initial) == 2 and len(resized) == 2 and min(initial + resized) > 0 and initial != resized)
    fact('normal_teardown', not running and read(os.path.join(core, 'shell-exit.txt')).strip() == '0' and 'Destroyed' in log and 'child terminated, new state is Dead' in log and ' ERROR ' not in log and 'panic at' not in log)
    nlaunch, nlog, nrunning = data(notifications)
    requests = read(os.path.join(notifications, 'requested.txt'))
    fact('notification_click_human_observed', option(arguments, '--confirm-click') == nlaunch['nonce'] and 'notify ' + nlaunch['nonce'] in requests)
    fact('notification_expiry_human_observed', option(arguments, '--confirm-expiry') == nlaunch['nonce'] and 'expire ' + nlaunch['nonce'] in requests)
    fact('notification_probe_no_reported_failure', ' ERROR ' not in nlog and 'panic at' not in nlog and not nrunning)
    fact('actual_light_appearance', read(os.path.join(notifications, 'appearance.txt')).strip() == 'Light')
    fact('requested_titlebar_options_preserve_classic_window', 'preserving the classic titlebar' in nlog)
    fact('native_negative_boundaries', set(ng.get('native_checks', {})) == set(('cocoa_compat', 'render_dependencies', 'notification_backend', 'tls_compat')))
    fresh = option(arguments, '--fresh-evidence')
    fact('fresh_build_replay', False)
    if fresh:
        fresh = os.path.realpath(fresh)
        if not fresh.startswith(os.path.realpath(work) + os.sep):
            raise ValueError('fresh replay evidence must be inside the owned work root')
        replay = json.loads(read(os.path.join(fresh, 'replay.json')))
        fresh_launch = json.loads(read(os.path.join(fresh, 'launch.json')))
        fresh_build = fresh_launch['stage_receipt']['build']
        fresh_recipe = json.loads(read(os.path.join(fresh, 'fresh-build.json')))
        success = replay.get('normal_teardown_observed') and option(arguments, '--confirm-fresh') == fresh_launch['nonce'] and fresh_build['upstream_sha'] == staged['build']['upstream_sha'] and fresh_recipe.get('empty_target_before_build') is True and fresh_recipe.get('recipe') == json.loads(read(os.path.join(work, 'prepared.json')))['recipe']
        report['operations']['fresh_build_replay'] = bool(success)
        if success:
            report['failures'].remove('fresh_build_replay')
        report['fresh_build'] = {'evidence': fresh, 'build': fresh_build, 'screenshot_sha256': digest(os.path.join(fresh, 'before.png'))}
    report.update(renderer=renderer.group(1) if renderer else None, core_evidence=core,
                  notification_evidence=notifications, screenshot_sha256=images,
                  initial_rows_columns=initial, resized_rows_columns=resized,
                  numeric_gui_exit_status=None,
                  limits=['LaunchServices owns GUI wait status; normal teardown observed, not a numeric GUI status', 'Notification URL opening/deduplication covered by native unit tests; GUI banner used no URL', 'Unavailable renderer test requests a nonexistent native accelerated renderer, not physical GPU removal', 'Modern-host parity, installed package acceptance, CI and publication are deferred'])
    report['passed'] = not report['failures']
    probe.write_json(path, report)
    print(('PASS' if report['passed'] else 'FAIL') + ': local acceptance; missing/failed: ' + ', '.join(report['failures']))
    return 0 if report['passed'] else 1


def read_binary(path):
    with open(path, 'rb') as source:
        return source.read()


if __name__ == '__main__':
    try:
        action, repo, work, scripts = sys.argv[1:5]
        if action == '--non-gui':
            non_gui(repo, work, scripts)
        elif action == '--gui':
            sys.exit(collect(repo, work, sys.argv[5:]))
        else:
            raise ValueError('unknown acceptance mode')
    except (ValueError, IOError, OSError, KeyError, IndexError) as error:
        sys.stderr.write('local-acceptance: %s\n' % error)
        sys.exit(1)
