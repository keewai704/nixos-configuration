import difflib
import os
from pathlib import Path

root = Path(__file__).resolve().parent
kernel = Path(os.environ['DSH_KERNEL_ROOT'])
web = Path(os.environ['DSH_UI_CHAT_CLIENT'])


def replace_once(source, before, after):
    if source.count(before) != 1:
        raise ValueError(f'Expected one source anchor: {before!r}')
    return source.replace(before, after, 1)


def patch(before, after, target):
    return ''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                        fromfile=f'a/{target}', tofile=f'b/{target}'))


meter_path = kernel / 'dsh-token-meter/lib/index.js'
meter = meter_path.read_text()
patched_meter = replace_once(meter, 'import { Service } from "@deepseek-ai/cordis";',
                             'import { scopedUsageProjectionDefinition } from "./cache-usage/projection.mjs";\nimport { Service } from "@deepseek-ai/cordis";')
patched_meter = replace_once(patched_meter,
                             '\t\tctx.sessionProjections.register(tokenUsageProjectionDefinition);',
                             '\t\tctx.sessionProjections.register(tokenUsageProjectionDefinition);\n\t\tctx.sessionProjections.register(scopedUsageProjectionDefinition);')
kernel_patch = patch(meter, patched_meter,
                     'lib/deepseek-harness/node_modules/@deepseek-ai/dsh-token-meter/lib/index.js')

schema = (root / 'schema.mjs').read_text().replace('export function', 'function')
for name in ['typert.host.js', 'typert.remote-client.js']:
    source = (kernel / 'dsh-api-session-controller/lib' / name).read_text()
    changed = replace_once(source, "import { z } from 'zod'",
                           "import { z } from 'zod'\n" + schema + '\nconst scopedUsageSchema = createScopedUsageSchemas(z).view;')
    anchor = "  'tokenUsage': z.object({"
    if changed.count(anchor) != 5:
        raise ValueError(f'Expected five tokenUsage schemas in {name}')
    changed = changed.replace(anchor, "  'scopedUsage': scopedUsageSchema.optional(),\n" + anchor)
    kernel_patch += patch(source, changed,
                          f'lib/deepseek-harness/node_modules/@deepseek-ai/dsh-api-session-controller/lib/{name}')

ui = web.read_text()
start = ui.index('\t\tconst UsagePill = ')
end = ui.index('\n\t\t//#endregion', start)
accounting = (root / 'accounting.mjs').read_text().split('export function usageBucket', 1)[0].replace('export ', '')
rollup = '\n'.join(line for line in (root / 'rollup.mjs').read_text().splitlines() if not line.startswith('import ')).replace('export ', '')
replacement = accounting + '\n' + rollup + '\n' + (root / 'usage-pill.js').read_text().rstrip()
ui_changed = ui[:start] + '\n'.join('\t\t' + line if line else '' for line in replacement.splitlines()) + ui[end:]
ui_changed = replace_once(ui_changed,
                          '\t\t\tconst statPillInject = () => ({ hooks: { performanceUsage } });',
                          '\t\t\tconst refreshScopedUsage = (id) => ctx.sessions.refreshProjections(id);\n'
                          '\t\t\tconst statPillInject = (sessionId) => ({\n'
                          '\t\t\t\thooks: { performanceUsage, scopedUsageSessions: ctx.sessions.list },\n'
                          '\t\t\t\tscopedUsageSessionId: sessionId, refreshScopedUsage\n'
                          '\t\t\t});')
web_patch = patch(ui, ui_changed,
                  'lib/node_modules/@deepseek-ai/dsh-web-app/node_modules/@deepseek-ai/dsh-client-ui-chat/lib/client.js')
remotes_path = web.parents[2] / 'dsh-api-remotes/lib/client.js'
remotes = remotes_path.read_text()
anchor = '\t\t//#region ../session-controller/lib/typert.remote-client.js'
remotes_changed = replace_once(remotes, anchor, anchor + '\n' +
                               '\n'.join('\t\t' + line if line else '' for line in schema.splitlines()) +
                               '\n\t\tconst scopedUsageSchema = createScopedUsageSchemas({ number, object, string, literal, boolean }).view;')
anchor = '"tokenUsage": object({'
if remotes_changed.count(anchor) != 5:
    raise ValueError('Expected five tokenUsage schemas in browser remotes')
remotes_changed = remotes_changed.replace(anchor, '"scopedUsage": scopedUsageSchema.optional(),\n\t\t\t\t\t' + anchor)
web_patch += patch(remotes, remotes_changed,
                   'lib/node_modules/@deepseek-ai/dsh-web-app/node_modules/@deepseek-ai/dsh-api-remotes/lib/client.js')

for name, content in [('kernel.patch', kernel_patch), ('web.patch', web_patch)]:
    target = root / name
    if target.exists():
        target.read_text()
    target.write_text(content)
