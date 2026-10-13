import { chmod, cp, mkdir, readFile, realpath, writeFile } from 'node:fs/promises';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const originalPlanPackage = '@deepseek-ai/dsh-client-ui-plan';
export const replacementPlanPackage = '@keewai/dsh-ui-plan';
export const planTooltips = {
  en: {
    original: 'Plan mode on — click to turn off (/plan off)',
    corrected: 'Plan mode on — planning guidance, not read-only enforcement. Click to turn off (/plan off)',
  },
  zh: {
    original: '计划模式已开启 — 点击关闭（/plan off）',
    corrected: '计划模式已开启 — 仅提供规划指引，不强制只读；点击关闭（/plan off）',
  },
};

function replaceExact(source, before, after, count) {
  const occurrences = source.split(before).length - 1;
  if (occurrences !== count) throw new Error(`Expected ${count} occurrences of ${before}, found ${occurrences}`);
  return source.replaceAll(before, after);
}

export function transformPlanClient(manifest, source) {
  if (manifest.name !== originalPlanPackage || manifest.version !== '0.2.1-alpha.2') {
    throw new Error('Expected the pinned ui-plan package 0.2.1-alpha.2');
  }
  if (manifest.dsh?.client?.platform !== 'web' || !Array.isArray(manifest.dsh.client.inject)
    || manifest.exports?.['./client']?.default !== './lib/client.js') {
    throw new Error('Unexpected ui-plan client manifest');
  }
  if (source.includes('require.async(') || /\bimport\s*\(/.test(source)) {
    throw new Error('Unexpected split ui-plan client bundle');
  }
  let client = replaceExact(source, `id: "${originalPlanPackage}",`, `id: "${replacementPlanPackage}",`, 1);
  client = replaceExact(client, `tag.dataset.plugin = "${originalPlanPackage}";`, `tag.dataset.plugin = "${replacementPlanPackage}";`, 2);
  for (const stylesheet of ['PlanPreview.module.css', 'PlanModeControl.module.css']) {
    client = replaceExact(client, `"${originalPlanPackage}/${stylesheet}"`, `"${replacementPlanPackage}/${stylesheet}"`, 1);
  }
  for (const { original, corrected } of Object.values(planTooltips)) {
    const before = `"chip.on.title": ${JSON.stringify(original)}`;
    const after = `"chip.on.title": ${JSON.stringify(corrected)}`;
    const oldCount = client.split(before).length - 1;
    const newCount = client.split(after).length - 1;
    if (oldCount + newCount !== 1) throw new Error('Unknown or duplicated ui-plan tooltip');
    if (oldCount === 1) client = replaceExact(client, before, after, 1);
  }
  const stablePreview = `const previewId = "${originalPlanPackage}";`;
  if (client.split(stablePreview).length - 1 !== 1) throw new Error('Unexpected ui-plan preview identity');
  const packageManifest = structuredClone(manifest);
  packageManifest.name = replacementPlanPackage;
  return { manifest: packageManifest, client };
}

export async function buildPlanClientPackage(sourceDirectory, outputDirectory) {
  const sourceRoot = await realpath(sourceDirectory);
  const requestedOutput = resolve(outputDirectory);
  const outputRoot = join(await realpath(dirname(requestedOutput)), basename(requestedOutput));
  if (outputRoot === sourceRoot || outputRoot.startsWith(`${sourceRoot}/`)) {
    throw new Error('The replacement package must be outside the upstream package');
  }
  const manifest = JSON.parse(await readFile(join(sourceRoot, 'package.json'), 'utf8'));
  const source = await readFile(join(sourceRoot, 'lib/client.js'), 'utf8');
  const transformed = transformPlanClient(manifest, source);
  await mkdir(outputRoot);
  await cp(join(sourceRoot, 'lib'), join(outputRoot, 'lib'), {
    recursive: true,
    dereference: true,
    filter: path => path !== join(sourceRoot, 'lib/client.js'),
  });
  await chmod(join(outputRoot, 'lib'), 0o755);
  await writeFile(join(outputRoot, 'lib/client.js'), transformed.client, { flag: 'wx' });
  await writeFile(join(outputRoot, 'package.json'), `${JSON.stringify(transformed.manifest, null, 2)}\n`, { flag: 'wx' });
  return outputRoot;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [, , sourceDirectory, outputDirectory, ...extra] = process.argv;
  if (!sourceDirectory || !outputDirectory || extra.length) {
    throw new Error('Usage: node plan-client-build.mjs UPSTREAM_PACKAGE NEW_OUTPUT_DIRECTORY');
  }
  await realpath(dirname(resolve(outputDirectory)));
  await buildPlanClientPackage(sourceDirectory, outputDirectory);
}
