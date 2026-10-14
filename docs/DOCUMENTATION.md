# Documentation and screenshots

The site uses [Diplodoc](https://diplodoc.com/docs/en/quickstart) and is published
at [lyova24.github.io/keepy](https://lyova24.github.io/keepy/).

## Build and preview

Install the Node.js version in `.node-version` (Node 24, npm 11.5.1 or newer),
then run from the repository root:

```sh
npm ci --ignore-scripts --no-fund --no-audit
npm run docs:build
npm run docs:check
npm run docs:preview
```

Open `http://127.0.0.1:5005/keepy/`. Stop the preview with Ctrl-C. The preview
serves the same repository subpath as GitHub Pages; paths outside `/keepy/`
return 404 to catch assets that accidentally refer to the domain root.
Rebuild after editing a page or image.

`docs/toc.yaml` defines navigation and `docs/.yfm` configures English pages,
static HTML content, and local browser search. Pages remain ordinary Markdown
and screenshot paths remain relative, so the user guide also reads correctly
on GitHub. The landing page's logo comes from the existing `icons/` assets.

`scripts/docs.mjs` stages `docs/`, root `SECURITY.md`, root `CHANGELOG.md`, and
logo assets into `target/docs-source/`, then builds `target/docs-site/`.
These directories are generated and ignored by Git. Edit only the canonical
sources; security policy and release history do not require separate copies.
The build normalizes resource paths in Diplodoc 5.63.3's generated search page
so its scripts and styles resolve from the document root under `/keepy/`.
The checker verifies generated page links, anchors, image/script/style assets,
the `/keepy/` subpath, and README's local source links.

## Publish

In GitHub repository **Settings → Pages → Build and deployment**, select
**GitHub Actions** as the source. The **Documentation** workflow builds and
checks documentation on pull requests and on relevant pushes to `master`.
Only successful builds from `master` are uploaded and deployed. Pull requests,
including forks, receive no Pages write permission and cannot deploy.

For a manual rebuild, open **Actions → Documentation → Run workflow** and
select `master`. Other branches can be built manually but do not deploy.
The deployment job reports the public URL. If repository environment rules
require deployment approval, approve the `github-pages` environment in GitHub.

Update the exact Diplodoc dependency version in `package.json` and commit the
resulting `package-lock.json` together. Use `npm ci` in CI and for reproducible
local builds. Dependabot proposes documentation dependency updates weekly.

## Reproduce screenshots

Screenshots in `docs/images/` show the native macOS application with synthetic
data. Build the application first, then prepare and launch the isolated demo:

```sh
bash scripts/build-macos.sh
bash scripts/prepare-docs-demo.sh
KEEPY_DATA_DIR="$PWD/target/docs-demo" \
  target/docs-demo-app/Keepy.app/Contents/MacOS/keepy
```

The preparation script refuses to overwrite existing demo directories. Move
`target/docs-demo` and `target/docs-demo-app` aside before starting a new demo.
It gives the copied application a separate bundle identity, avoiding changes
to the installed app's window preferences. Its vault and appearance settings
stay inside `target/docs-demo`. Never capture your real vault.

Unlock **Documentation Demo** with `documentation-demo-password`. Expand
**Work → Infrastructure → Demo server**. The vault contains Text, Secret, URL,
and SSH fields, colored tags, a second account, and a Personal group. The
encrypted demonstration SSH key is generated locally for each run and its
temporary source files are removed after import. Its passphrase is
`documentation-key-passphrase`. The host is a reserved `.invalid` address;
cancel the passphrase prompt instead of making a connection.

Capture these states as window-only PNG files, excluding other applications:

| Image | State |
| --- | --- |
| `unlock.png` | Locked demo vault, empty password input |
| `main-window.png` | Expanded groups and Demo server, masked Password |
| `entry-editor.png` | Demo server editor with tags and Text/Secret fields |
| `ssh-field.png` | Editor scrolled to the SSH field and key reference |
| `tag-filter.png` | Search for `demo`, Green selected, filter results visible |
| `ssh-keys.png` | Vault → SSH Keys, imported Demo SSH Key, empty private-key input |
| `ssh-passphrase.png` | Demo server's SSH connection passphrase prompt, input empty |
| `theme-settings.png` | Settings, theme selector and Liquid Glass switch |

The initial set was captured with Keepy 2.1.1 on macOS 26.

Keep screenshots focused on the relevant controls and readable at article
width. Leave secrets masked and private-key inputs empty. Use only the seeded
example values; check for personal paths or account details before committing.
Use a caption and descriptive alt text wherever an image is embedded. Retain
PNG compression and avoid unnecessary full-display captures. After replacing
images, rebuild and visually check the user guide and SSH page on desktop and
a narrow viewport.

Quit the demo application when finished. Its generated state remains in the
ignored `target/` directory and is never part of the documentation artifact.
