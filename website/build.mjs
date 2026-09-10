import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { homePage } from './home.mjs';
import { PRIVACY_HTML } from './privacy.mjs';

const root = new URL('./', import.meta.url);
const dist = new URL('dist/', root);
await rm(dist, { recursive: true, force: true });
await mkdir(dist, { recursive: true });
await cp(new URL('public/', root), dist, { recursive: true });
for (const name of ['workout', 'library']) await readFile(new URL(`public/assets/${name}.png`, root));
await writeFile(new URL('index.html', dist), homePage());
await mkdir(new URL('privacy/', dist), { recursive: true });
await writeFile(new URL('privacy/index.html', dist), PRIVACY_HTML);
console.log(`Built Très Fort website: ${fileURLToPath(dist)}`);
