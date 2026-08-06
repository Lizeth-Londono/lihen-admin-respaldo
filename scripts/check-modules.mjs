import { readdir, readFile } from 'node:fs/promises';
import { resolve, dirname, extname } from 'node:path';
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

function extractExports(source) {
  const names = new Set();

  for (const match of source.matchAll(/export\s+(?:async\s+)?function\s+([A-Za-z_$][\w$]*)/g)) names.add(match[1]);
  for (const match of source.matchAll(/export\s+(?:const|let|var|class)\s+([A-Za-z_$][\w$]*)/g)) names.add(match[1]);
  if (/export\s+default\b/.test(source)) names.add('default');

  for (const match of source.matchAll(/export\s*\{([^}]+)\}/gs)) {
    for (const rawPart of match[1].split(',')) {
      const part = rawPart.trim();
      if (!part) continue;
      const alias = part.match(/^([A-Za-z_$][\w$]*)(?:\s+as\s+([A-Za-z_$][\w$]*))?/);
      if (alias) names.add(alias[2] || alias[1]);
    }
  }

  return names;
}

function localTarget(file, specifier) {
  const target = resolve(dirname(file), specifier);
  return extname(target) ? target : `${target}.js`;
}

await walk(jsRoot);

const sources = new Map();
const exportsByFile = new Map();
for (const file of files) {
  const source = await readFile(file, 'utf8');
  sources.set(file, source);
  exportsByFile.set(file, extractExports(source));
}

const errors = [];

for (const file of files) {
  const source = sources.get(file);
  const displayFile = file.replace(root, '');

  for (const match of source.matchAll(/import\s*\{([^}]+)\}\s*from\s*['"](\.?\.?\/[^'"]+)['"]/gs)) {
    const [, importBlock, specifier] = match;
    const target = localTarget(file, specifier);
    let targetSource;
    try {
      targetSource = await readFile(target, 'utf8');
    } catch {
      errors.push(`Importación inexistente: ${displayFile} -> ${specifier}`);
      continue;
    }

    if (!exportsByFile.has(target)) exportsByFile.set(target, extractExports(targetSource));
    const available = exportsByFile.get(target);
    for (const rawPart of importBlock.split(',')) {
      const importedName = rawPart.trim().split(/\s+as\s+/)[0];
      if (importedName && !available.has(importedName)) {
        errors.push(`Exportación inexistente: ${displayFile} importa "${importedName}" desde ${specifier}`);
      }
    }
  }

  for (const match of source.matchAll(/import\s+([A-Za-z_$][\w$]*)\s+from\s*['"](\.?\.?\/[^'"]+)['"]/g)) {
    const [, , specifier] = match;
    const target = localTarget(file, specifier);
    let targetSource;
    try {
      targetSource = await readFile(target, 'utf8');
    } catch {
      errors.push(`Importación inexistente: ${displayFile} -> ${specifier}`);
      continue;
    }
    if (!exportsByFile.has(target)) exportsByFile.set(target, extractExports(targetSource));
    if (!exportsByFile.get(target).has('default')) {
      errors.push(`Exportación default inexistente: ${displayFile} -> ${specifier}`);
    }
  }

  for (const match of source.matchAll(/(?:import\s*['"]|from\s*['"])(\.?\.?\/[^'"]+)['"]/g)) {
    const specifier = match[1];
    const target = localTarget(file, specifier);
    try { await readFile(target); }
    catch {
      const message = `Importación inexistente: ${displayFile} -> ${specifier}`;
      if (!errors.includes(message)) errors.push(message);
    }
  }
}

if (errors.length) {
  errors.forEach((error) => console.error(error));
  process.exit(1);
}

console.log(`OK: ${files.length} módulos JavaScript, rutas locales y exportaciones importadas.`);
