window.__ModuleLoader__.load({
  id: "dsh-subscription-usage",
  factory: (require) => {
    const React = require("react");
    const h = React.createElement;
    const NS = "subscriptionUsage";
    const en = {
      nav: "Usage", cost: "Cost", tokens: "Tokens", limits: "Limits", refresh: "Refresh",
      period: "Period", provider: "Provider", model: "Model", all: "All providers", allModels: "All models",
      "24h": "Past 24 hours", "7d": "Past 7 days", "30d": "Past 30 days", "90d": "Past 90 days",
      processed: "Processed tokens", input: "Uncached input", cacheRead: "Cache read", cacheWrite: "Cache write",
      output: "Output", reasoning: "Reasoning (included in output)", savings: "Cache savings", cacheHit: "Cache hit rate",
      estimate: "Estimated cost · API equivalent", sessions: "Sessions", requests: "Requests", breakdown: "Models",
      hourly: "Hourly trend", daily: "Daily trend", types: "By token type", speeds: "By speed", premium: "Speed premium",
      unpriced: "Unpriced", noData: "No usage history in this period", loading: "Loading…", error: "Usage could not be loaded. Try refreshing.",
      sources: "History and pricing", claudeSource: "Claude Code history", codexSource: "Codex history", dshSource: "DSH ChatGPT history",
      ok: "Ready", missing: "No history", partial: "Partial", files: "files", skipped: "unreadable files", malformed: "invalid records",
      pricing: "Model prices", fresh: "Current", cached: "Cached", unavailable: "Unavailable", updated: "Updated", duplicates: "Duplicates excluded",
      local: "History on this host", other: "Other", standard: "Standard", fast: "Fast", ultrafast: "Ultrafast",
      t3: "T3 service tier history",
      session: "Session", weekly: "Weekly", monthly: "Monthly", monthlySpend: "Monthly spending limit", monthlyCredit: "Monthly credit limit",
      remaining: "remaining", resets: "Resets", availableAgain: "Available again", credits: "Banked resets", unsupported: "Limits are not reported for this connection",
      limitsError: "Limits are unavailable. Check the CLI sign-in and connection.", checked: "Checked", pricesEdit: "Model prices",
      priceModel: "Exact model ID", perMillion: "USD per million tokens", save: "Save", resetPrice: "Reset to automatic", close: "Close",
      priceHelp: "Leave cache rates blank to use the input rate.", details: "Daily values", priceSaved: "Price saved", incomplete: "Some usage could not be priced",
    };
    const ja = {
      nav: "使用状況", cost: "コスト", tokens: "トークン", limits: "契約残量", refresh: "更新",
      period: "期間", provider: "プロバイダー", model: "モデル", all: "すべてのプロバイダー", allModels: "すべてのモデル",
      "24h": "過去24時間", "7d": "過去7日間", "30d": "過去30日間", "90d": "過去90日間",
      processed: "処理トークン", input: "未キャッシュ入力", cacheRead: "キャッシュ読取", cacheWrite: "キャッシュ書込",
      output: "出力", reasoning: "推論（出力の内数）", savings: "キャッシュ節約額", cacheHit: "キャッシュヒット率",
      estimate: "推定コスト・API料金換算", sessions: "セッション", requests: "リクエスト", breakdown: "モデル別",
      hourly: "時間別の推移", daily: "日別の推移", types: "トークン種別", speeds: "速度別", premium: "高速処理の追加分",
      unpriced: "未換算", noData: "この期間の利用履歴はありません", loading: "取得中…", error: "使用状況を取得できません。更新して再試行してください。",
      sources: "集計元と料金表", claudeSource: "Claude Code の履歴", codexSource: "Codex の履歴", dshSource: "DSH の ChatGPT 履歴",
      ok: "取得済み", missing: "履歴なし", partial: "一部取得", files: "ファイル", skipped: "読取不可", malformed: "不正なレコード",
      pricing: "モデル単価", fresh: "取得済み", cached: "キャッシュ", unavailable: "取得不可", updated: "更新", duplicates: "除外した重複",
      local: "このホストの利用履歴", other: "その他", standard: "通常", fast: "Fast", ultrafast: "Ultrafast",
      t3: "T3 の速度設定履歴",
      session: "セッション", weekly: "週間", monthly: "月間", monthlySpend: "追加使用の月額上限", monthlyCredit: "月間クレジット上限",
      remaining: "残り", resets: "リセット", availableAgain: "利用再開", credits: "リセットカード", unsupported: "この接続では契約残量が提供されていません",
      limitsError: "契約残量を取得できません。CLI のログインと接続を確認してください。", checked: "取得", pricesEdit: "モデル単価",
      priceModel: "モデルID（完全一致）", perMillion: "100万トークンあたりの USD", save: "保存", resetPrice: "自動計算に戻す", close: "閉じる",
      priceHelp: "キャッシュ単価が空欄なら入力単価を使います。", details: "日別の数値", priceSaved: "単価を保存しました", incomplete: "一部の利用量は料金を換算できません",
    };
    const providerName = (provider) => provider === "chatgpt" ? "ChatGPT" : "Claude";
    const number = (value) => new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 }).format(value);
    const compact = (value) => new Intl.NumberFormat(undefined, { notation: "compact", maximumFractionDigits: 1 }).format(value);
    const usd = (value) => new Intl.NumberFormat(undefined, { style: "currency", currency: "USD", maximumFractionDigits: value < 1 ? 3 : 2 }).format(value);
    const date = (value) => value ? new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }).format(new Date(value)) : "—";
    const cost = (bucket, t) => bucket.records > 0 && bucket.records === bucket.unpricedRecords ? t("unpriced") : usd(bucket.cost);
    const styles = `
      .su-page{box-sizing:border-box;width:100%;height:100%;min-height:0;overflow:auto;padding:clamp(16px,3vw,32px);color:var(--dsw-alias-label-primary)}
      .su-content{max-width:1120px;margin:0 auto;display:flex;flex-direction:column;gap:24px}
      .su-title,.su-toolbar,.su-tabs,.su-row{display:flex;align-items:center;gap:12px;flex-wrap:wrap}.su-title{justify-content:space-between}
      .su-page h1{font-size:22px;font-weight:600;margin:0}.su-page h2{font-size:14px;font-weight:600;margin:0 0 12px}.su-page p{margin:6px 0}
      .su-page button,.su-page select,.su-page input{font:inherit;color:inherit;background:transparent;border:1px solid var(--dsw-alias-border-l2);border-radius:8px;padding:8px 10px;min-height:36px;box-sizing:border-box}
      .su-page button{cursor:pointer}.su-page button:disabled{opacity:.5;cursor:default}.su-page button:hover{background:color-mix(in srgb,currentColor 5%,transparent)}
      .su-tabs{border-bottom:1px solid var(--dsw-alias-border-l2);gap:18px}.su-tabs button{border:0;border-radius:0;padding:10px 0;opacity:.55}.su-tabs button[aria-selected=true]{opacity:1;border-bottom:2px solid currentColor}
      .su-toolbar select{max-width:100%}.su-model-select{flex:1;min-width:120px}.su-muted{color:var(--dsw-alias-label-secondary);font-size:12px}.su-error{padding:12px;border:1px solid var(--dsw-alias-border-l2);border-radius:8px}
      .su-totals{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:24px}.su-stat{display:flex;flex-direction:column;gap:6px;min-width:0}.su-value{font-size:25px;font-variant-numeric:tabular-nums;line-height:1.2}.su-value small{font-size:14px}
      .su-sections{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}.su-section{min-width:0}.su-meter{height:8px;border-radius:4px;overflow:hidden;background:color-mix(in srgb,currentColor 8%,transparent);margin:8px 0 4px}.su-meter>span{display:block;height:100%;background:currentColor;opacity:.55}
      .su-chart{display:block;width:100%;height:auto;max-height:220px;overflow:visible}.su-chart text{fill:currentColor;font-size:11px;opacity:.6}.su-chart rect{fill:currentColor;opacity:.48}.su-chart rect:hover{opacity:.85}
      .su-table-wrap{overflow-x:auto}.su-page table{border-collapse:collapse;width:100%;font-size:12px;white-space:nowrap}.su-page th,.su-page td{padding:10px 8px;border-bottom:1px solid var(--dsw-alias-border-l2);text-align:right;font-variant-numeric:tabular-nums}.su-page th:first-child,.su-page td:first-child{text-align:left}.su-page td button{border:0;padding:0;min-height:24px;text-align:left}
      .su-limit{padding:18px 0;border-top:1px solid var(--dsw-alias-border-l2)}.su-limit:first-child{border-top:0}.su-limit .su-value{font-size:28px}.su-limit-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}
      .su-page details{border-top:1px solid var(--dsw-alias-border-l2);padding-top:14px}.su-page summary{cursor:pointer;font-size:12px}.su-form{padding:16px;border:1px solid var(--dsw-alias-border-l2);border-radius:10px;display:flex;flex-direction:column;gap:14px}.su-price-fields{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.su-price-fields label{display:flex;flex-direction:column;gap:6px;font-size:12px}.su-price-fields input{width:100%;min-width:0}
      @media(max-width:640px){.su-totals{grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}.su-sections,.su-limit-grid{grid-template-columns:1fr}.su-page th,.su-page td{padding:9px 6px}.su-value{font-size:22px}.su-toolbar{gap:8px}.su-content{gap:20px}}
      html[data-rdsh-device-mode="mobile"] .su-page{padding-top:60px}
    `;

    function Metric({ label, value, note }) {
      return h("div", { className: "su-stat" }, h("span", { className: "su-muted" }, label), h("span", { className: "su-value" }, value), note && h("span", { className: "su-muted" }, note));
    }

    function Distribution({ values, title, format, t }) {
      const sum = Object.values(values).reduce((total, value) => total + value, 0);
      return h("section", { className: "su-section" }, h("h2", null, title), Object.entries(values).filter(([, value]) => value > 0).map(([key, value]) =>
        h("div", { key, style: { marginBottom: 12 } }, h("div", { className: "su-title" }, h("span", { className: "su-muted" }, t(key)), h("span", { style: { fontVariantNumeric: "tabular-nums" } }, format(value))),
          h("div", { className: "su-meter" }, h("span", { style: { width: `${sum ? value / sum * 100 : 0}%` } })))));
    }

    function Trend({ data, metric, t }) {
      const values = data.series.map((bucket) => metric === "cost" ? bucket.cost : bucket.totalTokens);
      const maximum = Math.max(...values, 1);
      const step = 680 / Math.max(1, values.length);
      const hourly = data.period === "24h";
      return h("section", null, h("h2", null, t(hourly ? "hourly" : "daily")), h("svg", { className: "su-chart", viewBox: "0 0 720 180", role: "img", "aria-label": t(hourly ? "hourly" : "daily") },
        h("text", { x: 4, y: 13 }, metric === "cost" ? usd(maximum === 1 && !values.some(Boolean) ? 0 : maximum) : compact(maximum === 1 && !values.some(Boolean) ? 0 : maximum)),
        ...data.series.map((bucket, index) => {
          const height = values[index] / maximum * 130;
          const label = hourly ? new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit", timeZone: data.timeZone }).format(new Date(bucket.key)) : bucket.key.slice(5);
          return h("g", { key: bucket.key }, h("rect", { x: 30 + index * step, y: 150 - height, width: Math.max(1, step - 3), height: Math.max(height, 1), rx: 2 }, h("title", null, `${label}: ${metric === "cost" ? cost(bucket, t) : number(bucket.totalTokens)}`)),
            (index === 0 || index === values.length - 1 || index % Math.ceil(values.length / 6) === 0) && h("text", { x: 30 + index * step, y: 172, textAnchor: index === values.length - 1 ? "end" : "start" }, label));
        })));
    }

    function PriceEditor({ rpc, models, t, onSaved, onClose }) {
      const [overrides, setOverrides] = React.useState({});
      const [model, setModel] = React.useState("");
      const [fields, setFields] = React.useState({ input: "", output: "", cacheRead: "", cacheWrite: "" });
      const [busy, setBusy] = React.useState(true);
      const [error, setError] = React.useState(false);
      React.useEffect(() => {
        let active = true;
        rpc.call("prices").then((value) => { if (active) setOverrides(value); }).catch(() => { if (active) setError(true); }).finally(() => { if (active) setBusy(false); });
        return () => { active = false; };
      }, [rpc]);
      const select = (value) => {
        setModel(value);
        setFields(Object.fromEntries(Object.keys(fields).map((key) => [key, overrides[value]?.[key] ?? ""])));
      };
      const save = async (reset = false) => {
        setBusy(true); setError(false);
        try {
          const next = Object.fromEntries(Object.entries(overrides).filter(([id]) => id !== model));
          if (!reset) Object.defineProperty(next, model, { enumerable: true, value: Object.fromEntries(Object.entries(fields).filter(([, value]) => value !== "").map(([key, value]) => [key, Number(value)])) });
          setOverrides(await rpc.call("save-prices", next));
          onSaved();
        } catch { setError(true); }
        finally { setBusy(false); }
      };
      return h("div", { className: "su-form" }, h("div", { className: "su-title" }, h("strong", null, t("perMillion")), h("button", { onClick: onClose }, t("close"))),
        h("label", { className: "su-muted" }, t("priceModel")), h("input", { value: model, list: "su-price-models", "aria-label": t("priceModel"), onChange: (event) => select(event.target.value), disabled: busy }),
        h("datalist", { id: "su-price-models" }, models.map((value) => h("option", { key: `${value.provider}:${value.model}`, value: value.model }))),
        h("div", { className: "su-price-fields" }, Object.entries(fields).map(([key, value]) => h("label", { key }, t(key), h("input", { type: "number", min: 0, step: "any", value, disabled: busy, onChange: (event) => setFields({ ...fields, [key]: event.target.value }) })))),
        h("span", { className: "su-muted" }, t("priceHelp")), error && h("p", { role: "alert" }, t("error")),
        h("div", { className: "su-row" }, h("button", { disabled: busy || !model.trim() || fields.input === "" || fields.output === "", onClick: () => save() }, t("save")), h("button", { disabled: busy || !model.trim(), onClick: () => save(true) }, t("resetPrice"))));
    }

    function Limits({ limits, provider, t, now }) {
      return h("div", { className: "su-limit-grid" }, limits.filter((account) => provider === "all" || account.provider === provider).map((account) =>
        h("section", { className: "su-section", key: account.provider }, h("div", { className: "su-title" }, h("h2", null, providerName(account.provider)), account.plan && h("span", { className: "su-muted" }, account.plan)),
          account.status !== "ok" ? h("p", { className: "su-muted" }, t(account.status === "unsupported" ? "unsupported" : "limitsError")) : account.windows.map((window) => {
            const reset = window.nextAvailableAt || window.resetsAt;
            const minutes = reset ? Math.max(0, Math.ceil((Date.parse(reset) - now) / 60_000)) : null;
            const countdown = minutes === null ? "" : `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
            return h("div", { key: window.id, className: "su-limit" }, h("span", { className: "su-muted" }, Object.hasOwn(en, window.label) ? t(window.label) : window.label),
              h("div", { className: "su-value" }, `${number(window.remainingPercent)}% `, h("small", null, t("remaining"))),
              h("div", { className: "su-meter", role: "progressbar", "aria-label": `${providerName(account.provider)} ${window.label}`, "aria-valuenow": window.remainingPercent, "aria-valuemin": 0, "aria-valuemax": 100 }, h("span", { style: { width: `${window.remainingPercent}%` } })),
              reset && h("p", { className: "su-muted" }, `${t(window.nextAvailableAt ? "availableAgain" : "resets")} ${date(reset)} · ${countdown}`));
          }), account.resetCredits !== null && account.resetCredits !== undefined && h("p", { className: "su-muted" }, `${t("credits")}: ${account.resetCredits}`),
          h("p", { className: "su-muted" }, `${t("checked")} ${date(account.checkedAt)}`))));
    }

    function UsagePage({ rpc, t }) {
      const [view, setView] = React.useState("tokens");
      const [period, setPeriod] = React.useState("7d");
      const [provider, setProvider] = React.useState("all");
      const [model, setModel] = React.useState("");
      const [revision, setRevision] = React.useState(0);
      const [data, setData] = React.useState(null);
      const [limits, setLimits] = React.useState(null);
      const [loading, setLoading] = React.useState(false);
      const [limitsLoading, setLimitsLoading] = React.useState(false);
      const [error, setError] = React.useState(false);
      const [editing, setEditing] = React.useState(false);
      const [now, setNow] = React.useState(Date.now());
      const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
      React.useEffect(() => {
        const mobile = globalThis.__RDSH_MOBILE_UX__;
        if (mobile?.phone()) mobile.closeDrawer();
      }, []);
      React.useEffect(() => {
        if (view === "limits") return;
        let active = true;
        setLoading(true); setError(false);
        rpc.call("summary", { period, timeZone, provider, model, refresh: revision > 0 }).then((value) => { if (active) setData(value); }).catch(() => { if (active) setError(true); }).finally(() => { if (active) setLoading(false); });
        return () => { active = false; };
      }, [rpc, view === "limits", period, timeZone, provider, model, revision]);
      const loadLimits = React.useCallback(async (refresh = false) => {
        setLimitsLoading(true); setError(false);
        try { setLimits(await rpc.call("limits", { refresh })); }
        catch { setError(true); }
        finally { setLimitsLoading(false); }
      }, [rpc]);
      React.useEffect(() => {
        if (view !== "limits") return;
        void loadLimits();
        const timer = setInterval(() => { if (document.visibilityState === "visible") void loadLimits(); }, 300_000);
        return () => clearInterval(timer);
      }, [view, loadLimits]);
      React.useEffect(() => { const timer = setInterval(() => setNow(Date.now()), 30_000); return () => clearInterval(timer); }, []);
      const availableModels = (data?.availableModels ?? []).filter((value) => provider === "all" || value.provider === provider);
      const busy = view === "limits" ? limitsLoading : loading;
      return <div className="su-page"><div className="su-content">
        <div className="su-title">
          <h1>{t("nav")}</h1>
          <button disabled={busy} onClick={() => view === "limits" ? void loadLimits(true) : setRevision(revision + 1)}>{busy ? t("loading") : t("refresh")}</button>
        </div>
        <div className="su-tabs" role="tablist" aria-label={t("nav")}>
          {["cost", "tokens", "limits"].map((key) => <button key={key} role="tab" aria-selected={view === key} onClick={() => setView(key)}>{t(key)}</button>)}
        </div>
        <div className="su-toolbar">
          {view !== "limits" && <select aria-label={t("period")} value={period} onChange={(event) => setPeriod(event.target.value)}>
            {["24h", "7d", "30d", "90d"].map((key) => <option key={key} value={key}>{t(key)}</option>)}
          </select>}
          <select aria-label={t("provider")} value={provider} onChange={(event) => { setProvider(event.target.value); setModel(""); }}>
            {["all", "chatgpt", "claude"].map((key) => <option key={key} value={key}>{key === "all" ? t("all") : providerName(key)}</option>)}
          </select>
          {view !== "limits" && <select className="su-model-select" aria-label={t("model")} value={model} onChange={(event) => setModel(event.target.value)}>
            <option value="">{t("allModels")}</option>
            {[...new Set(availableModels.map((value) => value.model))].map((value) => <option key={value} value={value}>{value}</option>)}
          </select>}
          {view === "cost" && <button onClick={() => setEditing(!editing)}>{t("pricesEdit")}</button>}
        </div>
        {error && <p className="su-error" role="alert">{t("error")}</p>}
        {editing && view === "cost" && <PriceEditor rpc={rpc} models={availableModels} t={t} onSaved={() => setRevision(revision + 1)} onClose={() => setEditing(false)} />}
        {view === "limits"
          ? limits ? <Limits limits={limits} provider={provider} t={t} now={now} /> : <p className="su-muted">{t("loading")}</p>
          : data ? <History data={data} loading={loading} view={view} period={period} timeZone={timeZone} t={t} onModel={(row) => { setProvider(row.provider); setModel(row.model); }} />
            : <p className="su-muted">{t("loading")}</p>}
      </div></div>;
    }

    function History({ data, loading, view, period, timeZone, t, onModel }) {
      const totals = data.totals;
      const inputTotal = totals.tokens.input + totals.tokens.cacheRead + totals.tokens.cacheWrite;
      return <div className="su-content" style={{ width: "100%", opacity: loading ? .5 : 1 }} aria-busy={loading}>
        <section className="su-totals">
          <Metric label={view === "cost" ? t("estimate") : t("processed")} value={view === "cost" ? cost(totals, t) : compact(totals.totalTokens)}
            note={totals.unpricedRecords ? `${t("unpriced")}: ${number(totals.unpricedRecords)} ${t("requests")}` : t("local")} />
          <Metric label={t("cacheHit")} value={inputTotal ? `${number(totals.tokens.cacheRead / inputTotal * 100)}%` : "—"} />
          <Metric label={t("sessions")} value={number(totals.sessions)} />
        </section>
        <Trend data={data} metric={view} t={t} />
        <section className="su-totals">
          {["input", "cacheRead", "cacheWrite", "output", "reasoning"].map((key) => <Metric key={key} label={t(key)} value={compact(totals.tokens[key])} />)}
          {view === "cost" && <Metric label={t("savings")} value={usd(totals.savings)} />}
        </section>
        <div className="su-sections">
          <Distribution title={t("types")} values={view === "cost" ? totals.categories : Object.fromEntries(["input", "cacheRead", "cacheWrite", "output"].map((key) => [key, totals.tokens[key]]))} format={view === "cost" ? usd : compact} t={t} />
          {view === "cost" && totals.speedCost.fast + totals.speedCost.ultrafast > 0 && <div>
            <Distribution title={t("speeds")} values={totals.speedCost} format={usd} t={t} />
            <p className="su-muted">{t("premium")}: {usd(totals.premium)}</p>
          </div>}
        </div>
        <section>
          <h2>{t("breakdown")}</h2>
          {data.models.length ? <div className="su-table-wrap"><table>
            <thead><tr>{["model", "processed", "cost", "cacheHit", "requests"].map((key) => <th key={key}>{t(key)}</th>)}</tr></thead>
            <tbody>{data.models.map((row) => {
              const input = row.tokens.input + row.tokens.cacheRead + row.tokens.cacheWrite;
              return <tr key={`${row.provider}:${row.model}`}>
                <td><button onClick={() => onModel(row)}>{row.model}</button><div className="su-muted">{providerName(row.provider)}</div></td>
                <td>{compact(row.totalTokens)}</td><td>{cost(row, t)}</td>
                <td>{input ? `${number(row.tokens.cacheRead / input * 100)}%` : "—"}</td><td>{number(row.records)}</td>
              </tr>;
            })}</tbody>
          </table></div> : <p className="su-muted">{t("noData")}</p>}
        </section>
        <details><summary>{t("details")}</summary><div className="su-table-wrap"><table><tbody>
          {data.series.map((row) => <tr key={row.key}><td>{period === "24h" ? date(row.key) : row.key}</td><td>{number(row.totalTokens)}</td><td>{cost(row, t)}</td></tr>)}
        </tbody></table></div></details>
        <details><summary>{t("sources")}</summary><div className="su-muted">
          {data.sources.map((source) => <p key={source.id}>
            {`${t(`${source.id}Source`)} · ${t(source.status)} · ${number(source.scannedFiles)} ${t("files")}${source.skippedFiles ? ` · ${t("skipped")}: ${source.skippedFiles}` : ""}${source.malformedRecords ? ` · ${t("malformed")}: ${source.malformedRecords}` : ""}`}
          </p>)}
          <p>{t("duplicates")}: {number(data.duplicates)}</p>
          {data.t3Tiers && <p>{t("t3")} · {t(data.t3Tiers.status)} · {number(data.t3Tiers.matched)}</p>}
          <p>{timeZone} · {t("updated")} {date(data.readAt)}</p>
          <p><a href={data.pricing.source} target="_blank" rel="noreferrer">LiteLLM</a> · {t(data.pricing.status)} · {date(data.pricing.fetchedAt)}</p>
        </div></details>
      </div>;
    }

    function Icon({ size = 18 }) {
      return h("svg", { width: size, height: size, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: 1.7, "aria-hidden": true }, h("path", { d: "M4 20V10m8 10V4m8 16v-7" }));
    }

    return {
      inject: ["slots", "locale", "connection"],
      apply(ctx) {
        ctx.effect(() => ctx.locale.register(NS, { en, ja }));
        ctx.effect(() => {
          const element = document.createElement("style");
          element.textContent = styles;
          document.head.append(element);
          return () => element.remove();
        });
        const t = ctx.locale.bind(NS);
        const rpc = {
          async call(endpoint, payload = {}) {
            const response = await ctx.connection.rpc.call("/api", `subscription-usage/${endpoint}`, payload);
            if (!response?.ok) throw new Error("Usage request failed");
            return response.value;
          },
        };
        ctx.slots.inject("main", () => ctx.slots.register({ name: "main", key: "subscription-usage", locale: NS, inject: () => ({ rpc, t }) }, UsagePage));
        ctx.slots.inject("sidebar.panellist", () => ctx.slots.register({ name: "sidebar.panellist", id: "subscription-usage", order: 20, label: () => t("nav"), locale: NS }, Icon));
      },
    };
  },
});
