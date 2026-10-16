#!/usr/bin/env python3
"""Select and prove a coherent SDK 27 Apple toolchain before building Keepy."""
import argparse
import hashlib
import json
import os
import pathlib
import platform
import shlex
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEPLOYMENT = '14.0'


class ToolchainError(RuntimeError):
    pass


def run(args, env):
    result = subprocess.run([str(arg) for arg in args], env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        raise ToolchainError(f"{shlex.join(map(str, args))}\n{result.stdout.strip()}")
    return result.stdout.strip()


def version(text, prefix):
    import re
    match = re.search(prefix + r'\s+(\d+)\.(\d+)', text)
    if not match:
        raise ToolchainError(f'Cannot identify version: {text}')
    return tuple(map(int, match.groups()))


def select(env, root=ROOT, runner=run):
    env = dict(env)
    developer = env.get('DEVELOPER_DIR')
    if not developer:
        # Prefer the pinned release when full Xcode is installed. A matching
        # selected CLT installation is also supported and proved below.
        candidates = ['/Applications/Xcode_27.0.app/Contents/Developer',
                      '/Applications/Xcode_27.app/Contents/Developer']
        developer = next((path for path in candidates if pathlib.Path(path).is_dir()), None)
        developer = developer or runner(['/usr/bin/xcode-select', '-p'], env)
    developer = pathlib.Path(developer).expanduser().resolve()
    if developer.suffix == '.app':
        developer /= 'Contents/Developer'
    if not developer.is_dir():
        raise ToolchainError(f'DEVELOPER_DIR does not exist: {developer}')
    env['DEVELOPER_DIR'] = str(developer)
    sdk = env.get('SDKROOT') or runner(['/usr/bin/xcrun', '--sdk', 'macosx27.0', '--show-sdk-path'], env)
    sdk = pathlib.Path(sdk).expanduser().resolve()
    try:
        metadata = (sdk / 'SDKSettings.json').read_bytes()
        settings = json.loads(metadata)
        sdk_version = str(settings['Version'])
    except (OSError, ValueError, KeyError) as error:
        raise ToolchainError(f'SDKROOT must be a macOS SDK directory with SDKSettings.json: {sdk}') from error
    env['SDKROOT'] = str(sdk)
    tools = {}
    for name in ['swiftc', 'swift', 'clang', 'ld', 'ar']:
        path = pathlib.Path(runner(['/usr/bin/xcrun', '--find', name], env)).absolute()
        if not path.resolve().is_relative_to(developer) or not path.is_file():
            raise ToolchainError(f'{name} is outside the selected Apple developer directory: {path}')
        tools[name] = path
    swift = runner([tools['swiftc'], '--version'], env)
    clang = runner([tools['clang'], '--version'], env)
    linker = runner([tools['ld'], '-version_details'], env)
    print(f'Developer: {developer}\nSDK: macOS {sdk_version} ({sdk})\n'
          f'Swift: {swift}\nClang: {clang}\nLinker: {tools["ld"]}\n{linker}', file=sys.stderr)
    if not sdk_version.startswith('27.'):
        raise ToolchainError(f'Keepy requires macOS SDK 27.x; selected {sdk_version}.')
    if 'Apple Swift version' not in swift or version(swift, r'Apple Swift version') < (6, 4):
        raise ToolchainError('SDK 27 requires Apple Swift 6.4 or newer from Xcode/CLT 27; an older Swift cannot read its interfaces.')
    if 'Apple clang version' not in clang or version(clang, r'Apple clang version') < (21, 0):
        raise ToolchainError('Select the Apple Clang supplied with Xcode/CLT 27.')
    # Fail on accidental runtime-target changes instead of silently overriding.
    if env.get('MACOSX_DEPLOYMENT_TARGET', DEPLOYMENT) != DEPLOYMENT:
        raise ToolchainError('Keepy must retain MACOSX_DEPLOYMENT_TARGET=14.0.')
    digest = hashlib.sha256(metadata + swift.encode() + clang.encode() + linker.encode() +
                            str(developer).encode() + str(sdk).encode())
    for path in tools.values():
        digest.update(f'{path}:{path.stat().st_mtime_ns}:{path.stat().st_size}'.encode())
    module_fingerprint = digest.hexdigest()[:20]
    digest.update(pathlib.Path(__file__).read_bytes())
    fingerprint = digest.hexdigest()[:20]
    exports = {
        'DEVELOPER_DIR': str(developer), 'SDKROOT': str(sdk),
        'MACOSX_DEPLOYMENT_TARGET': DEPLOYMENT,
        'KEEPY_SWIFTC': str(tools['swiftc']), 'KEEPY_SWIFT': str(tools['swift']),
        'KEEPY_CLANG': str(tools['clang']), 'KEEPY_APPLE_BIN': str(tools['ld'].parent),
        'KEEPY_SWIFT_MODULE_CACHE': str(root / 'target/swift-module-cache' / module_fingerprint),
        'CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER': str(root / 'scripts/macos-linker.sh'),
        'CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER': str(root / 'scripts/macos-linker.sh'),
        'CC_aarch64_apple_darwin': str(tools['clang']),
        'CC_x86_64_apple_darwin': str(tools['clang']),
        'AR_aarch64_apple_darwin': str(tools['ar']),
        'AR_x86_64_apple_darwin': str(tools['ar']),
    }
    return {**env, **exports}, exports, fingerprint


def prove(env, fingerprint, root=ROOT, runner=run, fresh=False):
    cache = root / 'target/toolchain-check' / fingerprint
    stamp = cache / 'passed'
    if stamp.exists() and not fresh:
        print('SDK 27 compile/link probes: cached success (arm64, x86_64; macOS 14.0).', file=sys.stderr)
        return
    cache.mkdir(parents=True, exist_ok=True)
    pathlib.Path(env['KEEPY_SWIFT_MODULE_CACHE']).mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='probe-', dir=cache) as scratch:
        scratch = pathlib.Path(scratch)
        c = scratch / 'probe.c'
        c.write_text('#include <iconv.h>\nint main(void) { iconv_t c = iconv_open("UTF-8", "UTF-8"); return c == (iconv_t)-1; }\n')
        swift = scratch / 'probe.swift'
        swift.write_text('import SwiftUI\nimport AppKit\nimport ServiceManagement\nimport UniformTypeIdentifiers\nimport Security\nimport Carbon\ntypealias ProbeState<Value> = SwiftUI.State<Value>\nstruct ProbeView: View { @ProbeState var text = \"\"; var body: some View { TextField(\"Probe\", text: $text) } }\nprint(ProcessInfo.processInfo.operatingSystemVersionString)\n')
        for arch in ['arm64', 'x86_64']:
            # libiconv forces the linker to parse SDK stubs containing the new
            # arm64e.x1 architecture, catching old ld/TAPI with a new SDK.
            runner([env['KEEPY_CLANG'], '-arch', arch, '-isysroot', env['SDKROOT'],
                    '-B' + env['KEEPY_APPLE_BIN'] + '/', '-mmacosx-version-min=' + DEPLOYMENT,
                    '-Werror', c, '-liconv', '-o', scratch / ('c-' + arch)], env)
            runner([env['KEEPY_SWIFTC'], '-swift-version', '5', '-warnings-as-errors',
                    '-sdk', env['SDKROOT'], '-target', arch + '-apple-macosx' + DEPLOYMENT,
                    '-module-cache-path', env['KEEPY_SWIFT_MODULE_CACHE'], swift,
                    '-o', scratch / ('swift-' + arch)], env)
    stamp.write_text('SDK 27: Swift and Clang/linker compile both architectures for macOS 14.0.\n')
    print('SDK 27 compile/link probes passed (arm64, x86_64; macOS 14.0).', file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export', action='store_true', help='print shell-quoted exports after verification')
    parser.add_argument('--github-env', type=pathlib.Path, help='append verified selection to GitHub Actions environment')
    parser.add_argument('--fresh', action='store_true', help='repeat compile/link probes even if cached')
    args = parser.parse_args()
    try:
        if platform.system() != 'Darwin':
            raise ToolchainError('macOS is required.')
        env, exports, fingerprint = select(os.environ)
        prove(env, fingerprint, fresh=args.fresh)
        if args.github_env:
            if any('\n' in value or '\r' in value for value in exports.values()):
                raise ToolchainError('GitHub environment paths must not contain line breaks.')
            with args.github_env.open('a') as output:
                for key, value in exports.items():
                    output.write(f'{key}={value}\n')
        if args.export:
            for key, value in exports.items():
                print(f'export {key}={shlex.quote(value)}')
    except (ToolchainError, OSError) as error:
        print(f'\nUnsupported macOS toolchain: {error}\n\n'
              'Install Xcode 27.0 (Apple Swift 6.4 and its Clang/linker) or matching Command Line Tools 27.\n'
              'Select it per command with DEVELOPER_DIR=/Applications/Xcode_27.0.app/Contents/Developer.\n'
              'Unset an old SDKROOT, or set SDKROOT to an absolute macOS 27.x SDK path compatible with those tools.\n'
              'Do not combine SDK 27 with Xcode/CLT 26 tools. See docs/DEVELOPMENT.md.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
