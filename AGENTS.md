# Repository workflow

## GitHub issues

- Handle one issue at a time and keep its implementation, tests, changelog,
  and version bump in one commit.
- Start the one-line commit subject with the issue number, for example:
  `#12 add URL field click actions`.
- Update the version for every completed issue in `Cargo.toml`, the root
  `bunch-of-keys` package entry in `Cargo.lock`, and `tauri.conf.json`.
- Record the new version and a short summary in `CHANGELOG.md`.

Use semantic version increments according to the issue's impact:

- `small`: add `0.0.1` for bug fixes and small internal or interface changes.
- `minor`: add `0.1.0` for backwards-compatible features.
- `major`: add `1.0.0` for breaking changes or incompatible data changes.

Reset lower-order components after `minor` or `major` bumps. For example,
`0.2.7` becomes `0.2.8` for `small`, `0.3.0` for `minor`, or `1.0.0` for
`major`.
