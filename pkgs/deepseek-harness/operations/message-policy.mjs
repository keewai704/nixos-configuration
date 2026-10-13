export const name = 'message-policy';
export const inject = ['tools', 'systemPrompt'];

const OLD_CLIPS = [
  '<response clipped><NOTE>To save on context only part of this file has been shown to you. You should retry this tool after you have searched inside the file with `grep -n` in order to find the line numbers of what you are looking for.</NOTE>',
  '<response clipped><NOTE>To save on context only part of this file has been shown to you. You should retry this tool after you have searched inside the file with Select-String in order to find the line numbers of what you are looking for.</NOTE>',
];
export const CLIPPED_ADVICE = '<response clipped><NOTE>Only part of this command output is shown. If a log exists and read is available, inspect it with read using file_path, offset, and limit. Otherwise, rerun only if safe, saving or filtering the output.</NOTE>';
export const SEARCH_SCOPE = 'Returned paths refer to the command-execution filesystem; file tools must share it to read them.';
export const PLAN_SCOPE = 'Plan mode is guidance only; it does not block tool calls or change sandbox and approval settings.';
const ORIGINAL_READ = 'Use read on a matched file when you need surrounding context.';
const SCOPED_READ = 'Use read on a matched file for surrounding context only when read and search use the same filesystem.';

export function rewriteShellContent(content) {
  let changed = false;
  const result = content.map(block => {
    if (block.type !== 'text') return block;
    const suffix = OLD_CLIPS.find(text => block.text.endsWith(text));
    if (!suffix) return block;
    changed = true;
    return { ...block, text: block.text.slice(0, -suffix.length) + CLIPPED_ADVICE };
  });
  return changed ? result : content;
}

export function rewriteAssembly(assembly) {
  return {
    ...assembly,
    sections: assembly.sections.map(section => typeof section.text === 'string' && section.name === 'tool:grep'
      ? { ...section, text: section.text.replace(ORIGINAL_READ, SCOPED_READ) } : section),
    tools: assembly.tools.map(tool => {
      const extra = ['glob', 'grep'].includes(tool.name) ? SEARCH_SCOPE : tool.name === 'exit_plan_mode' ? PLAN_SCOPE : undefined;
      if (!extra || tool.description.includes(extra)) return tool;
      return { ...tool, description: `${tool.description} ${extra}` };
    }),
  };
}

export function apply(ctx) {
  ctx.on('system-prompt/assemble', async (_assembly, _context, next) => rewriteAssembly(await next()));
  ctx.on('tools/post-execute', async (exec, result, next) => {
    const decision = await next();
    if (!['bash', 'pwsh'].includes(exec.name) || decision.kind !== 'accept' || Object.hasOwn(decision, 'value')) return decision;
    const content = decision.content ?? result.content;
    const rewritten = rewriteShellContent(content);
    return rewritten === content ? decision : { ...decision, content: rewritten };
  });
}
