const UsagePill = (0, react.memo)(function UsagePill({ useProjection, usePerformanceUsage, useScopedUsageSessions, scopedUsageSessionId, refreshScopedUsage, t }) {
  const mode = usePerformanceUsage(value => value);
  const usage = useProjection('scopedUsage');
  const catalog = useProjection('subagentCatalog');
  const sessions = useScopedUsageSessions(value => value);
  const rollup = (0, react.useMemo)(() => collectScopedUsage(scopedUsageSessionId, usage, catalog, sessions),
    [scopedUsageSessionId, usage, catalog, sessions]);
  const pendingReads = rollup.refresh.join('\n');
  (0, react.useEffect)(() => {
    for (const id of rollup.refresh) void refreshScopedUsage(id).catch(() => {});
  }, [pendingReads, refreshScopedUsage]);
  const chinese = t('message.turnUsage.title') === '本轮用量';
  const text = (english, translated) => chinese ? translated : english;
  const unknown = text('Unknown', '未知');
  const icon = (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.IconDatabaseOutlineRegular, {});
  const display = scopedUsagePresentation(rollup, formatCacheHitPercent);
  const totalText = rollup.overall.measuredCalls === 0 || display.total === null ? unknown
    : `${display.totalPartial ? '≥ ' : ''}${t('message.turnUsage.count', { count: formatTokens(display.total, t) })}`;
  const cacheText = display.cachePercent === null ? text('Cache unknown', '缓存未知')
    : `${text(display.cachePartial ? 'Measured cache' : 'Recorded cache', display.cachePartial ? '已测缓存' : '已记录缓存')} ${display.cachePercent}%`;
  const label = joined$1(`${text('Recorded', '已记录')} ${totalText}`, cacheText);
  const row = (key, name, value) => (0, react_jsx_runtime.jsxs)(react_jsx_runtime.Fragment, {
    children: [(0, react_jsx_runtime.jsx)('dt', { children: name }), (0, react_jsx_runtime.jsx)('dd', { children: value })],
  }, key);
  const bucketText = bucket => {
    const measured = bucket.measuredCalls;
    const amount = bucket.calls === 0 ? exactCount(0, t) : measured === 0 || bucket.totalTokens === null ? unknown
      : `${measured < bucket.calls ? '≥ ' : ''}${exactCount(bucket.totalTokens, t)}`;
    const cache = bucket.cacheEligibleInputTokens > 0 && bucket.cacheEligibleReadTokens !== null
      ? `${formatCacheHitPercent(bucket.cacheEligibleReadTokens, bucket.cacheEligibleInputTokens, 1)}%` : unknown;
    return `${amount} · ${measured}/${bucket.calls} ${text('attempts measured', '次尝试已计量')} · ${text('cache', '缓存')} ${cache}`;
  };
  const exactBucket = (value, missing) => value === null || missing === rollup.overall.calls && missing > 0
    || value === 0 && rollup.missing.length > 0 ? unknown
    : `${missing > 0 || rollup.missing.length > 0 ? '≥ ' : ''}${exactCount(value, t)}${missing > 0 ? ` (${missing} ${text('unknown', '未知')})` : ''}`;
  const childrenText = rollup.childSessions > 0 && rollup.measuredChildSessions === 0 ? unknown
    : `${rollup.measuredChildSessions < rollup.childSessions ? '≥ ' : ''}${bucketText(rollup.children)}`;
  const detailRows = [
    row('ordinary', text('This session · ordinary', '本会话 · 普通调用'), usage === undefined ? unknown : bucketText(rollup.ordinary)),
    row('summaries', text('This session · summaries', '本会话 · 摘要调用'), usage === undefined ? unknown : bucketText(rollup.summaries)),
    row('children', text('Descendants · ordinary + summaries', '后代会话 · 普通及摘要'), childrenText),
    row('coverage', text('Descendant sessions', '后代会话'), `${rollup.measuredChildSessions}/${rollup.childSessions}`),
    row('cache', text('Weighted cache · measured input', '加权缓存 · 已测输入'), display.cachePercent === null ? unknown : `${display.cachePercent}% (${rollup.overall.cacheMeasuredCalls}/${rollup.overall.calls} ${text('attempts', '次尝试')})`),
    row('input', t('message.turnUsage.input'), exactBucket(rollup.overall.uncachedInputTokens, rollup.overall.missingInput)),
    row('read', t('message.turnUsage.cacheRead'), exactBucket(rollup.overall.cacheReadTokens, rollup.overall.missingCacheRead)),
    row('write', t('message.turnUsage.cacheWrite'), exactBucket(rollup.overall.cacheWriteTokens, rollup.overall.missingCacheWrite)),
    row('output', t('message.turnUsage.output'), exactBucket(rollup.overall.outputTokens, rollup.overall.missingOutput)),
    row('failed', text('Failed / interrupted ordinary or summary attempts', '失败或中断的普通及摘要尝试'), rollup.overall.failedCalls),
    row('compaction-errors', text('Failed compactions · unknown cost', '失败压缩 · 未知用量'), `${rollup.failedCompactions} · ${rollup.unknownCompactions} ${text('unknown', '未知')}`),
    row('scope', text('Accounting scope', '统计范围'), text('Recorded provider usage, not a bill. Inherited history and embedded snapshots excluded; each descendant session counted once. Unlogged adapter retries may be absent. Legacy Codex cache writes are treated as not applicable for this deployment’s Responses adapter.', '已记录的提供方用量，非账单。排除继承历史与嵌入快照，每个后代会话仅计一次。未记录的适配器重试可能缺失。本部署的 Responses 适配器将旧版 Codex 缓存写入视为不适用。')),
  ];
  if (rollup.legacySummaries > 0) detailRows.push(row('legacy', text('Legacy summaries', '旧版摘要'), `${rollup.legacySummaries} · ${text('accepted summaries only; rejected or retried calls may be absent', '仅已接受摘要；被拒绝或重试调用可能缺失')}`));
  for (const child of rollup.rows.filter(item => item.parentId !== null)) {
    detailRows.push(row(`child-${child.id}`, (0, react_jsx_runtime.jsx)('span', { title: `${child.id} ← ${child.parentId}`, children: child.label }), bucketText(child.total)));
  }
  for (const missing of rollup.missing) detailRows.push(row(`missing-${missing.id}-${missing.reason}`, missing.id, `${unknown} (${missing.reason})`));
  if (rollup.missing.length > 0) detailRows.push(row('retry', text('Unavailable sessions', '不可用会话'), (0, react_jsx_runtime.jsx)('button', {
    type: 'button',
    onClick: () => {
      for (const item of rollup.missing) if (item.reason !== 'external') void refreshScopedUsage(item.id).catch(() => {});
    },
    children: text('Retry projection reads', '重试读取统计'),
  })));
  return (0, react_jsx_runtime.jsx)(DialogPill, {
    stat: 'usage', icon,
    label: mode === 'compact' ? cacheText : label,
    ariaLabel: `${text('Recorded session and descendant usage', '已记录的会话及后代用量')} · ${totalText} · ${cacheText}`,
    title: text('Recorded session + descendant usage', '已记录的会话及后代用量'),
    titleValue: totalText,
    children: (0, react_jsx_runtime.jsx)('dl', {
      className: stat_dialog_module_css_default.details,
      'data-session-stats-usage': true,
      'data-scoped-usage': true,
      'data-usage-partial': rollup.partial,
      'data-usage-child-sessions': rollup.childSessions,
      'data-usage-missing-sessions': rollup.missing.length,
      style: { maxHeight: '60vh', overflowY: 'auto', maxWidth: 'min(42rem, 80vw)', whiteSpace: 'normal', overflowWrap: 'anywhere' },
      children: detailRows,
    }),
  });
});
