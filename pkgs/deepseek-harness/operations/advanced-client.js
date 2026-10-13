export function createAdvancedOperations(React, api) {
  const h = React.createElement;
  const maxBytes = 32768;
  const limitKeys = ['maxRequests', 'maxChildren', 'maxConcurrentChildren', 'maxOutputTokens', 'maxCostMicros', 'deadlineAt'];
  const en = {
    title: 'Checkpoint & budget controls', load: 'Load controls', refresh: 'Refresh controls', choose: 'Select…',
    access: 'These are authenticated same-origin operator controls, not cryptographic proof of a human gesture. Native approval policy, including never, is unchanged. No execution or mutation occurs merely by opening this panel. Closing it aborts HTTP requests, not execution already accepted by the server.',
    checkpoints: 'Durable checkpoints', root: 'Live checkpoint root', identity: 'Root identity', run: 'Owned checkpoint run', details: 'Load selected run details',
    checkpointHint: 'Only runs with this exact rootId are listed. The server also checks the live root identity. Enter provider and model manually from the selected root’s current route or allowed child-model routes; the listing does not advertise model choices.',
    draft: 'Create a draft', draftId: 'New checkpoint ID', graph: 'Graph JSON', draftPhrase: 'Draft confirmation', create: 'Create draft only',
    graphHint: 'Enter {"nodes":[{"id":"…","deps":[],"provider":"…","model":"…","prompt":"…"}]}. All five node fields are required; use your own route and prompt, not the ellipses. At most 32 nodes. Optional graph fields: maxAttempts, nodeTimeoutMs, runTimeoutMs. Prompts are stored privately. Creating a draft never starts it.',
    action: 'Checkpoint action', start: 'Start', resume: 'Resume', cancel: 'Cancel run', retry: 'Prepare retry', node: 'Failed or ambiguous node',
    actionPhrase: 'Action confirmation', retryPhrase: 'Retry confirmation', execute: 'Submit checkpoint action',
    checkpointRisk: 'Start/resume can dispatch model work and cause costs or side effects. Resume dispatches only dependency-ready pending nodes and reuses completed results. Ambiguous work is never automatically replayed. Before retrying, verify child sessions, running jobs and external effects. Retry only prepares a new attempt; resume requires a separate confirmation. Cancellation cannot undo effects or prove quiescence.',
    exact: 'Type the exact phrase shown inside the quotes, including all spaces; do not type the quotes.',
    budgets: 'Root budgets', budgetRoot: 'Live budget root', limits: 'Replacement limits JSON', budgetPhrase: 'Budget confirmation', configure: 'Apply budget limits',
    budgetHint: 'This replaces the entire limits object; omitted limits are removed, and {} removes all configurable caps. Use only advertised limit names and nonnegative safe integers. deadlineAt is Unix time in milliseconds. Configuration requires a quiescent root without outstanding work.',
    cost: 'Tracking and request/child caps are distinct from hard output/cost caps. Claude has no supported hard output/cost guarantee here. Hard output/cost limits require backend-audited routes and operator configuration; unsupported routes are refused, not silently protected. Unknown pricing is not zero. Input billing bounds are operator assumptions, not measured estimates or provider guarantees.',
    capabilities: 'Reported capabilities', consumption: 'Current consumption and reservations', allowed: 'Advertised configurable limits',
    reconcile: 'Reconcile ambiguous reservations', reconcileHint: 'First independently verify execution quiescence: check jobs, child sessions and external executors, and ensure the selected work cannot continue. This UI cannot prove that. Reconciliation retains the FULL reserved output/cost charge for requests; it does not zero charges, erase history, or make unknown billing known. Child selections use reservation record IDs, not child session IDs. Nothing is preselected.',
    requestRecord: 'Request reservation', childRecord: 'Child reservation', quiescent: 'I independently verified execution quiescence for every selected reservation',
    fullReservation: 'If selected, retain this request’s full output_reserved and cost_reserved charge (output tokens and cost micros). These are reserved amounts, not a known final bill; unknown pricing remains unknown.',
    reconcilePhrase: 'Reconciliation confirmation', reconcileSubmit: 'Reconcile with full reserved charge', noAmbiguous: 'No ambiguous reservations in this snapshot.',
    stale: 'A request failed or its outcome is uncertain. Refresh current state before another mutation. Confirmation text is retained; verify the latest revision and effects before confirming again. No automatic retry occurs.',
    failure: 'Controls error', invalidJson: 'Enter a JSON object.', invalidGraph: 'Use 1–32 nodes with explicit valid id, deps, provider, model and prompt fields.',
    invalidId: 'Use a new ID of 1–128 characters: letters, digits, underscore, dot, colon or hyphen; begin with a letter or digit.',
    invalidLimits: 'Limits must be a subset of the advertised names, with nonnegative safe integer values.', tooLarge: 'The complete JSON request must not exceed 32 KiB (UTF-8).',
    confirmation: 'Exact current confirmation is required.', invalidState: 'Selection or revision changed. Refresh and review current state.', invalidResponse: 'Unexpected server response. Refresh before acting.',
    draftSaved: 'Draft saved; not started.', retrySaved: 'New pending attempt prepared; not resumed.', activated: 'Activation accepted; this is not a completion guarantee. Refresh to inspect execution.',
    cancelled: 'Cancellation response received. Refresh and verify remaining work and effects.', budgetSaved: 'Budget configuration accepted by the server.', reconciled: 'Reconciliation accepted with full reserved charge; unknown billing remains unknown.',
    result: 'Server response metadata', metadata: 'Selected run metadata (prompts and results omitted)', emptyRoots: 'No live roots reported.', revision: 'Revision',
    deliveries: 'Scheduled delivery recovery', delivery: 'Original delivery obligation', deliveryPhrase: 'Delivery retry confirmation', deliveryRetry: 'Retry original delivery', noDeliveries: 'No delivery obligations reported.',
    deliveryHint: 'Manual retry resumes the original pending intent with the same delivery ID and immutable text; it does not create a new reminder. Verify the session and any external effects before retrying. Native accepted or canceled evidence stops reinsertion. Input acceptance is not exactly-once execution or proof that external effects completed. Each recovery generation has at most 5 automatic attempts, with at most 100 manual recovery generations. At most 100 obligations are displayed; no retry is automatic in this UI.',
    deliveryUnavailable: 'This snapshot does not permit retry (for example, in flight, accepted, canceled, or the recovery limit reached). Refresh to inspect current state.',
    deliverySaved: 'The server returned delivery recovery metadata. This is not proof of execution or exactly-once effects. Reload before any further delivery retry.',
    deliveryReload: 'Reload controls to inspect the latest delivery state before retrying. A failed or uncertain request is never automatically repeated.',
  };
  const ja = {
    title: 'チェックポイントと予算の操作', load: '操作情報を読み込む', refresh: '操作情報を再読み込み', choose: '選択…',
    access: '認証済み・同一オリジンの運用者向け操作です。人間の操作を暗号学的に証明するものではありません。never を含むネイティブ承認ポリシーは変更しません。この画面を開くだけでは実行・変更しません。画面を閉じるとHTTP要求は中断しますが、サーバーが受理済みの実行は止まりません。',
    checkpoints: '永続チェックポイント', root: '稼働中のチェックポイントルート', identity: 'ルート識別情報', run: '所有するチェックポイント', details: '選択した実行の詳細を読み込む',
    checkpointHint: 'rootId が完全一致する実行だけを表示します。サーバーは稼働中ルートの識別情報も検証します。選択ルートの現在の経路、または許可された子モデル経路から provider と model を手入力してください。この一覧にはモデル候補の情報はありません。',
    draft: '下書きを作成', draftId: '新しいチェックポイントID', graph: 'グラフJSON', draftPhrase: '下書き作成の確認文字列', create: '下書きのみ作成',
    graphHint: '{"nodes":[{"id":"…","deps":[],"provider":"…","model":"…","prompt":"…"}]} を入力します。ノードの5項目はすべて必須です。「…」ではなく自分の経路・指示を入力してください。最大32ノード。任意のグラフ項目: maxAttempts、nodeTimeoutMs、runTimeoutMs。指示は非公開で保存され、下書き作成では実行を開始しません。',
    action: 'チェックポイント操作', start: '開始', resume: '再開', cancel: '実行を中止', retry: '再試行を準備', node: '失敗・結果不明のノード',
    actionPhrase: '操作の確認文字列', retryPhrase: '再試行の確認文字列', execute: 'チェックポイント操作を送信',
    checkpointRisk: '開始・再開ではモデル処理が動き、費用や外部への変更が発生し得ます。再開は依存が完了した待機ノードのみを実行し、完了済みの結果は再利用します。結果不明の処理は自動再実行しません。再試行前に子セッション・稼働ジョブ・外部への変更を確認してください。再試行は新しい試行の準備のみで、再開には別の確認が必要です。中止しても変更は取り消せず、実行停止の証明にはなりません。',
    exact: '引用符の内側の文字列を、空白も含めて完全一致で入力してください。引用符自体は入力しません。',
    budgets: 'ルート予算', budgetRoot: '稼働中の予算ルート', limits: '置換する上限JSON', budgetPhrase: '予算の確認文字列', configure: '予算上限を適用',
    budgetHint: '上限オブジェクト全体を置き換えます。省略した上限は解除し、{} は設定可能な上限をすべて解除します。提示された項目名と0以上の安全な整数のみ指定できます。deadlineAt はUNIX時刻（ミリ秒）です。設定には未完了処理がなく、実行停止を確認したルートが必要です。',
    cost: '使用量の記録・リクエスト数・子の数の上限と、出力・費用の厳密な上限は別です。ここではClaudeの厳密な出力・費用上限は保証しません。厳密な出力・費用上限にはバックエンドが監査した経路と運用者の設定が必要で、未対応経路は保護したことにせず拒否します。料金不明はゼロではありません。入力課金の上界は運用者の仮定で、実測推定やプロバイダーの保証ではありません。',
    capabilities: '報告された対応機能', consumption: '現在の消費量と予約量', allowed: '設定可能と報告された上限',
    reconcile: '結果不明の予約を精算', reconcileHint: '先にジョブ・子セッション・外部実行基盤を独立して確認し、選択した処理が継続しないことを検証してください。この画面では実行停止を証明できません。精算してもリクエストの予約済み出力・費用は全額計上します。請求をゼロにしたり履歴を消したり、料金不明を既知にしたりはしません。子の選択は子セッションIDではなく予約レコードIDを使います。自動選択はしません。',
    requestRecord: 'リクエスト予約', childRecord: '子の予約', quiescent: '選択したすべての予約について実行停止を独立して確認しました',
    fullReservation: '選択すると、このリクエストの output_reserved（出力トークン）・cost_reserved（費用のマイクロ単位）を全額計上します。これらは予約量で、確定した最終請求額ではありません。料金不明は不明のままです。',
    reconcilePhrase: '精算の確認文字列', reconcileSubmit: '予約全額を計上して精算', noAmbiguous: 'このスナップショットに結果不明の予約はありません。',
    stale: 'リクエストが失敗したか、結果が不明です。次の変更前に最新状態を再読み込みしてください。確認文字列は保持しています。最新リビジョンと外部への影響を確認してから再確定してください。自動再試行は行いません。',
    failure: '操作エラー', invalidJson: 'JSONオブジェクトを入力してください。', invalidGraph: '有効な id・deps・provider・model・prompt を明示した1〜32ノードを指定してください。',
    invalidId: 'IDは英数字で始まり、英数字・アンダースコア・ピリオド・コロン・ハイフンの1〜128文字にしてください。',
    invalidLimits: '上限は提示された項目の一部または全部とし、値は0以上の安全な整数にしてください。', tooLarge: 'JSONリクエスト全体はUTF-8で32 KiB以下にしてください。',
    confirmation: '現在の確認文字列との完全一致が必要です。', invalidState: '選択またはリビジョンが変わりました。再読み込みして最新状態を確認してください。', invalidResponse: 'サーバー応答が想定外です。操作前に再読み込みしてください。',
    draftSaved: '下書きを保存しました。実行は開始していません。', retrySaved: '新しい試行を待機状態で準備しました。再開はしていません。', activated: '開始・再開の要求を受理しました。完了の保証ではありません。再読み込みして実行状態を確認してください。',
    cancelled: '中止の応答を受信しました。再読み込みし、残る処理と外部への影響を確認してください。', budgetSaved: 'サーバーが予算設定を受理しました。', reconciled: '予約全額の計上で精算を受理しました。料金不明の状態は変わりません。',
    result: 'サーバー応答のメタデータ', metadata: '選択した実行のメタデータ（指示・結果は非表示）', emptyRoots: '稼働中のルートが報告されていません。', revision: 'リビジョン',
    deliveries: 'スケジュール配信の復旧', delivery: '元の配信義務', deliveryPhrase: '配信再試行の確認文字列', deliveryRetry: '元の配信を再試行', noDeliveries: '配信義務は報告されていません。',
    deliveryHint: '手動再試行は、同じ配信ID・変更不可の本文で元の未処理の意図を再開します。新しいリマインダーは作成しません。再試行前にセッションと外部への影響を確認してください。ネイティブ側に受理済み・中止済みの証拠がある場合は再挿入しません。入力の受理は、一度だけの実行や外部処理の完了を証明しません。復旧世代ごとの自動試行は最大5回、手動復旧世代は最大100回です。配信義務は最大100件表示し、この画面では自動再試行しません。',
    deliveryUnavailable: 'このスナップショットでは再試行できません（処理中、受理済み、中止済み、復旧上限到達など）。再読み込みして最新状態を確認してください。',
    deliverySaved: '配信復旧のメタデータを受信しました。実行や外部処理の一度限りの完了を証明するものではありません。次の配信再試行前に再読み込みしてください。',
    deliveryReload: '再試行前に操作情報を再読み込みし、最新の配信状態を確認してください。失敗・結果不明の要求は自動再送しません。',
  };
  const buttonStyle = { border: '1px solid var(--border, #8885)', borderRadius: 6, padding: '6px 12px', background: 'transparent', color: 'inherit', font: 'inherit' };
  const cardStyle = { border: '1px solid var(--border, #8885)', borderRadius: 8, padding: 14, marginBlock: 12 };
  const preStyle = { whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', maxHeight: 280, overflowY: 'auto', fontSize: 12 };
  const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
  const identifier = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/.test(value);
  const revision = value => Number.isSafeInteger(value) && value > 0;
  const pick = (value, keys) => Object.fromEntries(keys.filter(key => value?.[key] !== undefined).map(key => [key, value[key]]));
  const runMetadata = value => ({
    ...pick(value, ['id', 'rootId', 'status', 'revision', 'createdAt', 'updatedAt', 'deadlineAt', 'backend', 'maxAttempts', 'attemptsStarted', 'nodeTimeoutMs', 'runTimeoutMs']),
    nodes: value.nodes.map(node => ({ ...pick(node, ['id', 'deps', 'provider', 'model', 'status', 'attempt']), attempts: (node.attempts ?? []).map(attempt => pick(attempt, ['attempt', 'status', 'childId', 'startedAt', 'finishedAt'])) })),
    ...(value.authorization ? { authorization: pick(value.authorization, ['actor', 'action', 'rootId', 'priorRevision', 'confirmation']) } : {}),
  });
  const budgetMetadata = value => pick(value, ['rootSessionId', 'revision', 'limits', 'requests', 'children', 'activeChildren', 'ambiguousChildren', 'ambiguousRequests', 'unknownCostRequests', 'reserved', 'usage', 'accountedOutputTokens', 'accountedCostMicros']);
  const deliveryMetadata = value => ({
    ...pick(value, ['id', 'sessionId', 'revision', 'attempts', 'totalAttempts', 'recoveryCount', 'retryAt', 'deliveredAt', 'inFlight', 'retryable']),
    members: value.members.map(member => pick(member, ['taskId', 'scheduledAt', 'nextScheduledAt'])),
  });
  return function AdvancedOperations({ locale }) {
    const t = locale === 'ja' ? ja : en;
    const [checkpoints, setCheckpoints] = React.useState(null);
    const [budgets, setBudgets] = React.useState(null);
    const [deliveries, setDeliveries] = React.useState(null);
    const [deliveryId, setDeliveryId] = React.useState('');
    const [deliveryPhrase, setDeliveryPhrase] = React.useState('');
    const [deliveryStale, setDeliveryStale] = React.useState(false);
    const [rootId, setRootId] = React.useState('');
    const [runId, setRunId] = React.useState('');
    const [detail, setDetail] = React.useState(null);
    const [budgetId, setBudgetId] = React.useState('');
    const [form, setForm] = React.useState({ draftId: '', graph: '', draftPhrase: '', action: '', nodeId: '', actionPhrase: '', retryPhrase: '', limits: '', budgetPhrase: '', requestIds: [], childIds: [], quiescent: false, reconcilePhrase: '' });
    const [stale, setStale] = React.useState({ checkpoint: false, budget: false });
    const [busy, setBusy] = React.useState(false);
    const [error, setError] = React.useState('');
    const [result, setResult] = React.useState(null);
    const request = React.useRef(null);
    const patch = changes => setForm(previous => ({ ...previous, ...changes }));
    React.useEffect(() => () => request.current?.abort(), []);
    const root = checkpoints?.roots.find(row => row.id === rootId);
    const ownedRuns = checkpoints?.runs.filter(row => row.rootId === rootId) ?? [];
    const selected = root && detail?.rootId === rootId && detail.id === runId && ownedRuns.some(row => row.id === runId) ? detail : null;
    const budget = budgets?.roots.find(row => row.rootSessionId === budgetId);
    const allowedLimits = limitKeys.filter(key => budgets?.capabilities?.limits?.includes(key));
    const requestRecords = budget?.requestRecords.filter(row => row.state === 'ambiguous' && row.root_id === budgetId) ?? [];
    const childRecords = budget?.childRecords.filter(row => row.state === 'ambiguous' && row.root_id === budgetId) ?? [];
    const selectedRequests = form.requestIds.filter(id => requestRecords.some(row => row.id === id));
    const selectedChildren = form.childIds.filter(id => childRecords.some(row => row.id === id));
    const retryNodes = selected?.nodes.filter(node => ['ambiguous', 'failed'].includes(node.status)) ?? [];
    const retryNode = retryNodes.find(node => node.id === form.nodeId);
    const actions = selected ? {
      start: selected.status === 'draft', resume: ['paused', 'ambiguous', 'failed'].includes(selected.status),
      retry: ['paused', 'ambiguous', 'failed'].includes(selected.status) && retryNodes.length > 0,
      cancel: !['completed', 'cancelled'].includes(selected.status),
    } : {};
    const draftRequired = root ? `CREATE CHECKPOINT ${root.id} 0` : '';
    const actionRequired = selected && form.action ? `${form.action.toUpperCase()} CHECKPOINT ${selected.id} ${selected.revision}` : '';
    const retryRequired = selected && retryNode ? `RETRY ${selected.id}/${retryNode.id}/${retryNode.attempt} @${selected.revision}` : '';
    const budgetRequired = budget ? `BUDGET ${budget.rootSessionId} ${budget.revision}` : '';
    const reconcileRequired = budget ? `RECONCILE ${budget.rootSessionId} ${budget.revision} ${[...selectedRequests].sort().join(',')} ${[...selectedChildren].sort().join(',')}` : '';
    const matches = (value, expected) => Boolean(expected) && value === expected;
    const delivery = deliveries?.find(row => row.id === deliveryId);
    const deliveryRequired = delivery ? `RETRY DELIVERY ${delivery.id} ${delivery.revision}` : '';
    const deliveryRetryable = delivery?.retryable === true && delivery.inFlight === false && delivery.deliveredAt == null;
    const canRetryDelivery = deliveryRetryable && !deliveryStale && !stale.delivery && matches(deliveryPhrase, deliveryRequired);
    const canAct = !stale.checkpoint && actions[form.action] && matches(form.actionPhrase, actionRequired)
      && (form.action !== 'retry' || (revision(retryNode?.attempt) && matches(form.retryPhrase, retryRequired)));
    const canReconcile = !stale.budget && form.quiescent && selectedRequests.length + selectedChildren.length > 0
      && selectedRequests.length + selectedChildren.length <= 100 && matches(form.reconcilePhrase, reconcileRequired);
    const fail = key => { throw new Error(t[key]); };
    const parseObject = text => { let value; try { value = JSON.parse(text); } catch { fail('invalidJson'); } if (!object(value)) fail('invalidJson'); return value; };
    const validDetail = (value, owner, id) => {
      if (!object(value) || value.id !== id || value.rootId !== owner || !revision(value.revision) || !Array.isArray(value.nodes)) fail('invalidResponse');
      return value;
    };
    const validBudget = (value, id) => {
      if (!object(value) || value.rootSessionId !== id || !revision(value.revision) || !object(value.limits) || !Array.isArray(value.requestRecords) || !Array.isArray(value.childRecords)) fail('invalidResponse');
      return value;
    };
    const validDelivery = value => {
      if (!object(value) || typeof value.id !== 'string' || !value.id || typeof value.sessionId !== 'string'
        || typeof value.revision !== 'string' || !value.revision || typeof value.retryable !== 'boolean' || typeof value.inFlight !== 'boolean'
        || !Array.isArray(value.members) || value.members.some(member => !object(member))) fail('invalidResponse');
      return deliveryMetadata(value);
    };
    async function run(work) {
      if (request.current) return;
      const controller = new AbortController();
      request.current = controller;
      setBusy(true); setError(''); setResult(null);
      try { await work(controller.signal); }
      catch (failure) { if (!controller.signal.aborted) setError(`${t.failure}: ${failure instanceof Error ? failure.message : t.invalidResponse}`); }
      finally { if (request.current === controller) request.current = null; if (!controller.signal.aborted) setBusy(false); }
    }
    async function loadDetail(owner, id, signal) {
      const query = new URLSearchParams({ id, ownerSessionId: owner.id, ownerIdentity: owner.identity });
      const value = await api(`checkpoints?${query}`, undefined, signal);
      signal.throwIfAborted();
      return validDetail(value, owner.id, id);
    }
    async function refreshCheckpoints(signal) {
      setStale(previous => ({ ...previous, checkpoint: true }));
      const value = await api('checkpoints', undefined, signal);
      signal.throwIfAborted();
      if (!Array.isArray(value?.roots) || !Array.isArray(value.runs) || value.roots.some(row => typeof row.id !== 'string' || typeof row.identity !== 'string')) fail('invalidResponse');
      setCheckpoints(value);
      const current = value.roots.find(row => row.id === rootId);
      if (root && (!current || current.identity !== root.identity)) {
        setRootId(''); setRunId(''); setDetail(null); patch({ draftPhrase: '', actionPhrase: '', retryPhrase: '' });
      } else if (root && current && runId && value.runs.some(row => row.id === runId && row.rootId === rootId)) {
        setDetail(await loadDetail(current, runId, signal));
      } else if (runId) { setRunId(''); setDetail(null); }
      signal.throwIfAborted();
      setStale(previous => ({ ...previous, checkpoint: false }));
    }
    async function refreshBudgets(signal) {
      setStale(previous => ({ ...previous, budget: true }));
      const value = await api('budgets', undefined, signal);
      signal.throwIfAborted();
      if (!Array.isArray(value?.roots) || !Array.isArray(value.capabilities?.limits)) fail('invalidResponse');
      value.roots.forEach(row => validBudget(row, row.rootSessionId));
      setBudgets(value); patch({ quiescent: false });
      if (budgetId && !value.roots.some(row => row.rootSessionId === budgetId)) setBudgetId('');
      setStale(previous => ({ ...previous, budget: false }));
    }
    async function refreshDeliveries(signal) {
      setDeliveryStale(true);
      const value = await api('deliveries', undefined, signal);
      signal.throwIfAborted();
      if (value?.version !== 1 || !Array.isArray(value.obligations)) fail('invalidResponse');
      const rows = value.obligations.slice(0, 100).map(validDelivery);
      if (new Set(rows.map(row => row.id)).size !== rows.length) fail('invalidResponse');
      setDeliveries(rows);
      if (deliveryId && !rows.some(row => row.id === deliveryId)) setDeliveryId('');
      setDeliveryStale(false);
      setStale(previous => ({ ...previous, delivery: false }));
    }
    const refresh = () => run(async signal => {
      const results = await Promise.allSettled([refreshCheckpoints(signal), refreshBudgets(signal), refreshDeliveries(signal)]);
      signal.throwIfAborted();
      const failures = results.filter(value => value.status === 'rejected');
      if (failures.length) throw new Error(failures.map(value => value.reason?.message ?? t.invalidResponse).join(' · '));
    });
    function mutate(kind, path, build, accept) {
      return run(async signal => {
        const body = build();
        if (new TextEncoder().encode(JSON.stringify(body)).length > maxBytes) fail('tooLarge');
        try {
          const value = await api(path, body, signal);
          signal.throwIfAborted();
          accept(value);
        } catch (failure) {
          if (!signal.aborted) setStale(previous => ({ ...previous, [kind]: true }));
          throw failure;
        }
      });
    }
    function acceptCheckpoint(value, id, message) {
      validDetail(value, root.id, id);
      setDetail(value); setRunId(id);
      setCheckpoints(previous => ({ ...previous, runs: [pick(value, ['id', 'rootId', 'status', 'revision']), ...previous.runs.filter(row => row.id !== id)] }));
      patch({ draftPhrase: '', actionPhrase: '', retryPhrase: '', action: '', nodeId: '' });
      setResult({ message, metadata: runMetadata(value) });
    }
    function createDraft() {
      return mutate('checkpoint', 'checkpoints/action', () => {
        if (!root || stale.checkpoint) fail('invalidState');
        if (!matches(form.draftPhrase, draftRequired)) fail('confirmation');
        if (!identifier(form.draftId)) fail('invalidId');
        const graph = parseObject(form.graph);
        if (!Array.isArray(graph.nodes) || graph.nodes.length < 1 || graph.nodes.length > 32 || graph.nodes.some(node => !object(node) || !identifier(node.id)
          || !Array.isArray(node.deps) || node.deps.some(dep => !identifier(dep)) || ['provider', 'model', 'prompt'].some(key => typeof node[key] !== 'string' || !node[key].trim() || node[key].trim() === '…'))) fail('invalidGraph');
        return { action: 'create', ownerSessionId: root.id, ownerIdentity: root.identity, id: form.draftId, graph, confirmation: form.draftPhrase };
      }, value => acceptCheckpoint(value, form.draftId, 'draftSaved'));
    }
    function checkpointAction() {
      return mutate('checkpoint', 'checkpoints/action', () => {
        if (!canAct) fail('confirmation');
        return { action: form.action, ownerSessionId: root.id, ownerIdentity: root.identity, id: selected.id, revision: selected.revision, confirmation: form.actionPhrase,
          ...(form.action === 'retry' ? { nodeId: retryNode.id, attempt: retryNode.attempt, retryConfirmation: form.retryPhrase } : {}) };
      }, value => acceptCheckpoint(value, selected.id, form.action === 'retry' ? 'retrySaved' : form.action === 'cancel' ? 'cancelled' : 'activated'));
    }
    function acceptBudget(value, message) {
      validBudget(value, budgetId);
      setBudgets(previous => ({ ...previous, roots: previous.roots.map(row => row.rootSessionId === budgetId ? value : row) }));
      patch({ budgetPhrase: '', reconcilePhrase: '', requestIds: [], childIds: [], quiescent: false });
      setResult({ message, metadata: budgetMetadata(value) });
    }
    function configureBudget() {
      return mutate('budget', 'budgets/configure', () => {
        if (!budget || stale.budget) fail('invalidState');
        if (!matches(form.budgetPhrase, budgetRequired)) fail('confirmation');
        const limits = parseObject(form.limits);
        if (Object.entries(limits).some(([key, value]) => !allowedLimits.includes(key) || !Number.isSafeInteger(value) || value < 0)) fail('invalidLimits');
        return { rootSessionId: budgetId, revision: budget.revision, limits, confirmation: form.budgetPhrase };
      }, value => acceptBudget(value, 'budgetSaved'));
    }
    function reconcileBudget() {
      return mutate('budget', 'budgets/reconcile', () => {
        if (!canReconcile) fail('confirmation');
        return { rootSessionId: budgetId, revision: budget.revision, requestIds: [...selectedRequests].sort(), childIds: [...selectedChildren].sort(), confirmation: form.reconcilePhrase };
      }, value => acceptBudget(value, 'reconciled'));
    }
    function retryDelivery() {
      return mutate('delivery', 'deliveries/retry', () => {
        if (!canRetryDelivery) fail('confirmation');
        return { id: delivery.id, expectedRevision: delivery.revision, confirmation: deliveryPhrase };
      }, value => {
        const updated = validDelivery(value?.obligation);
        if (updated.id !== delivery.id || updated.sessionId !== delivery.sessionId) fail('invalidResponse');
        setDeliveries(previous => previous.map(row => row.id === updated.id ? updated : row));
        setDeliveryPhrase(''); setDeliveryStale(true);
        setResult({ message: 'deliverySaved', metadata: updated });
      });
    }
    const button = (label, onClick, disabled = false) => h('button', { type: 'button', style: buttonStyle, disabled: busy || disabled, onClick }, label);
    const field = (label, tag, props, children) => h('label', { style: { display: 'block', marginBlock: 10 } }, label,
      h(tag, { 'aria-label': label, style: { ...buttonStyle, display: 'block', width: '100%', boxSizing: 'border-box' }, disabled: busy, ...props }, children));
    const text = (label, key, extra = {}) => field(label, 'input', { value: form[key], autoComplete: 'off', spellCheck: false, onChange: event => patch({ [key]: event.target.value }), ...extra });
    const options = rows => [h('option', { key: '', value: '' }, t.choose), ...rows.map(([value, label, disabled]) => h('option', { key: value, value, disabled }, label))];
    const phrase = (label, key, required) => h('div', null, h('p', null, t.exact), h('pre', { style: preStyle }, `"${required}"`), text(label, key));
    const json = (label, value) => h('details', null, h('summary', null, label), h('pre', { style: preStyle }, JSON.stringify(value, null, 2)));
    const toggle = (key, id, checked) => setForm(previous => ({ ...previous, [key]: checked ? [...new Set([...previous[key], id])] : previous[key].filter(value => value !== id), reconcilePhrase: '', quiescent: false }));
    return h('section', { 'aria-label': t.title, 'aria-busy': busy, style: { marginBlock: 20, lineHeight: 1.6 } },
      h('h3', null, t.title), h('p', null, t.access), button(checkpoints || budgets || deliveries ? t.refresh : t.load, refresh),
      error && h('p', { role: 'alert' }, error),
      !busy && (stale.checkpoint || stale.budget || stale.delivery) && h('p', { role: 'status' }, t.stale),
      result && h('div', { role: 'status' }, h('p', null, t[result.message]), json(t.result, result.metadata)),
      checkpoints && h('article', { style: cardStyle },
        h('h4', null, t.checkpoints), h('p', null, t.checkpointHint),
        !checkpoints.roots.length && h('p', null, t.emptyRoots),
        field(t.root, 'select', { value: rootId, onChange: event => {
          setRootId(event.target.value); setRunId(''); setDetail(null); setResult(null);
          patch({ draftPhrase: '', action: '', nodeId: '', actionPhrase: '', retryPhrase: '' });
        } }, options(checkpoints.roots.map(row => [row.id, row.id]))),
        root && h(React.Fragment, null,
          h('p', { style: { overflowWrap: 'anywhere' } }, `${t.identity}: ${root.identity}`),
          h('details', null, h('summary', null, t.draft), h('p', null, t.graphHint),
            text(t.draftId, 'draftId', { maxLength: 128, onChange: event => patch({ draftId: event.target.value, draftPhrase: '' }) }),
            field(t.graph, 'textarea', { rows: 8, maxLength: maxBytes, value: form.graph, onChange: event => patch({ graph: event.target.value, draftPhrase: '' }) }),
            phrase(t.draftPhrase, 'draftPhrase', draftRequired),
            button(t.create, createDraft, stale.checkpoint || !form.draftId || !form.graph || !matches(form.draftPhrase, draftRequired))),
          field(t.run, 'select', { value: runId, onChange: event => {
            setRunId(event.target.value); setDetail(null); setResult(null); patch({ action: '', nodeId: '', actionPhrase: '', retryPhrase: '' });
          } }, options(ownedRuns.map(row => [row.id, `${row.id} · ${row.status} · ${t.revision} ${row.revision}`]))),
          button(t.details, () => run(async signal => {
            setStale(previous => ({ ...previous, checkpoint: true }));
            setDetail(await loadDetail(root, runId, signal));
            setStale(previous => ({ ...previous, checkpoint: false }));
          }), !runId),
          selected && h('div', null,
            h('p', null, `${selected.id} · ${selected.status} · ${t.revision} ${selected.revision}`), json(t.metadata, runMetadata(selected)),
            h('p', null, t.checkpointRisk),
            field(t.action, 'select', { value: form.action, onChange: event => patch({ action: event.target.value, nodeId: '', actionPhrase: '', retryPhrase: '' }) }, options(['start', 'resume', 'retry', 'cancel'].map(action => [action, t[action], !actions[action]]))),
            form.action && h(React.Fragment, null,
              form.action === 'retry' && field(t.node, 'select', { value: form.nodeId, onChange: event => patch({ nodeId: event.target.value, actionPhrase: '', retryPhrase: '' }) }, options(retryNodes.map(node => [node.id, `${node.id} · ${node.status} · ${node.attempt}`]))),
              phrase(t.actionPhrase, 'actionPhrase', actionRequired),
              form.action === 'retry' && phrase(t.retryPhrase, 'retryPhrase', retryRequired),
              button(t.execute, checkpointAction, !canAct)))),
      ),
      budgets && h('article', { style: cardStyle },
        h('h4', null, t.budgets), h('p', null, t.cost), json(t.capabilities, budgets.capabilities),
        !budgets.roots.length && h('p', null, t.emptyRoots),
        field(t.budgetRoot, 'select', { value: budgetId, onChange: event => {
          const value = budgets.roots.find(row => row.rootSessionId === event.target.value);
          setBudgetId(event.target.value); setResult(null);
          patch({ limits: value ? JSON.stringify(value.limits, null, 2) : '', budgetPhrase: '', requestIds: [], childIds: [], reconcilePhrase: '', quiescent: false });
        } }, options(budgets.roots.map(row => [row.rootSessionId, `${row.rootSessionId} · ${t.revision} ${row.revision}`]))),
        budget && h(React.Fragment, null,
          h('p', null, `${budget.rootSessionId} · ${t.revision} ${budget.revision}`),
          h('h5', null, t.consumption), h('pre', { style: preStyle }, JSON.stringify(budgetMetadata(budget), null, 2)),
          h('details', null, h('summary', null, t.configure), h('p', null, t.budgetHint), h('p', null, `${t.allowed}: ${allowedLimits.join(', ')}`),
            field(t.limits, 'textarea', { rows: 5, maxLength: maxBytes, value: form.limits, onChange: event => patch({ limits: event.target.value, budgetPhrase: '' }) }),
            phrase(t.budgetPhrase, 'budgetPhrase', budgetRequired), button(t.configure, configureBudget, stale.budget || !matches(form.budgetPhrase, budgetRequired))),
          h('details', null, h('summary', null, t.reconcile), h('p', null, t.reconcileHint),
            requestRecords.length + childRecords.length === 0 && h('p', null, t.noAmbiguous),
            ...[[requestRecords, 'requestIds', t.requestRecord], [childRecords, 'childIds', t.childRecord]].flatMap(([rows, key, label]) => rows.map(row => h('div', { key: `${key}:${row.id}`, style: { marginBlock: 10 } },
              h('label', { style: { display: 'block', overflowWrap: 'anywhere' } },
                h('input', { type: 'checkbox', disabled: busy, checked: form[key].includes(row.id), onChange: event => toggle(key, row.id, event.target.checked) }),
                ` ${label}: ${row.id}${row.child_id ? ` (child_id: ${row.child_id})` : ''}`),
              h('pre', { style: preStyle }, JSON.stringify(pick(row, key === 'requestIds'
                ? ['id', 'session_id', 'provider', 'model', 'purpose', 'state', 'output_reserved', 'cost_reserved']
                : ['id', 'child_id', 'parent_id', 'provider', 'kind', 'state']), null, 2)),
              key === 'requestIds' && h('p', null, t.fullReservation)))),
            h('label', { style: { display: 'block', marginBlock: 10 } }, h('input', { type: 'checkbox', disabled: busy, checked: form.quiescent, onChange: event => patch({ quiescent: event.target.checked }) }), ` ${t.quiescent}`),
            phrase(t.reconcilePhrase, 'reconcilePhrase', reconcileRequired), button(t.reconcileSubmit, reconcileBudget, !canReconcile)))),
      deliveries && h('article', { style: cardStyle },
        h('h4', null, t.deliveries), h('p', null, t.deliveryHint),
        deliveries.length === 0 && h('p', null, t.noDeliveries),
        field(t.delivery, 'select', { value: deliveryId, onChange: event => { setDeliveryId(event.target.value); setDeliveryPhrase(''); setResult(null); } },
          options(deliveries.map(row => [row.id, `${row.id} · ${row.sessionId}`]))),
        delivery && h('div', null,
          h('pre', { style: preStyle }, JSON.stringify(delivery, null, 2)),
          !deliveryRetryable && h('p', null, t.deliveryUnavailable),
          (deliveryStale || stale.delivery) && h('p', { role: 'status' }, t.deliveryReload),
          h('p', null, t.exact), h('pre', { style: preStyle }, `"${deliveryRequired}"`),
          field(t.deliveryPhrase, 'input', { value: deliveryPhrase, autoComplete: 'off', spellCheck: false, onChange: event => setDeliveryPhrase(event.target.value) }),
          button(t.deliveryRetry, retryDelivery, !canRetryDelivery))),
    );
  };
}
