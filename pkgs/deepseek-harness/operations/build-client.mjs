import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

export function buildClient() {
  const source = readFileSync(new URL('./client.js', import.meta.url), 'utf8');
  const rawFactory = readFileSync(new URL('./locale-ja-client.js', import.meta.url), 'utf8');
  if (!rawFactory.includes('export function createJapaneseLocalePlugin')) throw new Error('Unexpected Japanese plugin export');
  const factory = rawFactory.replace('export function createJapaneseLocalePlugin', 'function createJapaneseLocalePlugin');
  const rawControls = readFileSync(new URL('./advanced-client.js', import.meta.url), 'utf8');
  if (!rawControls.includes('export function createAdvancedOperations')) throw new Error('Unexpected operations controls export');
  const controls = rawControls.replace('export function createAdvancedOperations', 'function createAdvancedOperations');
  const data = JSON.parse(readFileSync(new URL('./locale-ja.json', import.meta.url), 'utf8'));
  const marker = '    function apply(ctx) {';
  if (source.split(marker).length !== 2) throw new Error('Expected one operations client entry point');
  return source.replace(marker, `${factory}\n${controls}\n    const AdvancedOperations = createAdvancedOperations(React, api);\n    const japaneseDictionaries = ${JSON.stringify(data)};\n${marker}\n      createJapaneseLocalePlugin(japaneseDictionaries).apply(ctx);`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const output = process.argv[2];
  if (!output || existsSync(output)) throw new Error('Specify a new client output path');
  writeFileSync(output, buildClient());
}
