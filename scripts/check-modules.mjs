import { readdir, readFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const jsRoot = resolve(root, 'js');
const files = [];

async function walk(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const full = resolve(directory, entry.name);
    if (entry.isDirectory()) await walk(full);
    else if (entry.name.endsWith('.js')) files.push(full);
  }
}

await walk(jsRoot);
let missing = 0;
for (const file of files) {
  const source = await readFile(file, 'utf8');
  for (const match of source.matchAll(/from\s+['"](\.\.?\/[^'"]+)['"]/g)) {
    const target = resolve(dirname(file), match[1]);
    try { await readFile(target); }
    catch { console.error(`Importación inexistente: ${file.replace(root, '')} -> ${match[1]}`); missing++; }
  }
}
if (missing) process.exit(1);
console.log(`OK: ${files.length} módulos JavaScript y todas sus importaciones locales.`);
