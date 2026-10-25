#!/usr/bin/env python3
"""Optional integration test. Reads a local Capture One; never executes its code.

Usage: python3 Source/test_signing_fences.py '/Applications/Capture One.app'
Requires a Capture One build that matches the patch rule and Command Line Tools.
Temporary copies are signed with dummy test entitlements and then discarded.
No vendor binaries are included in this source distribution.
"""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]).resolve()
tool = Path(__file__).resolve().parent.parent / 'S5M2 Compatibility Tool.app/Contents/MacOS/S5M2Compatibility'
main = source / 'Contents/MacOS/Capture One'
initial_hash = hashlib.sha256(main.read_bytes()).hexdigest()
results = []
with tempfile.TemporaryDirectory(prefix='s5m2-signing-tests-') as tmp:
    base = Path(tmp)
    app = base / 'Fixture.app'
    (app / 'Contents/MacOS').mkdir(parents=True)
    shutil.copy2(source / 'Contents/Info.plist', app / 'Contents/Info.plist')
    shutil.copy2(main, app / 'Contents/MacOS/Capture One')
    subprocess.run(['/usr/bin/ditto', str(source / 'Contents/Frameworks/P1CaptureCoreObjC.framework'), str(app / 'Contents/Frameworks/P1CaptureCoreObjC.framework')], check=True)
    ent = base / 'test-entitlements.plist'
    empty = base / 'empty-entitlements.plist'
    ent.write_bytes(plistlib.dumps({'keychain-access-groups': ['TEST.fixture.only']}))
    empty.write_bytes(plistlib.dumps({}))
    for name, args, expected in [
        ('identity-bound', ['--entitlements', str(ent)], 'Identity-bound'),
        ('strict-library-validation', ['--options', 'runtime', '--entitlements', str(empty)], 'Strict library validation'),
    ]:
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none', *args, str(app)], check=True, capture_output=True)
        before = set(base.iterdir())
        p = subprocess.run([str(tool), '--create', str(app), str(base)], capture_output=True, text=True, timeout=90)
        outcome = json.loads(p.stdout)
        assert p.returncode != 0 and expected in outcome['error'], (name, outcome)
        assert set(base.iterdir()) == before, 'Refusal created unexpected files'
        results.append({'test': name, 'passed': True})
    p = subprocess.run([str(tool), '--create', str(app), str(app)], capture_output=True, text=True)
    assert p.returncode != 0 and 'Output cannot be inside source app' in p.stdout
    results.append({'test': 'output-inside-source', 'passed': True})
assert hashlib.sha256(main.read_bytes()).hexdigest() == initial_hash
print(json.dumps({'tests': results, 'sourceMainUnchanged': True}, indent=2))
