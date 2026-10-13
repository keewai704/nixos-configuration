import { Context } from '@deepseek-ai/cordis'
import SessionPersistence, { SessionPersistenceRevision } from '@deepseek-ai/dsh-session-persistence'
import type { SessionAccess, SessionHandle, SessionPersistenceCreateOptions, SessionPersistenceSnapshot } from '@deepseek-ai/dsh-session-persistence'
import { SessionLogOffset } from '@deepseek-ai/dsh-session'
import type { SessionEvent, SessionHeader, SessionId } from '@deepseek-ai/dsh-session'

type Stored = { header: SessionHeader; inherited: SessionLogOffset; events: SessionEvent[]; durable: SessionEvent[] }
export default class MemorySessions extends SessionPersistence {
  readonly rows = new Map<SessionId, Stored>()
  constructor(ctx: Context) {
    super(ctx)
    ctx.on('session/event', (session, event) => { this.rows.get(session.id)?.events.push(event) })
  }
  async create(header: SessionHeader, options?: SessionPersistenceCreateOptions): Promise<SessionHandle> {
    if (this.rows.has(header.id)) throw new Error('duplicate disposable Session')
    this.rows.set(header.id, { header, inherited: options?.inheritedEventCount ?? SessionLogOffset(0), events: [], durable: [] })
    return this.open(header.id, 'write')
  }
  async open(id: SessionId, access: SessionAccess): Promise<SessionHandle> {
    const row = this.rows.get(id)
    if (!row) throw new Error('unknown disposable Session')
    return {
      id, header: row.header, inheritedEventCount: row.inherited, access,
      read: async (offset = 0, length = row.events.length) => ({ events: structuredClone(row.events.slice(offset, offset + length)), eventState: 'detached' }),
      append: async events => { row.events.push(...events) },
      flush: async () => { row.durable = structuredClone(row.events) },
      close: async () => {},
      [Symbol.asyncDispose]: async () => {},
    }
  }
  async flush(): Promise<void> {
    for (const row of this.rows.values()) row.durable = structuredClone(row.events)
  }
  async stat(id: SessionId): Promise<SessionPersistenceSnapshot | undefined> {
    const row = this.rows.get(id)
    return row === undefined ? undefined : { header: row.header, eventCount: row.events.length, revision: SessionPersistenceRevision(String(row.events.length)) }
  }
  async list(): Promise<readonly SessionPersistenceSnapshot[]> {
    return [...this.rows.values()].map(row => ({ header: row.header, eventCount: row.events.length, revision: SessionPersistenceRevision(String(row.events.length)) }))
  }
}
