window.__ModuleLoader__.load({
  id: '@keewai/dsh-operations',
  factory(require) {
    const React = require('react');
    const h = React.createElement;
    const en = {
      title: 'Privacy & operations', refresh: 'Refresh', loading: 'Loading…', privacy: 'Data sharing',
      warning: 'These four channels are independent. Disabling affects future collection, not already transmitted data. In-flight requests may finish. Provider requests still send the context needed to answer.',
      'session-telemetry-otel': 'Feedback session upload', 'session-log-deepseek': 'DeepSeek session history',
      'plugin-package-inventory-deepseek': 'DeepSeek plugin inventory', 'product-analytics': 'Desktop product analytics',
      enabled: 'Enabled', disabled: 'Disabled', 'not-mounted': 'Not installed in this composition', 'not-active': 'Inactive', unknown: 'Unknown',
      enable: 'Enable…', disable: 'Disable…', confirm: 'Confirm change', cancel: 'Cancel',
      confirmHint: 'Review the scope above, then enter the exact phrase. Re-enabling session-history sharing can upload earlier conversation text, instructions and tool results.',
      retention: 'Local retention preview', days: 'Created more than this many days ago', preview: 'Preview only',
      retentionHint: 'Creation age is not last activity. No automatic deletion is enabled. Deletion and attachment collection require the offline dsh-maintenance command, exclusive locking and a fresh confirmation plan. Stop all packaged DSH processes first. Workspaces, credentials and uploaded remote data are not erased by deleting local history.',
      candidates: 'Candidate sessions', bytes: 'Known bytes', plugins: 'Plugin health & trust',
      trust: 'Plugins execute as the host user, outside tool sandboxes. Official, installed, enabled and active are separate states. Version-range acceptance alone does not prove compatibility. Nix-managed bundles are reproducible; use the existing Plugins page for package installation and its script approvals.',
      failed: 'Failed / pending plugins', recover: 'Disable failed entry…', bundles: 'Bundle availability',
      active: 'Active', installed: 'Installed', available: 'Available', selected: 'Selected',
      none: 'None', readOnly: 'Controlled by deployment or inactive', partial: 'Japanese language pack: common controls and this page are translated; other text falls back to English.',
      managed: 'This profile is Nix-managed. GUI changes apply now but reset on the next launch or regeneration of this profile, possibly from another DSH process. Change the Nix deployment configuration for persistence.',
      temporary: 'Applied to the current runtime only; not retained after profile regeneration.',
      persistenceUnknown: 'Persistence policy is unknown. Only current runtime application is reported; verify deployment settings before relying on restart persistence.',
      appliedUnknown: 'Applied now. Whether the change survives another launch is unknown.',
      result: 'Change outcome', journal: 'Durable workflow journal', present: 'Mounted', absent: 'Not mounted',
      applied: 'Applied to the running profile.', 'restart-required': 'Saved. Restart the host before this change becomes active.',
      overridden: 'Saved, but a higher-priority deployment setting overrides this change.', changeFailed: 'Change failed; review the error code and refresh before retrying.',
      runs: 'Recent workflow runs', recoveryHint: 'Interrupted means the journal lost ownership; execution may still be active after a plugin reload. No automatic replay is available. Verify running jobs, child sessions and external side effects before starting a new run.',
    };
    const ja = {
      title: 'プライバシーと運用', refresh: '再読み込み', loading: '読み込み中…', privacy: 'データ送信',
      warning: '以下の4経路は独立しています。無効化は今後の収集に適用され、送信済みデータは削除しません。送信中の処理は完了する場合があります。モデルへの通常のリクエストには回答に必要な文脈が送信されます。',
      'session-telemetry-otel': 'フィードバック時の履歴送信', 'session-log-deepseek': 'DeepSeekへの会話・セッション履歴',
      'plugin-package-inventory-deepseek': 'DeepSeekへのプラグイン一覧', 'product-analytics': 'Desktop利用状況分析',
      enabled: '有効', disabled: '無効', 'not-mounted': 'この構成には未配置', 'not-active': '非稼働', unknown: '不明',
      enable: '有効化…', disable: '無効化…', confirm: '変更を確定', cancel: 'キャンセル',
      confirmHint: '送信範囲を確認し、下の確認文字列を正確に入力してください。履歴送信を再度有効化すると、未送信の過去の会話本文・指示・ツール結果も送信される場合があります。',
      retention: 'ローカル保持対象のプレビュー', days: '作成からの経過日数', preview: 'プレビューのみ',
      retentionHint: '作成日は最終利用日ではありません。自動削除は行いません。履歴削除・添付回収にはオフラインの dsh-maintenance コマンド、排他ロック、最新の確認計画が必要です。先にパッケージ版DSHの全プロセスを停止してください。ワークスペース・認証情報・送信済みの遠隔データはローカル履歴の削除では消えません。',
      candidates: '候補セッション数', bytes: '判明しているバイト数', plugins: 'プラグインの状態と信頼境界',
      trust: 'プラグインはツールのサンドボックス外でホストユーザー権限により実行されます。公式・導入済み・有効・稼働中は別の状態です。バージョン範囲の一致だけでは互換性の証明になりません。Nix管理の構成は再現可能です。追加インストールとスクリプト実行許可は既存の「プラグイン」画面で管理してください。',
      failed: '失敗・待機中のプラグイン', recover: '問題のエントリーを無効化…', bundles: 'バンドルの導入状況',
      active: '稼働中', installed: '導入済み', available: '配置元', selected: '選択済み',
      none: 'なし', readOnly: 'デプロイ設定で管理、または非稼働', partial: '日本語パックは共通操作とこの画面を翻訳します。未翻訳部分は英語にフォールバックします。',
      managed: 'このプロファイルはNix管理です。GUIでの変更は今すぐ適用しますが、同じプロファイルの次回起動・再生成で既定値へ戻ります。別のDSHプロセスによる再生成も含みます。永続化にはNixのデプロイ設定を変更してください。',
      temporary: '現在の実行環境にのみ適用しました。プロファイル再生成後は保持されません。',
      persistenceUnknown: '保持性の設定は未確認です。現在の実行環境への適用のみを示します。次回起動後の保持についてはデプロイ設定を確認してください。',
      appliedUnknown: '現在の実行環境に適用しました。次回起動後に保持されるかは未確認です。',
      result: '変更結果', journal: '永続ワークフロー記録', present: '配置済み', absent: '未配置',
      applied: '稼働中のプロファイルに適用しました。', 'restart-required': '保存しました。有効にするにはホストの再起動が必要です。',
      overridden: '保存しましたが、優先順位の高いデプロイ設定により上書きされています。', changeFailed: '変更に失敗しました。エラーコードを確認し、再読み込みしてから再試行してください。',
      runs: '最近のワークフロー', recoveryHint: '中断は記録の所有権を失った状態です。プラグイン再読込み後も処理が動いている可能性があります。自動再実行は行いません。稼働ジョブ・子セッション・外部への変更を確認してから、新しい実行を開始してください。',
    };
    const scopes = {
      'session-telemetry-otel': '明示的なフィードバックを送ると、使用モデルに関係なく、それ以前のセッション履歴も送信対象になります。',
      'session-log-deepseek': '公式DeepSeekリクエストに会話本文、システム・開発者の指示、ツールの入力・結果を含む履歴を添付します。メタデータだけではありません。再有効化時は未送信の過去の履歴も対象になります。',
      'plugin-package-inventory-deepseek': '公式DeepSeekリクエストに稼働プラグインの名前とバージョンを添付します。',
      'product-analytics': 'Desktopの操作・利用状況です。フィードバックやセッション情報とは別経路で、通常のWeb構成では非稼働です。',
    };
    const commonJa = {
      ok: 'OK', cancel: 'キャンセル', close: '閉じる', copy: 'コピー', copied: 'コピー済み',
      'codeBlock.title': 'コード', 'codeBlock.wrap': '折り返す', 'codeBlock.unwrap': '折り返さない',
      'copy.failed': 'コピーに失敗しました', 'copy.value': '値をコピー', 'copy.json': 'JSONをコピー',
      'copy.path': 'プロパティのパスをコピー', 'copy.prettyJson': '整形したJSONをコピー', 'copy.compactJson': '圧縮JSONをコピー',
      'copy.optionsHint': '{action}（右クリックでコピー形式を選択）', retry: '再試行', loading: '読み込み中…',
      'load.failed': '読み込みに失敗しました', submit: '送信', submitting: '送信中…', next: '次へ', previous: '前へ',
      skip: 'スキップ', delete: '削除', edit: '編集', save: '保存', search: '検索', more: 'その他', collapse: '折りたたむ',
      expand: '展開', back: '戻る', 'brand.localBuild': 'DSHローカルビルド', 'workspace.defaultName': '既定のワークスペース',
      unknown: '不明', none: 'なし', truncated: '省略あり', 'json.label': 'JSON', 'markdown.footnotes': '脚注',
      'markdown.truncatedCharacters': '… {total}文字で省略', 'number.thousand': '{value}K', 'number.million': '{value}M',
    };
    const buttonStyle = { border: '1px solid var(--border, #8885)', borderRadius: 6, padding: '6px 12px', cursor: 'pointer', background: 'transparent', color: 'inherit' };
    const cardStyle = { border: '1px solid var(--border, #8885)', borderRadius: 8, padding: 14, marginBlock: 12 };

    async function api(path, data, signal) {
      const response = await fetch(new URL(`api/operations/${path}`, document.baseURI), {
        method: data === undefined ? 'GET' : 'POST', credentials: 'same-origin', signal,
        headers: data === undefined ? {} : { 'content-type': 'application/json', 'x-dsh-operations': '1' },
        ...(data === undefined ? {} : { body: JSON.stringify(data) }),
      });
      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        throw new Error(body.error ?? `HTTP ${response.status}`);
      }
      return response.json();
    }

    function apply(ctx) {
      ctx.effect(() => ctx.locale.addLanguage({ id: 'ja', label: '日本語', fallback: 'en' }));
      ctx.effect(() => ctx.locale.register('common', 'ja', commonJa));
      ctx.effect(() => ctx.locale.register('operations', { en, zh: en, ja }));
      const t = ctx.locale.bind('operations');

      function Page() {
        const locale = React.useSyncExternalStore(fn => ctx.locale.subscribe(fn), () => ctx.locale.getSnapshot());
        const [status, setStatus] = React.useState(null);
        const [error, setError] = React.useState('');
        const [busy, setBusy] = React.useState(false);
        const [pending, setPending] = React.useState(null);
        const [phrase, setPhrase] = React.useState('');
        const [days, setDays] = React.useState('365');
        const [preview, setPreview] = React.useState(null);
        const [result, setResult] = React.useState(null);
        const [runs, setRuns] = React.useState([]);
        const request = React.useRef(null);
        async function run(action) {
          request.current?.abort();
          const controller = new AbortController();
          request.current = controller;
          setBusy(true); setError('');
          try { await action(controller.signal); }
          catch (failure) { if (!controller.signal.aborted) setError(failure.message); }
          finally { if (!controller.signal.aborted) setBusy(false); }
        }
        const refresh = signal => api('status', undefined, signal).then(setStatus);
        React.useEffect(() => { run(refresh); return () => request.current?.abort(); }, []);
        const button = (label, onClick, disabled = false) => h('button', { type: 'button', style: buttonStyle, onClick, disabled: busy || disabled }, label);
        const choose = value => { setPending(value); setPhrase(''); setResult(null); };
        const required = pending ? `${pending.enabled ? 'ENABLE' : 'DISABLE'} ${pending.id}` : '';
        const broken = status?.inventory.entries.filter(row => ['failed', 'pending'].includes(row.phase)) ?? [];
        return h('section', { style: { maxWidth: 860, padding: 8, lineHeight: 1.6 }, 'aria-busy': busy },
          h('h2', { style: { fontSize: 20, fontWeight: 600 } }, t('title')),
          button(t('refresh'), () => run(refresh)),
          h('p', { style: { opacity: .7, fontSize: 12 } }, t('partial')),
          error && h('p', { role: 'alert', style: { color: 'var(--destructive, #d55)' } }, error),
          !status && h('p', { role: 'status' }, t('loading')),
          status && h(React.Fragment, null,
            h('h3', null, t('privacy')), h('p', null, t('warning')),
            status.persistence !== 'profile' && h('p', { style: cardStyle }, t(status.persistence === 'launch-reset' ? 'managed' : 'persistenceUnknown')),
            status.privacy.map(row => h('article', { key: row.id, style: cardStyle },
              h('strong', null, t(row.id)), ' — ', h('span', null, t(row.effective)),
              h('p', null, locale.active === 'ja' ? scopes[row.id] : row.scope),
              row.editable ? button(t(row.effective === 'enabled' ? 'disable' : 'enable'), () => choose({ ...row, enabled: row.effective !== 'enabled', action: 'privacy' })) : h('small', null, t('readOnly')),
            )),
            pending && h('div', { style: cardStyle, role: 'group', 'aria-label': t('confirm') },
              status.persistence !== 'profile' && h('p', null, t(status.persistence === 'launch-reset' ? 'managed' : 'persistenceUnknown')),
              h('p', null, t('confirmHint')), h('code', { style: { overflowWrap: 'anywhere' } }, required),
              h('label', { style: { display: 'block' } }, t('confirm'), h('input', { value: phrase, onChange: event => setPhrase(event.target.value), autoComplete: 'off', spellCheck: false, style: { ...buttonStyle, width: '100%', marginBlock: 10 } })),
              button(t('confirm'), () => run(async signal => {
                const saved = await api(pending.action, { id: pending.id, enabled: pending.enabled, revision: pending.revision, confirmation: phrase }, signal);
                if (saved.application === 'failed' || saved.error) {
                  throw new Error(`${t('changeFailed')} (${saved.error?.code ?? 'operation-error'})`);
                }
                const applied = saved.persistence === 'launch-reset' ? 'temporary' : saved.persistence === 'profile' ? 'applied' : 'appliedUnknown';
                setResult(!saved.application || saved.application === 'applied' ? applied : saved.application);
                setPending(null); await refresh(signal);
              }), phrase !== required), ' ', button(t('cancel'), () => setPending(null)),
            ),
            result && h('p', { role: 'status' }, `${t('result')}: ${t(result)}`),
            h('h3', null, t('retention')), h('p', null, t('retentionHint')),
            h('label', null, t('days'), ' ', h('input', { type: 'number', min: 1, max: 36500, value: days, onChange: event => setDays(event.target.value), style: { ...buttonStyle, width: 110 } })), ' ',
            button(t('preview'), () => run(async signal => setPreview(await api('retention', { days: Number(days) }, signal)))),
            preview && h('div', { style: cardStyle },
              h('p', null, `${t('candidates')}: ${preview.candidates.length} / ${preview.totalSessions} · ${t('bytes')}: ${preview.candidateBytes}`),
              h('ul', { style: { maxHeight: 180, overflowY: 'auto', overflowWrap: 'anywhere' } }, preview.candidates.slice(0, 100).map(row => h('li', { key: row.id }, `${row.id} · ${new Date(row.createdAt).toLocaleDateString()}`))),
            ),
            h('h3', null, t('plugins')), h('p', null, t('trust')),
            h('p', null, `${t('journal')}: ${t(status.reliability.workflowJournal ? 'present' : 'absent')}`),
            h('p', null, t('recoveryHint')),
            status.reliability.workflowJournal && button(t('runs'), () => run(async signal => setRuns((await api('workflows', undefined, signal)).runs))),
            runs.length > 0 && h('ul', { style: { maxHeight: 240, overflowY: 'auto', overflowWrap: 'anywhere' } }, runs.map(row => h('li', { key: row.id },
              `${row.name} · ${row.status} · ${row.agentsStarted}/${row.maxTotalAgents} · ${new Date(row.startedAt).toLocaleString()} · ${row.id}`,
            ))),
            h('h4', null, t('failed')),
            broken.length === 0 ? h('p', null, t('none')) : broken.map(row => h('div', { key: row.id, style: cardStyle }, h('code', null, `${row.module} (${row.phase})`), ' ', button(t('recover'), () => choose({ id: row.id, enabled: false, action: 'recovery' })))),
            h('details', null, h('summary', null, t('bundles')),
              h('ul', null, status.inventory.bundles.map(row => h('li', { key: row.name, style: { marginBlock: 8, overflowWrap: 'anywhere' } },
                h('code', null, `${row.name}${row.version ? ` @ ${row.version}` : ''}`),
                h('div', null, `${t('available')}: ${row.availability} · ${t('installed')}: ${row.installed} · ${t('selected')}: ${row.enabled}${row.error ? ` · ${row.error}` : ''}`),
              ))),
            ),
          ),
        );
      }
      ctx.slots.inject('settings.section', () => ctx.slots.register({ name: 'settings.section', id: 'operations', order: 16, label: () => t('title'), locale: 'operations' }, Page));
    }
    return { name: 'operations-client', inject: ['locale', 'slots'], apply };
  },
});
