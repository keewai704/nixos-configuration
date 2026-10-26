import { stat } from "node:fs/promises";

export async function resolveT3Tiers(records, path) {
  const pending = records.filter((record) => record.unresolvedTurn);
  if (!path || !pending.length) return { records };
  let database;
  try {
    await stat(path);
    const { DatabaseSync } = await import("node:sqlite");
    database = new DatabaseSync(path, { readOnly: true });
    database.exec("PRAGMA query_only = ON; PRAGMA busy_timeout = 1000");
    const ids = JSON.stringify([...new Set(pending.map((record) => record.unresolvedTurn))]);
    const rows = database.prepare(`
      SELECT json_extract(attempt.payload_json, '$.nativeThreadId') AS session,
        json_extract(turn.payload_json, '$.nativeTurnRef.nativeId') AS turn,
        (SELECT json_extract(event.payload_json, '$.modelSelection')
         FROM orchestration_events AS event
         WHERE event.aggregate_kind = 'thread'
           AND event.application_event_version = 2
           AND event.stream_id = attempt.thread_id
           AND event.event_type = 'run.updated'
           AND json_extract(event.payload_json, '$.id') = attempt.run_id
           AND json_extract(event.payload_json, '$.activeAttemptId') = attempt.attempt_id
           AND json_extract(event.payload_json, '$.status') = 'running'
         ORDER BY event.sequence LIMIT 1) AS selection
      FROM orchestration_v2_projection_provider_turns AS turn
      LEFT JOIN orchestration_v2_projection_run_attempts AS attempt
        ON attempt.attempt_id = turn.run_attempt_id
        AND attempt.thread_id = turn.thread_id
        AND attempt.provider_thread_id = turn.provider_thread_id
      WHERE json_extract(turn.payload_json, '$.nativeTurnRef.driver') = 'codex'
        AND json_extract(turn.payload_json, '$.nativeTurnRef.nativeId') IN
          (SELECT value FROM json_each(?))
    `).all(ids);
    const byTurn = new Map();
    for (const row of rows) byTurn.set(row.turn, byTurn.has(row.turn) ? null : row);
    const resolved = new Map();
    for (const record of pending) {
      const row = byTurn.get(record.unresolvedTurn);
      if (!row || row.session !== record.session || typeof row.selection !== "string") continue;
      let selection;
      try { selection = JSON.parse(row.selection); } catch { continue; }
      if (!selection || selection.model !== record.model || selection.options !== undefined && !Array.isArray(selection.options)) continue;
      const option = selection.options?.find((value) => value?.id === "serviceTier");
      if (option && typeof option.value !== "string") continue;
      const tier = option?.value;
      if (tier === "fast" || tier === "priority") resolved.set(record, "fast");
      else if (tier === "ultrafast") resolved.set(record, "ultrafast");
      else if (tier === undefined || tier === "default" || tier === "standard") resolved.set(record, "standard");
    }
    return { records: records.map((record) => resolved.has(record) ? { ...record, speed: resolved.get(record) } : record), t3Tiers: { status: "ok", matched: resolved.size } };
  } catch (error) {
    return { records, t3Tiers: { status: error.code === "ENOENT" ? "missing" : "unavailable", matched: 0 } };
  } finally { database?.close(); }
}
