# Repository workflow

## GitHub issues

- Handle one issue at a time and keep its implementation, tests, changelog,
  and version bump in one commit.
- Start the one-line commit subject with the issue number, for example:
  `#12 add URL field click actions`.
- After implementation and verification, show the result to the user and get
  their explicit approval before closing the GitHub issue, unless the user has
  explicitly authorized unattended issue processing. Pushing a commit does
  not count as approval to close the issue.
- Implement reordering and moving interactions with direct drag-and-drop. Do
  not substitute arrow buttons unless the user explicitly requests them.
- Treat acceptance criteria as the minimum. Fill in underspecified behavior
  with a robust implementation and a coherent UX/UI rather than the smallest
  literal code change.
- Visually inspect relevant states for every UI issue in addition to running
  automated code checks.
- Update the version for every completed issue in `Cargo.toml`, the root
  `keepy` package entry in `Cargo.lock`, and both bundle version keys
  in `macos/Info.plist`.
- Record the new version and a short summary in `CHANGELOG.md`.

Use semantic version increments according to the issue's impact:

- `small`: add `0.0.1` for bug fixes and small internal or interface changes.
- `minor`: add `0.1.0` for backwards-compatible features.
- `major`: add `1.0.0` for breaking changes or incompatible data changes.

Reset lower-order components after `minor` or `major` bumps. For example,
`0.2.7` becomes `0.2.8` for `small`, `0.3.0` for `minor`, or `1.0.0` for
`major`.
