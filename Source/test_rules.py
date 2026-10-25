#!/usr/bin/env python3
"""Synthetic Mach-O fixtures only. Does not need or ship Capture One binaries."""
import json
from pathlib import Path
import random
import struct
import subprocess
import sys
import tempfile
import unittest

TOOL = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / 'S5M2 Compatibility Tool.app/Contents/MacOS/S5M2Compatibility'
sys.argv = sys.argv[:1]
INIT = '__GLOBAL__sub_I_PTPPanasonicFactory.cpp'
SUPPORT = '__ZN10CaptureOne3PTP9Panasonic16PanasonicFactory11IsSupportedERKNS0_8Protocol10DeviceInfoE'

WORDS = [
    0x90000008,0x3dc00100,0x90000008,0x3dc00101,0xad0187e0,
    0xf90017ff,0xf94017e8,0x9100c3e9,0x8b080928,0x3dc00100,
    0x3d8007e0,0xfd400908,0xb9401914,0x52800400,0x94000000,
    0x90000008,0xfd400100,0x2e201d00,0x90000008,0x3dc00101,
    0x3dc007e2,0x6e211c41,0x90000008,0x91000108,0xf9000100,
    0x90000009,0x3dc00122,0x52800009,0x4a090289,0x3c808102,
    0x3d800001,0xfd000800,0x29037c09,
]

def adrp(reg, target, pc):
    pages = ((target & ~4095) - (pc & ~4095)) // 4096
    imm = pages & 0x1fffff
    return 0x90000000 | ((imm & 3) << 29) | ((imm >> 2) << 5) | reg

