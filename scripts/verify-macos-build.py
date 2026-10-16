#!/usr/bin/env python3
"""Verify both runtime compatibility and SDK adoption in built Mach-O files."""
import argparse
import pathlib
import plistlib
import re
import subprocess


def build_version(load_commands):
    for command in load_commands.split('Load command'):
        if re.search(r'\bcmd LC_BUILD_VERSION\b', command):
            def value(name):
                match = re.search(r'^\s*' + name + r'\s+(\S+)', command, re.M)
                if not match:
                    raise ValueError(f'Missing {name} in LC_BUILD_VERSION')
                return match.group(1)
            return value('platform'), value('minos'), value('sdk')
    raise ValueError('Missing LC_BUILD_VERSION')


def verify_binary(path, arch):
    actual = subprocess.check_output(['lipo', '-archs', str(path)], text=True).strip()
    if actual != arch:
        raise ValueError(f'{path}: expected {arch}, found {actual}')
    commands = subprocess.check_output(['otool', '-l', str(path)], text=True)
    platform, minimum, sdk = build_version(commands)
    if platform not in ['1', 'MACOS'] or minimum not in ['14.0', '14.0.0'] or not sdk.startswith('27.'):
        raise ValueError(f'{path}: expected macOS 14.0 / SDK 27.x, found platform={platform}, minos={minimum}, sdk={sdk}')
    print(f'Verified {path}: {arch}, min macOS {minimum}, SDK {sdk}.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=pathlib.Path)
    parser.add_argument('--arch', choices=['arm64', 'x86_64'], required=True)
    parser.add_argument('--helper', type=pathlib.Path)
    args = parser.parse_args()
    with (args.app / 'Contents/Info.plist').open('rb') as source:
        info = plistlib.load(source)
    if info.get('LSMinimumSystemVersion') != '14.0':
        raise ValueError('Bundle LSMinimumSystemVersion must remain 14.0')
    for name in ['keepy', 'keepy-core']:
        verify_binary(args.app / 'Contents/MacOS' / name, args.arch)
    if args.helper:
        import platform
        verify_binary(args.helper, platform.machine())


if __name__ == '__main__':
    main()
