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
