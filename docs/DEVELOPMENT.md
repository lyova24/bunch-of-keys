# Development and packaging

## Requirements

The project requires Rust 1.85 or newer and Node.js for frontend regression
tests. On Debian or Ubuntu, install the desktop build dependencies with:

```bash
sudo apt install build-essential curl file libappindicator3-dev \
  libgtk-3-dev librsvg2-dev libssl-dev libwebkit2gtk-4.1-dev
```

## Checks

Run the same Rust checks used by CI:

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

The UI regression tests use Node.js' built-in test runner:

```bash
node --test ui/*.test.mjs
```

Check that the package version matches in Cargo, the lockfile, Tauri, and the
latest changelog entry:

```bash
bash scripts/check-version-sync.sh
```

CI runs the Rust and UI checks only when a pull request or `master` update
contains non-documentation changes. Dependency policy and RustSec audits run
when Cargo inputs change and on a weekly schedule. Dependabot groups weekly
Cargo and GitHub Actions updates. Existing RustSec exceptions are narrowly
documented in `.cargo/audit.toml`; new vulnerability advisories still fail the
audit.

## Local development

Install the Tauri CLI and run the desktop application:

```bash
cargo install tauri-cli --version '^2' --locked
cargo tauri dev
```

The frontend is static HTML, CSS, and JavaScript under `ui/`. The Rust backend
is a single crate under `src/`; see [the architecture overview](ARCHITECTURE.md)
for component and trust-boundary details.

## Debian package

Build a Debian package with:

```bash
cargo tauri build --bundles deb
```

The resulting package is written under `target/release/bundle/deb/`.

The `Build Debian package` GitHub Actions workflow can also be started
manually for a selected branch, tag, or commit. It uploads a versioned `.deb`
and SHA-256 checksum as a workflow artifact; it does not create a GitHub
release, tag, or signature.
