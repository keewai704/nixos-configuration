import { constants } from 'node:fs'
import { lstat, mkdir, open, realpath, readdir, rename, type FileHandle } from 'node:fs/promises'
import { createHash, randomUUID } from 'node:crypto'
import { dirname, join, resolve } from 'node:path'
import type { ApprovalOutcome } from '@deepseek-ai/dsh-user-approval'

export interface ApprovalAuditStart {
  id: string
  sessionId: string
  turnStartSeq: number | null
  toolName: string
  callId?: string
  reasonDigest: string
  reasonBytes: number
}

export interface ApprovalAuditResult {
  answer: ApprovalOutcome
  outcome: ApprovalOutcome
  nativeAudit: 'paired' | 'not-recorded' | 'failed' | 'unknown'
  sessionFlushed: boolean
  cause: 'answer' | 'cancelled' | 'closed-turn' | 'policy-never' | 'unavailable' | 'durability-failed' | 'owner-lost'
}

export interface ApprovalAuditRecord extends ApprovalAuditStart {
  version: 1
  startedAt: number
  state: 'pending' | 'decided' | 'interrupted'
  result?: ApprovalAuditResult
  finishedAt?: number
}

const outcomes = ['allowed-once', 'rejected', 'cancelled', 'unavailable']
const causes = ['answer', 'cancelled', 'closed-turn', 'policy-never', 'unavailable', 'durability-failed', 'owner-lost']
const fields = ['version', 'id', 'sessionId', 'turnStartSeq', 'toolName', 'callId', 'reasonDigest', 'reasonBytes', 'startedAt', 'state', 'result', 'finishedAt']
const resultFields = ['answer', 'outcome', 'nativeAudit', 'sessionFlushed', 'cause']
const limit = 16_384

function identity(value: unknown): asserts value is string {
  if (typeof value !== 'string' || value.length < 1 || value.length > 1024 || /[\u0000-\u001f\u007f]/.test(value)) throw new Error('Invalid approval audit identity')
}

function natural(value: unknown): asserts value is number {
  if (!Number.isSafeInteger(value) || (value as number) < 0) throw new Error('Invalid approval audit integer')
}

function keyOf(id: string): string {
  identity(id)
  return createHash('sha256').update(id).digest('hex')
}

function validate(row: ApprovalAuditRecord, key: string): ApprovalAuditRecord {
  if (!row || Array.isArray(row) || row.version !== 1 || keyOf(row.id) !== key || !['pending', 'decided', 'interrupted'].includes(row.state)) throw new Error('Invalid approval audit record')
  if (Object.keys(row).some(field => !fields.includes(field))) throw new Error('Unknown approval audit field')
  identity(row.sessionId)
  identity(row.toolName)
  if (row.callId !== undefined) identity(row.callId)
  if (row.turnStartSeq !== null) natural(row.turnStartSeq)
  natural(row.reasonBytes)
  natural(row.startedAt)
  if (typeof row.reasonDigest !== 'string' || !/^[a-f0-9]{64}$/.test(row.reasonDigest)) throw new Error('Invalid approval reason digest')
  if (row.state === 'pending') {
    if (row.result !== undefined || row.finishedAt !== undefined) throw new Error('Pending approval audit has a result')
  } else {
    natural(row.finishedAt)
    const result = row.result
    if (row.finishedAt < row.startedAt || !result || Array.isArray(result)
      || Object.keys(result).some(field => !resultFields.includes(field))
      || !outcomes.includes(result.answer) || !outcomes.includes(result.outcome)
      || !['paired', 'not-recorded', 'failed', 'unknown'].includes(result.nativeAudit)
      || typeof result.sessionFlushed !== 'boolean' || !causes.includes(result.cause)) throw new Error('Invalid approval audit result')
    if (result.outcome === 'allowed-once' && (row.state !== 'decided' || result.answer !== 'allowed-once' || !result.sessionFlushed || result.nativeAudit !== 'paired')) throw new Error('Unaudited approval grant')
    if (row.state === 'interrupted' && (result.outcome !== 'cancelled' || result.cause !== 'owner-lost' || result.nativeAudit !== 'unknown')) throw new Error('Invalid interrupted approval')
  }
  return row
}

export class ApprovalJournal {
  readonly root: string
  private tail: Promise<unknown> = Promise.resolve()
  private readonly active = new Map<string, { row: ApprovalAuditRecord; lease: FileHandle }>()
  private ready = false
  private closed = false

  constructor(root: string, private readonly lockExclusive: (fd: number) => Promise<void>) {
    this.root = resolve(root)
  }

  private enqueue<T>(action: () => Promise<T>): Promise<T> {
    const next = this.tail.then(() => {
      if (!this.ready || this.closed) throw new Error('Approval journal is unavailable')
      return action()
    })
    this.tail = next.catch(() => {})
    return next
  }

