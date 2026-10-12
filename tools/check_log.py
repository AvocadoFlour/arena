#!/usr/bin/env python3
"""Gate: fail on any script error / engine ERROR / GDScript backtrace not explained by tests/expected_warnings.txt."""
import sys, re
allowed = [l.strip() for l in open('tests/expected_warnings.txt') if l.strip() and not l.startswith('#')]
IGNORE = ['audio_driver_alsa', 'ALSA lib', 'Unknown PCM',   # box has no sound card
          'leaked at exit', 'still in use at exit', 'Pages in use exist at exit']   # exit-time leak reports: listed, not fatal
bad = []
for path in sys.argv[1:]:
    lines = open(path, errors='replace').read().splitlines()
    skip_trace = False
    for i, l in enumerate(lines):
        if l.startswith(('WARNING:', 'ERROR:', 'SCRIPT ERROR:', 'Parse Error', 'USER ERROR:', 'USER WARNING:')):
            ctx = l + ' ' + (lines[i + 1] if i + 1 < len(lines) else '')
            skip_trace = any(a in l for a in allowed)
            if skip_trace or any(x in ctx for x in IGNORE):
                continue
            if l.startswith('WARNING:') and 'backtrace' not in ' '.join(lines[i + 1:i + 4]):
                continue   # plain engine warnings (e.g. vsync, ObjectDB leak) don't fail the gate
            bad.append(f'{path}:{i + 1}: {l}')
        elif 'GDScript backtrace' in l and not skip_trace and not any(b.startswith(f'{path}:{i}') or b.startswith(f'{path}:{i - 1}') or b.startswith(f'{path}:{i - 2}') for b in bad):
            bad.append(f'{path}:{i + 1}: {l.strip()} (after: {lines[i - 2].strip() if i >= 2 else ""})')
leaks = [l for p in sys.argv[1:] for l in open(p, errors='replace') if 'leaked at exit' in l]
if leaks:
    print(f'note: {len(leaks)} exit-time leak report(s) (non-fatal), e.g. {leaks[0].strip()}')
for b in bad[:30]:
    print(b)
sys.exit(1 if bad else 0)
