#!/usr/bin/env python3
"""Real Core Audio integration checks; never change device settings or record audio."""
import argparse
import json
from pathlib import Path
import selectors
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / '.build/Macam.app/Contents/MacOS/Macam'
UID = 'org.macam.Macam.Audio'
OUT = ROOT / '.build/verification'
OUT.mkdir(parents=True, exist_ok=True)
children = []

def run(*args):
    p = subprocess.run([str(BIN), *args], capture_output=True, text=True, timeout=20)
    if p.returncode:
        raise RuntimeError(p.stderr or p.stdout)
    return [json.loads(line) for line in p.stdout.splitlines() if line.strip()]

def owner(name, seconds, extra=()):
    p = subprocess.Popen([str(BIN), '--probe', str(seconds), '--allow-silence', *extra],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    children.append(p)
    sel = selectors.DefaultSelector()
    sel.register(p.stdout, selectors.EVENT_READ)
    if not sel.select(30):
        raise RuntimeError('Owner did not start in 30 seconds; check the macOS permission prompt')
    line = p.stdout.readline()
    sel.close()
    if not line:
        raise RuntimeError(p.stderr.read())
    first = json.loads(line)
    if 'started' not in first:
        raise RuntimeError(first)
    return p, first

def finish(name, p, first, timeout=30):
    stdout, stderr = p.communicate(timeout=timeout)
    events = [first] + [json.loads(line) for line in stdout.splitlines() if line.strip()]
    (OUT / f'{name}.json').write_text(json.dumps({'events': events, 'stderr': stderr, 'exitCode': p.returncode}, indent=2))
    if p.returncode:
        raise RuntimeError(f'{name}: {stderr}')
    result = events[-1]
    assert result['settingsUnchanged'] and result['deviceRemoved'] and not result['cleanupErrors'], result
    return result

def absent():
    return all(d['uid'] != UID for d in run('--inspect')[0]['devices'])

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=int, default=30)
    parser.add_argument('--source', action='append', default=[])
    args = parser.parse_args()
    if not 5 <= args.seconds <= 1800:
        parser.error('--seconds must be between 5 and 1800')
    extra = [part for source in args.source for part in ('--source', source)]
    baseline = run('--inspect')[0]['settings']
    assert absent(), 'Stop the menu-bar app before running verification'
    print('Testing independent stereo input and settings preservation…', flush=True)
    p, first = owner('capture', args.seconds + 3, extra)
    reader = subprocess.run([str(BIN), '--read', str(args.seconds)], capture_output=True, text=True, timeout=args.seconds + 30)
    (OUT / 'receiver.json').write_text(json.dumps({'events': [json.loads(x) for x in reader.stdout.splitlines()],
                                                'stderr': reader.stderr, 'exitCode': reader.returncode}, indent=2))
    assert reader.returncode == 0, reader.stderr
    r = json.loads(reader.stdout.splitlines()[-1])['independentReceiver']
    result = finish('capture', p, first)
    assert r['nonzeroSamples'] > 0 and result['owner']['nonzeroSamples'] > 0
    assert r['timestampDiscontinuities'] == 0 and result['owner']['timestampDiscontinuities'] == 0
    assert r['samples'] == 2 * r['frames'], 'Input must be stereo'
    assert absent()
    print('Testing an empty selected source (must remain silent)…', flush=True)
    p, first = owner('empty-selection', 3, ('--source', 'org.macam.nonexistent-test-source'))
    empty = finish('empty-selection', p, first)
    assert empty['owner']['nonzeroSamples'] == 0, 'Unselected playback leaked into selected-app capture'
    print('Testing SIGTERM cleanup…', flush=True)
    p, first = owner('sigterm', 30)
    p.send_signal(signal.SIGTERM)
    terminated = finish('sigterm', p, first)
    assert terminated['owner']['interrupted'] and absent()
    print('Testing forced termination, journal recovery, and restart…', flush=True)
    p, first = owner('crash', 30)
    p.kill(); p.communicate(timeout=5)
    # Only our subprocess is force-killed. --cleanup verifies exact journal UUIDs.
    leftover = not absent()
    run('--cleanup')
    assert absent()
    p, first = owner('restart', 3)
    restart = finish('restart', p, first)
    assert absent()
    after = run('--inspect')[0]['settings']
    assert baseline == after, 'Settings differ after the integration suite'
    report = {'seconds': args.seconds, 'sources': args.source or ['whole-system'],
              'receiver': r, 'owner': result['owner'], 'emptySelectionSilent': True,
              'sigtermCleaned': True, 'crashLeftAggregate': leftover,
              'journalRecoveryPassed': True, 'restartPassed': True, 'settingsUnchanged': True,
              'browserVerified': False, 'physicalControlsVerified': False}
    (OUT / 'summary.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2), flush=True)

try:
    main()
finally:
    for child in children:
        if child.poll() is None:
            child.terminate()
            try: child.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                child.kill(); child.communicate()
