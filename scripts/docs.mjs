import { cp, mkdir, readFile, readdir, rm, stat, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { dirname, extname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const source = join(root, 'target/docs-source');
const output = join(root, 'target/docs-site');
const prefix = '/keepy/';
const origin = 'https://lyova24.github.io';

async function files(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(entries.map(entry => entry.isDirectory()
    ? files(join(directory, entry.name)) : [join(directory, entry.name)]));
  return nested.flat();
}

async function build() {
  // Only generated directories are replaced. Canonical Markdown stays in place.
  await rm(source, { recursive: true, force: true });
  await rm(output, { recursive: true, force: true });
  await cp(join(root, 'docs'), source, { recursive: true });
  for (const name of ['SECURITY.md', 'CHANGELOG.md']) {
    await cp(join(root, name), join(source, name));
  }
  await mkdir(join(source, '_assets'), { recursive: true });
  for (const name of ['wordmark.svg', 'icon.png']) {
    await cp(join(root, 'icons', name), join(source, '_assets', name));
  }
  const result = spawnSync(process.execPath, [
    join(root, 'node_modules/@diplodoc/cli/build/index.js'),
    'build', '-i', source, '-o', output,
  ], { cwd: root, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`Diplodoc build failed (${result.status})`);
  // Diplodoc 5.63.3's search template combines a root <base> with page-relative
  // bundle paths and a duplicate basename-only resources script. Normalize only
  // these generated search pages; keep the root base used by the search index.
  for (const page of (await files(join(output, '_search'))).filter(path => extname(path) === '.html')) {
    const html = await readFile(page, 'utf8');
    const fixed = html
      .replace(/((?:href|src)=["'])\.\.\/\.\.\/_bundle\//g, '$1_bundle/')
      .replace(/<script\b[^>]*\bsrc=["']\d+-resources\.js["'][^>]*><\/script>\s*/g, '');
    await writeFile(page, fixed);
  }
  await writeFile(join(output, '.nojekyll'), '');
}

const decode = value => value.replaceAll('&amp;', '&').replaceAll('&quot;', '"')
  .replaceAll('&#39;', "'").replaceAll('&lt;', '<').replaceAll('&gt;', '>');

async function check() {
  const pages = (await files(output)).filter(path => extname(path) === '.html');
  if (!pages.length) throw new Error('Build the documentation first: npm run docs:build');
  const contents = new Map(await Promise.all(pages.map(async path => [path, await readFile(path, 'utf8')])));
  const failures = [];
  let checked = 0;
  for (const [page, html] of contents) {
    const pageURL = new URL(prefix + relative(output, page).split(sep).join('/'), origin);
    const baseHref = html.match(/<base\b[^>]*\bhref=["']([^"']+)["']/)?.[1];
    const baseURL = baseHref ? new URL(decode(baseHref), pageURL) : pageURL;
    // <base> establishes the URL context; it is not a link relative to itself.
    const linkedHTML = html.replace(/<base\b[^>]*>/g, '');
    for (const match of linkedHTML.matchAll(/\b(?:href|src)=["']([^"']+)["']/g)) {
      const value = decode(match[1]);
      const url = new URL(value, baseURL);
      if (url.origin !== origin || !['http:', 'https:'].includes(url.protocol)) continue;
      const report = message => failures.push(`${relative(output, page)}: ${value} — ${message}`);
      if (!url.pathname.startsWith(prefix)) { report('escapes the /keepy/ deployment path'); continue; }
      let path = resolve(output, decodeURIComponent(url.pathname.slice(prefix.length)));
      if (!path.startsWith(output + sep) && path !== output) { report('escapes build output'); continue; }
      // GitHub Pages also serves page.html at the extensionless page URL.
      try {
        if ((await stat(path)).isDirectory()) path = join(path, 'index.html');
      } catch {
        if (!extname(path)) path += '.html';
      }
      try { if (!(await stat(path)).isFile()) throw new Error(); }
      catch { report('missing file'); continue; }
      if (url.hash && extname(path) === '.html') {
        const target = contents.get(path);
        const anchors = [...target.matchAll(/\b(?:id|name)=["']([^"']+)["']/g)].map(item => decode(item[1]));
        if (!anchors.includes(decodeURIComponent(url.hash.slice(1)))) report('missing anchor');
      }
      checked++;
    }
  }
  // README remains usable as source on GitHub, independently of the site.
  const readme = await readFile(join(root, 'README.md'), 'utf8');
  for (const match of readme.matchAll(/\]\(([^)]+)\)|<img\s+src="([^"]+)"/g)) {
    const href = match[1] ?? match[2];
    if (/^[a-z]+:|^#/i.test(href)) continue;
    try { await stat(resolve(root, href.split('#')[0])); }
    catch { failures.push(`README.md: ${href} — missing source file`); }
  }
  if (failures.length) throw new Error(failures.join('\n'));
  console.log(`Checked ${pages.length} pages and ${checked} local links/assets under ${prefix}.`);
}

async function preview() {
  await stat(join(output, 'index.html'));
  const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css',
    '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png',
    '.woff': 'font/woff', '.woff2': 'font/woff2', '.md': 'text/plain' };
  createServer(async (request, response) => {
    try {
      const url = new URL(request.url, 'http://localhost');
      if (url.pathname === '/' || url.pathname === '/keepy') {
        response.writeHead(302, { Location: prefix }); response.end(); return;
      }
      if (!url.pathname.startsWith(prefix)) throw new Error('Outside site');
      let path = resolve(output, decodeURIComponent(url.pathname.slice(prefix.length)));
      if (!path.startsWith(output + sep) && path !== output) throw new Error('Outside output');
      try { if ((await stat(path)).isDirectory()) path = join(path, 'index.html'); }
      catch { if (!extname(path)) path += '.html'; }
      const data = await readFile(path);
      response.writeHead(200, { 'Content-Type': types[extname(path)] ?? 'application/octet-stream' });
      response.end(data);
    } catch { response.writeHead(404); response.end('Not found'); }
  }).listen(5005, '127.0.0.1', () => console.log('Preview: http://127.0.0.1:5005/keepy/ (Ctrl-C to stop)'));
}

try {
  switch (process.argv[2]) {
    case 'build': await build(); break;
    case 'check': await check(); break;
    case 'preview': await preview(); break;
    default: throw new Error('Usage: node scripts/docs.mjs build|check|preview');
  }
} catch (error) { console.error(error.message); process.exitCode = 1; }
