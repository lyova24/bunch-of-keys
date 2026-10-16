#!/usr/bin/env python3
"""Deterministic selection/failure/cross-link tests without an installed SDK."""
import contextlib
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('toolchain', pathlib.Path(__file__).with_name('check-macos-toolchain.py'))
toolchain = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(toolchain)
VERIFY_SPEC = importlib.util.spec_from_file_location('verify', pathlib.Path(__file__).with_name('verify-macos-build.py'))
verify = importlib.util.module_from_spec(VERIFY_SPEC)
VERIFY_SPEC.loader.exec_module(verify)


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='keepy toolchain ')
        self.addCleanup(self.scratch.cleanup)
        self.root = pathlib.Path(self.scratch.name).resolve()
        self.developer = self.root / 'Xcode 27.app/Contents/Developer'
        self.bin = self.developer / 'Toolchains/XcodeDefault.xctoolchain/usr/bin'
        self.bin.mkdir(parents=True)
        for name in ['swiftc', 'swift', 'clang', 'ld', 'ar']:
            (self.bin / name).touch()
        self.sdk = self.developer / 'Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk'
        self.sdk.mkdir(parents=True)
        self.metadata = self.sdk / 'SDKSettings.json'
        self.metadata.write_text(json.dumps({'Version': '27.0'}))
        self.env = {'DEVELOPER_DIR': str(self.developer), 'SDKROOT': str(self.sdk)}
        self.swift = 'Apple Swift version 6.4 (swiftlang-6.4.0.31.4 clang-2100.3.31.1)'
        self.calls = []
        self.outside = None
        self.fail_probe = False

    def run_tool(self, args, env):
        args = list(map(str, args)); self.calls.append((args, env.copy()))
        if args[0] == '/usr/bin/xcode-select':
            return str(self.developer)
        if args[0] == '/usr/bin/xcrun':
            if '--find' in args:
                return str(self.outside or self.bin / args[-1])
            return str(self.sdk)
        if args[-1] == '--version':
            return self.swift if 'swift' in args[0] else 'Apple clang version 21.0.0 (clang-2100.3.31.1)'
        if args[-1] == '-version_details':
            return '{"version":"1300","tapi":{"version":"21.0.3"}}'
        if self.fail_probe:
            raise toolchain.ToolchainError('ld: malformed file: unknown architecture arm64e.x1')
        return ''

    def select(self, env=None):
        with contextlib.redirect_stderr(io.StringIO()):
            return toolchain.select(self.env if env is None else env, self.root, self.run_tool)

    def test_exports_keep_sdk_and_tools_together_with_spaces(self):
        env, exports, fingerprint = self.select()
        self.assertEqual(exports['SDKROOT'], str(self.sdk))
        self.assertEqual(exports['MACOSX_DEPLOYMENT_TARGET'], '14.0')
        self.assertEqual(exports['KEEPY_SWIFTC'], str(self.bin / 'swiftc'))
        self.assertEqual(exports['CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER'], str(self.root / 'scripts/macos-linker.sh'))
        self.assertEqual(env['CC_aarch64_apple_darwin'], str(self.bin / 'clang'))
        with contextlib.redirect_stderr(io.StringIO()):
            toolchain.prove(env, fingerprint, self.root, self.run_tool)
            before = len(self.calls)
            toolchain.prove(env, fingerprint, self.root, self.run_tool)
            self.assertEqual(len(self.calls), before)
            toolchain.prove(env, fingerprint, self.root, self.run_tool, fresh=True)
        commands = [args for args, _ in self.calls if '-o' in args]
        self.assertEqual(len(commands), 8)
        for args in commands:
            if '-target' in args:
                self.assertIn(args[args.index('-target') + 1], ['arm64-apple-macosx14.0', 'x86_64-apple-macosx14.0'])
                self.assertIn('-warnings-as-errors', args)
            else:
                self.assertIn('-mmacosx-version-min=14.0', args)
                self.assertIn('-B' + str(self.bin) + '/', args)
                self.assertIn('-liconv', args)

    def test_pinned_sdk_is_requested_without_override(self):
        self.select({'DEVELOPER_DIR': str(self.developer.parent.parent)})
        self.assertTrue(any(args == ['/usr/bin/xcrun', '--sdk', 'macosx27.0', '--show-sdk-path'] for args, _ in self.calls))

    def test_old_swift_rejected_before_compiling(self):
        self.swift = 'Apple Swift version 6.3.3'
        with self.assertRaisesRegex(toolchain.ToolchainError, 'Swift 6.4'):
            self.select()
        self.assertFalse(any('-o' in args for args, _ in self.calls))

    def test_old_sdk_and_raised_runtime_target_rejected(self):
        self.metadata.write_text(json.dumps({'Version': '26.5'}))
        with self.assertRaisesRegex(toolchain.ToolchainError, 'SDK 27'):
            self.select()
        self.metadata.write_text(json.dumps({'Version': '27.0'}))
        with self.assertRaisesRegex(toolchain.ToolchainError, 'DEPLOYMENT_TARGET=14.0'):
            self.select({**self.env, 'MACOSX_DEPLOYMENT_TARGET': '27.0'})

    def test_mixed_toolchain_rejected(self):
        self.outside = '/usr/bin/clang'
        with self.assertRaisesRegex(toolchain.ToolchainError, 'outside'):
            self.select()

    def test_failed_link_probe_never_cached(self):
        env, _, fingerprint = self.select()
        self.fail_probe = True
        with self.assertRaisesRegex(toolchain.ToolchainError, 'unknown architecture'):
            toolchain.prove(env, fingerprint, self.root, self.run_tool)
        self.assertFalse((self.root / 'target/toolchain-check' / fingerprint / 'passed').exists())

    def test_linker_wrapper_forces_selected_sdk_and_linker(self):
        fake = self.root / 'fake clang'
        fake.write_text('#!/bin/bash\nprintf "%s\\n" "$@"\n')
        fake.chmod(0o755)
        result = subprocess.run(['bash', str(toolchain.ROOT / 'scripts/macos-linker.sh'), '-arch', 'x86_64', 'object.o'],
                                env={**os.environ, 'KEEPY_CLANG': str(fake), 'KEEPY_APPLE_BIN': str(self.bin), 'SDKROOT': str(self.sdk)},
                                text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout.splitlines(), ['-B' + str(self.bin) + '/', '-isysroot', str(self.sdk),
                                                     '-mmacosx-version-min=14.0', '-arch', 'x86_64', 'object.o'])


class MetadataTests(unittest.TestCase):
    def test_requires_both_new_sdk_and_original_runtime_target(self):
        for minimum, sdk, expected in [('14.0', '27.0', True), ('27.0', '27.0', False), ('14.0', '26.5', False)]:
            commands = f'Load command 9\n cmd LC_BUILD_VERSION\n platform 1\n minos {minimum}\n sdk {sdk}\n'
            with patch.object(verify.subprocess, 'check_output', side_effect=['x86_64', commands]), contextlib.redirect_stdout(io.StringIO()):
                if expected:
                    verify.verify_binary(pathlib.Path('keepy'), 'x86_64')
                else:
                    with self.assertRaisesRegex(ValueError, 'expected macOS 14.0 / SDK 27.x'):
                        verify.verify_binary(pathlib.Path('keepy'), 'x86_64')
        with self.assertRaisesRegex(ValueError, 'Missing LC_BUILD_VERSION'):
            verify.build_version('cmd LC_VERSION_MIN_MACOSX\n version 14.0')


if __name__ == '__main__':
    unittest.main()
