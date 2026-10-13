import { constants } from 'node:fs';
import { lstat, mkdir, open, realpath, readdir, rename } from 'node:fs/promises';
import { createHash, randomUUID } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';

function natural(value, key, minimum = 0) {
  if (!Number.isSafeInteger(value) || value < minimum) throw new Error(`Invalid workflow journal ${key}`);
  return value;
}

function identity(value) {
  if (typeof value !== 'string' || value.length < 1 || value.length > 1024 || /[\u0000-\u001f\u007f]/.test(value)) throw new Error('Invalid workflow journal identity');
  return value;
}

function fileKey(id) { return createHash('sha256').update(identity(id)).digest('hex'); }

function validateRecord(row, key) {
  if (!row || Array.isArray(row) || row.version !== 1 || fileKey(row.id) !== key || !['running', 'completed', 'cancelled', 'error', 'interrupted'].includes(row.status)) throw new Error('Unsupported workflow journal record');
  const fields = ['version', 'id', 'parentSessionId', 'name', 'startedAt', 'deadlineAt', 'maxTotalAgents', 'maxConcurrentAgents', 'agentsStarted', 'activeAgents', 'status', 'finishedAt'];
  if (Object.keys(row).some(field => !fields.includes(field))) throw new Error('Unknown workflow journal field');
  identity(row.parentSessionId); identity(row.name);
  for (const field of ['startedAt', 'deadlineAt', 'agentsStarted', 'activeAgents']) natural(row[field], field);
  for (const field of ['maxTotalAgents', 'maxConcurrentAgents']) natural(row[field], field, 1);
  if (row.deadlineAt <= row.startedAt || row.maxConcurrentAgents > row.maxTotalAgents || row.agentsStarted > row.maxTotalAgents || row.activeAgents > row.maxConcurrentAgents || row.activeAgents > row.agentsStarted) throw new Error('Invalid workflow journal counters or limits');
  if (row.status === 'running') {
    if (row.finishedAt !== undefined) throw new Error('Running journal record has a finish time');
  } else {
    if (natural(row.finishedAt, 'finishedAt') < row.startedAt || row.activeAgents !== 0) throw new Error('Invalid workflow journal completion');
  }
  return Object.fromEntries(fields.filter(field => Object.hasOwn(row, field)).map(field => [field, row[field]]));
}

export class WorkflowJournal {
  constructor(root, lockExclusive) {
    this.root = resolve(root);
    this.lockExclusive = lockExclusive;
    this.active = new Map();
    this.tail = Promise.resolve();
    this.closed = false;
  }

  enqueue(action) {
    const next = this.tail.then(() => {
      if (this.closed) throw new Error('Workflow journal is closed');
      return action();
    });
    this.tail = next.catch(() => {});
    return next;
  }

  async init() {
    await mkdir(this.root, { recursive: true, mode: 0o700 });
    if (await realpath(this.root) !== this.root) throw new Error('Symlinked workflow journal directory');
    const info = await lstat(this.root);
    if (!info.isDirectory() || info.uid !== process.getuid() || (info.mode & 0o022)) throw new Error('Unsafe workflow journal directory');
    for (let parent = dirname(this.root); ; parent = dirname(parent)) {
      const ancestor = await lstat(parent);
      if (!ancestor.isDirectory() || (parent !== dirname(parent) && ![0, process.getuid()].includes(ancestor.uid))
        || ((ancestor.mode & 0o022) && !(ancestor.uid === 0 && (ancestor.mode & 0o1000)))) throw new Error(`Unsafe workflow journal ancestor: ${parent} (uid=${ancestor.uid}, mode=${(ancestor.mode & 0o7777).toString(8)})`);
      if (parent === dirname(parent)) break;
    }
    for (const file of await readdir(this.root)) {
      if (!/^[a-f0-9]{64}\.json$/.test(file)) continue;
      const key = file.slice(0, -5);
      let lease;
      try { lease = await this.lease(key); }
      catch (error) {
        if (['EAGAIN', 'EWOULDBLOCK'].includes(error.code)) continue;
        throw error;
      }
      try {
        const row = await this.read(key);
        if (row.status === 'running') await this.save(key, { ...row, status: 'interrupted', finishedAt: Math.max(row.startedAt, Date.now()), activeAgents: 0 });
      } finally { await lease.close(); }
    }
  }

  async lease(key) {
    const path = join(this.root, `${key}.lock`);
    const file = await open(path, constants.O_CREAT | constants.O_RDWR | constants.O_NOFOLLOW, 0o600);
    try {
      const info = await file.stat();
      if (!info.isFile() || info.nlink !== 1 || info.uid !== process.getuid() || (info.mode & 0o022)) throw new Error('Unsafe workflow journal lock');
      await this.lockExclusive(file.fd);
      const current = await lstat(path);
      if (info.dev !== current.dev || info.ino !== current.ino) throw new Error('Workflow journal lock changed');
      return file;
    } catch (error) { await file.close(); throw error; }
  }