def fixture(seed=1, shift=0, model='DC-S1M2', referenced=True, duplicate=False):
    """Build minimal valid symbol/section tables and a rule-family initializer."""
    rng = random.Random(seed)
    d = bytearray(0x3000 + shift)
    struct.pack_into('<8I', d, 0, 0xfeedfacf, 0x0100000c, 0, 6, 2, 256, 0, 0)
    struct.pack_into('<II16sQQQQIIII', d, 32, 0x19, 232, b'__TEXT', 0, len(d), 0, len(d), 7, 5, 2, 0)
    struct.pack_into('<16s16sQQIIIIIIII', d, 104, b'__text', b'__TEXT', 0x400, 0x800, 0x400, 2, 0, 0, 0x80000400, 0, 0, 0)
    struct.pack_into('<16s16sQQIIIIIIII', d, 184, b'__const', b'__TEXT', 0x1000, 0x1000+shift, 0x1000, 2, 0, 0, 0, 0, 0, 0)
    symoff = 0x2400 + shift
    strings = b'\0'
    entries = []
    for name, addr in [(INIT, 0x400), ('_after_init', 0x780), (SUPPORT, 0x800), ('_after_support', 0x880)]:
        entries.append(struct.pack('<IBBHQ', len(strings), 0x0e, 1, 0, addr))
        strings += name.encode() + b'\0'
    stroff = symoff + 16 * len(entries)
    struct.pack_into('<6I', d, 264, 2, 24, symoff, len(entries), stroff, len(strings))
    d[symoff:stroff] = b''.join(entries)
    d[stroff:stroff+len(strings)] = strings
    enc, key16, key8, record = 0x1000+shift, 0x1100+shift, 0x1120+shift, 0x1180+shift
    keys = [rng.randrange(65536) for _ in range(7)]
    for i, c in enumerate(model):
        struct.pack_into('<I', d, enc+i*4, ord(c) ^ keys[i])
    struct.pack_into('<4I', d, key16, *keys[:4])
    struct.pack_into('<2I', d, key8, *keys[4:6])

    def initializer(at):
        struct.pack_into('<2I', d, at-8, 0x52800028, 0xb9001928)
        words = WORDS.copy()
        for i, target, vector in [(0, enc, True), (2, enc+16, True), (15, key8, False), (18, key16, True)]:
            words[i] = adrp(8, target, at+i*4)
            words[i+1] |= ((target & 4095) // (16 if vector else 8)) << 10
        words[22] = adrp(8, record+8, at+22*4)
        words[23] |= ((record+8) & 4095) << 10
        words[25] = adrp(9, key16, at+25*4)
        words[26] |= ((key16 & 4095) // 16) << 10
        words[27] |= keys[6] << 5
        struct.pack_into('<33I', d, at, *words)

    initializer(0x408)
    if duplicate:
        initializer(0x508)
    if referenced:
        struct.pack_into('<2I', d, 0x800, adrp(21, record, 0x800), 0x910002b5 | ((record & 4095) << 10))
    return d

def fat(thin):
    # Unrelated second slice tests preservation and correct ARM64 base offsets.
    intel = bytes.fromhex('cffaedfe070000010300000006000000') + bytes(48)
    d = bytearray(0x2000 + len(thin))
    struct.pack_into('>II', d, 0, 0xcafebabe, 2)
    struct.pack_into('>5I', d, 8, 0x01000007, 3, 0x1000, len(intel), 12)
    struct.pack_into('>5I', d, 28, 0x0100000c, 0, 0x2000, len(thin), 12)
    d[0x1000:0x1000+len(intel)] = intel
    d[0x2000:] = thin
    return d

def fat64(thin):
    d = bytearray(0x1000 + len(thin))
    struct.pack_into('>II', d, 0, 0xcafebabf, 1)
    struct.pack_into('>IIQQII', d, 8, 0x0100000c, 0, 0x1000, len(thin), 12, 0)
    d[0x1000:] = thin
    return d

def analyze(data):
    with tempfile.TemporaryDirectory() as tmp:
        p = Path(tmp) / 'fixture'
        p.write_bytes(data)
        result = subprocess.run([str(TOOL), '--analyze-binary', str(p)], capture_output=True, text=True, timeout=20)
        return result.returncode, json.loads(result.stdout)

class RuleTests(unittest.TestCase):
    def test_multiple_seeds_and_relocated_constants(self):
        for seed, shift in [(1, 0), (8, 0x200), (91, 0x1000), (17, 0x1200)]:
            with self.subTest(seed=seed, shift=shift):
                status, result = analyze(fixture(seed, shift))
                self.assertEqual(status, 0, result)
                self.assertEqual(result['model'], 'DC-S1M2')
                self.assertEqual(result['offset'], 0x1010+shift)
                self.assertFalse(result['testedBinary'])

    def test_only_one_byte_is_needed(self):
        data = fixture(8, 0x1000)
        _, first = analyze(data)
        data[first['offset']] ^= 4
        status, result = analyze(data)
        self.assertEqual(status, 0, result)
        self.assertTrue(result['alreadyPatched'])

    def test_universal_offset(self):
        status, result = analyze(fat(fixture()))
        self.assertEqual(status, 0, result)
        self.assertEqual(result['offset'], 0x3010)
        self.assertEqual(result['architectures'], ['x86_64', 'arm64'])

    def test_fat64_offset(self):
        status, result = analyze(fat64(fixture()))
        self.assertEqual(status, 0, result)
        self.assertEqual(result['offset'], 0x2010)

    def test_wrong_model(self):
        status, _ = analyze(fixture(model='DC-S9M2'))
        self.assertNotEqual(status, 0)

    def test_missing_whitelist_reference(self):
        status, _ = analyze(fixture(referenced=False))
        self.assertNotEqual(status, 0)

    def test_ambiguous_candidates(self):
        status, _ = analyze(fixture(duplicate=True))
        self.assertNotEqual(status, 0)

    def test_modified_instruction(self):
        data = fixture()
        data[0x408+17*4] ^= 1
        status, _ = analyze(data)
        self.assertNotEqual(status, 0)

    def test_missing_symbols(self):
        data = fixture()
        data[264+12:264+16] = bytes(4)
        status, _ = analyze(data)
        self.assertNotEqual(status, 0)

    def test_corrupt_bounds(self):
        for size in [0, 5, 31, 100, 0x1000]:
            with self.subTest(size=size):
                status, _ = analyze(fixture()[:size])
                self.assertNotEqual(status, 0)

    def test_overlapping_slices(self):
        data = fat(fixture())
        struct.pack_into('>I', data, 28+8, 0x1000)
        status, _ = analyze(data)
        self.assertNotEqual(status, 0)

    def test_missing_arm64(self):
        data = fixture()
        struct.pack_into('<I', data, 4, 0x01000007)
        status, _ = analyze(data)
        self.assertNotEqual(status, 0)

if __name__ == '__main__':
    unittest.main(verbosity=2)