  async init(): Promise<void> {
    if (this.ready || this.closed) throw new Error('Approval journal already initialized or closed')
    const created = await mkdir(this.root, { recursive: true, mode: 0o700 })
    if (await realpath(this.root) !== this.root) throw new Error('Symlinked approval journal directory')
    const info = await lstat(this.root)
    if (!info.isDirectory() || info.uid !== process.getuid!() || (info.mode & 0o077)) throw new Error('Unsafe approval journal directory')
    for (let parent = dirname(this.root); ; parent = dirname(parent)) {
      const ancestor = await lstat(parent)
      if (!ancestor.isDirectory() || (parent !== dirname(parent) && ![0, process.getuid!()].includes(ancestor.uid))
        || ((ancestor.mode & 0o022) && !(ancestor.uid === 0 && (ancestor.mode & 0o1000)))) throw new Error('Unsafe approval journal ancestor')
      if (parent === dirname(parent)) break
    }
    if (created !== undefined) {
      const anchor = dirname(created)
      for (let path = this.root; ; path = dirname(path)) {
        const directory = await open(path, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW)
        try { await directory.sync() } finally { await directory.close() }
        if (path === anchor) break
      }
    }
    for (const file of await readdir(this.root)) {
      if (!/^[a-f0-9]{64}\.json$/.test(file)) continue
      const key = file.slice(0, -5)
      let lease: FileHandle
      try { lease = await this.lease(key) }
      catch (error) {
        if (['EAGAIN', 'EWOULDBLOCK'].includes((error as NodeJS.ErrnoException).code ?? '')) continue
        throw error
      }
      try {
        const row = await this.read(key)
        if (row.state === 'pending') await this.save(key, {
          ...row, state: 'interrupted', finishedAt: Math.max(row.startedAt, Date.now()),
          result: { answer: 'unavailable', outcome: 'cancelled', nativeAudit: 'unknown', sessionFlushed: false, cause: 'owner-lost' },
        })
      } finally { await lease.close() }
    }
    this.ready = true
  }

  private async lease(key: string): Promise<FileHandle> {
    const path = join(this.root, `${key}.lock`)
    const file = await open(path, constants.O_CREAT | constants.O_RDWR | constants.O_NOFOLLOW, 0o600)
    try {
      const info = await file.stat()
      if (!info.isFile() || info.nlink !== 1 || info.uid !== process.getuid!() || (info.mode & 0o077)) throw new Error('Unsafe approval journal lock')
      await this.lockExclusive(file.fd)
      const current = await lstat(path)
      if (info.dev !== current.dev || info.ino !== current.ino) throw new Error('Approval journal lock changed')
      return file
    } catch (error) { await file.close(); throw error }
  }

  private async read(key: string): Promise<ApprovalAuditRecord> {
    const file = await open(join(this.root, `${key}.json`), constants.O_RDONLY | constants.O_NOFOLLOW)
    try {
      const info = await file.stat()
      if (!info.isFile() || info.size > limit || info.nlink !== 1 || info.uid !== process.getuid!() || (info.mode & 0o077)) throw new Error('Unsafe approval journal record')
      const buffer = Buffer.alloc(limit + 1)
      let size = 0
      while (size < buffer.length) {
        const result = await file.read(buffer, size, buffer.length - size, size)
        if (result.bytesRead === 0) break
        size += result.bytesRead
      }
      if (size > limit) throw new Error('Approval audit record exceeds size limit')
      return validate(JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(buffer.subarray(0, size))) as ApprovalAuditRecord, key)
    } finally { await file.close() }
  }

  private async save(key: string, row: ApprovalAuditRecord): Promise<void> {
    const serialized = `${JSON.stringify(validate(row, key))}\n`
    if (Buffer.byteLength(serialized) > limit) throw new Error('Approval audit record exceeds size limit')
    const destination = join(this.root, `${key}.json`)
    if (!/^[a-f0-9]{64}$/.test(key) || resolve(destination) !== `${this.root}/${key}.json`) throw new Error('Unsafe approval journal destination')
    const temporary = join(this.root, `${key}.${randomUUID()}.tmp`)
    const file = await open(temporary, constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY | constants.O_NOFOLLOW, 0o600)
    try { await file.writeFile(serialized); await file.sync() }
    finally { await file.close() }
    await rename(temporary, destination)
    for (const path of [this.root, dirname(this.root)]) {
      const directory = await open(path, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW)
      try { await directory.sync() } finally { await directory.close() }
    }
  }

  start(input: ApprovalAuditStart): Promise<void> {
    return this.enqueue(async () => {
      const key = keyOf(input.id)
      const row: ApprovalAuditRecord = validate({ ...input, version: 1, state: 'pending', startedAt: Date.now() }, key)
      const lease = await this.lease(key)
      try {
        try { await lstat(join(this.root, `${key}.json`)); throw new Error('Approval audit id already exists') }
        catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error }
        await this.save(key, row)
        this.active.set(input.id, { row, lease })
      } catch (error) { await lease.close(); throw error }
    })
  }

  finish(id: string, result: ApprovalAuditResult): Promise<void> {
    return this.enqueue(async () => {
      const entry = this.active.get(id)
      if (entry === undefined) throw new Error('Approval audit is not active')
      const row: ApprovalAuditRecord = { ...entry.row, state: 'decided', result, finishedAt: Math.max(entry.row.startedAt, Date.now()) }
      await this.save(keyOf(id), row)
      entry.row = row
    })
  }

  async flush(id: string): Promise<boolean> {
    return this.enqueue(async () => {
      const entry = this.active.get(id)
      if (entry === undefined || entry.row.state !== 'decided') return false
      const row = await this.read(keyOf(id))
      return JSON.stringify(row) === JSON.stringify(entry.row)
    })
  }

  release(id: string): Promise<void> {
    return this.enqueue(async () => {
      const entry = this.active.get(id)
      if (entry === undefined) return
      await entry.lease.close()
      this.active.delete(id)
    })
  }

  async list(): Promise<ApprovalAuditRecord[]> {
    return this.enqueue(async () => {
      const rows: ApprovalAuditRecord[] = []
      for (const file of await readdir(this.root)) {
        if (/^[a-f0-9]{64}\.json$/.test(file)) rows.push(await this.read(file.slice(0, -5)))
      }
      return rows.sort((a, b) => b.startedAt - a.startedAt).slice(0, 100)
    })
  }

  async close(): Promise<void> {
    this.closed = true
    await this.tail
    this.ready = false
    for (const { lease } of this.active.values()) await lease.close()
    this.active.clear()
  }
}