  async read(key) {
    const file = await open(join(this.root, `${key}.json`), constants.O_RDONLY | constants.O_NOFOLLOW);
    try {
      const info = await file.stat();
      if (!info.isFile() || info.size > 16384 || info.nlink !== 1 || info.uid !== process.getuid() || (info.mode & 0o022)) throw new Error('Unsafe workflow journal record');
      const buffer = Buffer.alloc(16385);
      let size = 0;
      while (size < buffer.length) {
        const result = await file.read(buffer, size, buffer.length - size, size);
        if (result.bytesRead === 0) break;
        size += result.bytesRead;
      }
      if (size > 16384) throw new Error('Workflow journal record exceeds size limit');
      const row = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(buffer.subarray(0, size)));
      return validateRecord(row, key);
    } finally { await file.close(); }
  }

  async save(key, row) {
    const serialized = `${JSON.stringify(validateRecord(row, key))}\n`;
    if (Buffer.byteLength(serialized) > 16384) throw new Error('Workflow journal record exceeds size limit');
    const destination = join(this.root, `${key}.json`);
    const temporary = join(this.root, `${key}.${randomUUID()}.tmp`);
    if (resolve(destination) !== `${this.root}/${key}.json` || !/^[a-f0-9]{64}$/.test(key)) throw new Error('Unsafe workflow journal destination');
    const file = await open(temporary, constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY | constants.O_NOFOLLOW, 0o600);
    try { await file.writeFile(serialized); await file.sync(); }
    finally { await file.close(); }
    await rename(temporary, destination);
    const directory = await open(this.root, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
    try { await directory.sync(); } finally { await directory.close(); }
  }

  start(input) {
    return this.enqueue(async () => {
      const id = identity(input.id);
      const key = fileKey(id);
      if (this.active.has(id)) throw new Error('Workflow journal id already active');
      const row = {
        version: 1, id, parentSessionId: identity(input.parentSessionId), name: identity(input.name),
        startedAt: natural(input.startedAt, 'startedAt'), deadlineAt: natural(input.deadlineAt, 'deadlineAt'),
        maxTotalAgents: natural(input.maxTotalAgents, 'maxTotalAgents', 1),
        maxConcurrentAgents: natural(input.maxConcurrentAgents, 'maxConcurrentAgents', 1),
        agentsStarted: 0, activeAgents: 0, status: 'running',
      };
      if (row.deadlineAt <= row.startedAt || row.maxConcurrentAgents > row.maxTotalAgents) throw new Error('Invalid workflow journal limits');
      const lease = await this.lease(key);
      try {
        try { await lstat(join(this.root, `${key}.json`)); throw new Error('Workflow journal id already exists'); }
        catch (error) { if (error.code !== 'ENOENT') throw error; }
        await this.save(key, row);
        this.active.set(id, { row, key, lease });
      } catch (error) { await lease.close(); throw error; }
    });
  }

  update(input) {
    return this.enqueue(async () => {
      const entry = this.active.get(identity(input.id));
      if (!entry) throw new Error('Workflow journal run is not active');
      const agentsStarted = natural(input.agentsStarted, 'agentsStarted');
      const activeAgents = natural(input.activeAgents, 'activeAgents');
      if (agentsStarted < entry.row.agentsStarted || agentsStarted > entry.row.maxTotalAgents || activeAgents > entry.row.maxConcurrentAgents || activeAgents > agentsStarted) throw new Error('Workflow journal budget exceeded');
      const row = { ...entry.row, agentsStarted, activeAgents };
      await this.save(entry.key, row);
      entry.row = row;
    });
  }

  finish(input) {
    return this.enqueue(async () => {
      const entry = this.active.get(identity(input.id));
      if (!entry) throw new Error('Workflow journal run is not active');
      if (!['completed', 'cancelled', 'error'].includes(input.stopReason)) throw new Error('Invalid workflow stop reason');
      const agentsStarted = natural(input.agentsStarted, 'agentsStarted');
      if (agentsStarted < entry.row.agentsStarted || agentsStarted > entry.row.maxTotalAgents) throw new Error('Invalid workflow final count');
      await this.save(entry.key, { ...entry.row, status: input.stopReason, agentsStarted, activeAgents: 0, finishedAt: natural(input.finishedAt, 'finishedAt') });
      await entry.lease.close();
      this.active.delete(input.id);
    });
  }

  async list() {
    await this.tail;
    const rows = [];
    for (const file of await readdir(this.root)) {
      if (/^[a-f0-9]{64}\.json$/.test(file)) rows.push(await this.read(file.slice(0, -5)));
    }
    return rows.sort((a, b) => b.startedAt - a.startedAt).slice(0, 100);
  }

  async close() {
    await this.tail;
    this.closed = true;
    for (const { lease } of this.active.values()) await lease.close();
    this.active.clear();
  }
}
