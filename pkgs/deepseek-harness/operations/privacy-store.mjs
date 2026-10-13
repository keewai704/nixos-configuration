import { DatabaseSync } from 'node:sqlite';
import { constants, closeSync, fstatSync, fsyncSync, lstatSync, mkdirSync, openSync, realpathSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';

export const PRIVACY_CHANNELS = ['session-telemetry-otel', 'session-log-deepseek', 'plugin-package-inventory-deepseek', 'product-analytics'];

function safeDirectory(path) {
  const target = resolve(path);
  for (let current = target; ; current = dirname(current)) {
    let info;
    try { info = lstatSync(current); }
    catch (error) { if (error.code === 'ENOENT') continue; throw error; }
    const root = current === dirname(current);
    if (!info.isDirectory() || (!root && ![0, process.getuid()].includes(info.uid))
      || ((info.mode & 0o022) && !(info.uid === 0 && !root && (info.mode & 0o1000)))) throw new Error('Unsafe privacy-store directory');
    if (root) break;
  }
  mkdirSync(target, { recursive: true, mode: 0o700 });
  if (realpathSync(target) !== target || lstatSync(target).uid !== process.getuid()) throw new Error('Unsafe privacy-store path');
  const parent = openSync(dirname(target), constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
  try { fsyncSync(parent); } finally { closeSync(parent); }
  return target;
}

export class PrivacyStore {
  constructor(directory) {
    this.directory = safeDirectory(directory);
    const file = join(this.directory, 'privacy.sqlite');
    const fd = openSync(file, constants.O_CREAT | constants.O_RDWR | constants.O_NOFOLLOW, 0o600);
    try {
      const info = fstatSync(fd);
      if (!info.isFile() || info.nlink !== 1 || info.uid !== process.getuid() || (info.mode & 0o077)) throw new Error('Unsafe privacy-store database');
      const current = lstatSync(file);
      if (current.dev !== info.dev || current.ino !== info.ino) throw new Error('Privacy-store database changed');
    } finally { closeSync(fd); }
    for (const suffix of ['-journal', '-wal', '-shm']) {
      let info;
      try { info = lstatSync(file + suffix); } catch (error) { if (error.code === 'ENOENT') continue; throw error; }
      if (!info.isFile() || info.nlink !== 1 || info.uid !== process.getuid() || (info.mode & 0o077)) throw new Error('Unsafe privacy-store sidecar');
    }
    this.db = new DatabaseSync(file);
    this.db.exec('PRAGMA busy_timeout=5000; PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; PRAGMA trusted_schema=OFF;');
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const version = this.db.prepare('PRAGMA user_version').get().user_version;
      if (version !== 0 && version !== 1) throw new Error('Unsupported privacy-store version');
      const objects = this.db.prepare("SELECT type,name FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'").all();
      if (version === 0) {
        if (objects.length) throw new Error('Unversioned privacy-store is not empty');
        this.db.exec('CREATE TABLE privacy_choices (channel TEXT PRIMARY KEY, enabled INTEGER NOT NULL CHECK(enabled IN (0,1)), revision INTEGER NOT NULL CHECK(revision>=0), updated_at INTEGER NOT NULL) STRICT;');
        const insert = this.db.prepare('INSERT INTO privacy_choices VALUES (?,0,0,0)');
        for (const channel of PRIVACY_CHANNELS) insert.run(channel);
      } else {
        if (objects.length !== 1 || objects[0].type !== 'table' || objects[0].name !== 'privacy_choices') throw new Error('Unexpected privacy-store objects');
        const columns = this.db.prepare('PRAGMA table_info(privacy_choices)').all();
        if (columns.map(row => `${row.name}:${row.type}`).join(',') !== 'channel:TEXT,enabled:INTEGER,revision:INTEGER,updated_at:INTEGER') throw new Error('Unexpected privacy-store columns');
        const channels = this.db.prepare('SELECT channel FROM privacy_choices').all().map(row => row.channel).sort();
        if (JSON.stringify(channels) !== JSON.stringify([...PRIVACY_CHANNELS].sort())) throw new Error('Incomplete privacy-store channels');
        for (const channel of PRIVACY_CHANNELS) this.get(channel);
      }
      if (this.db.prepare('PRAGMA quick_check').get().quick_check !== 'ok') throw new Error('Privacy-store integrity check failed');
      this.db.exec('PRAGMA user_version=1; COMMIT');
    } catch (error) { this.db.exec('ROLLBACK'); this.db.close(); throw error; }
    const directoryFd = openSync(this.directory, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
    try { fsyncSync(directoryFd); } finally { closeSync(directoryFd); }
  }

  get(channel) {
    if (!PRIVACY_CHANNELS.includes(channel)) throw new Error('Unknown privacy channel');
    const row = this.db.prepare('SELECT enabled, revision, updated_at FROM privacy_choices WHERE channel=?').get(channel);
    if (!row || ![0, 1].includes(row.enabled) || !Number.isSafeInteger(row.revision) || row.revision < 0 || !Number.isSafeInteger(row.updated_at)) throw new Error('Malformed privacy choice');
    return { enabled: row.enabled === 1, revision: row.revision, updatedAt: row.updated_at };
  }

  set(channel, enabled, expectedRevision, confirmation) {
    if (!PRIVACY_CHANNELS.includes(channel) || typeof enabled !== 'boolean' || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) throw new Error('Invalid privacy update');
    if (confirmation !== `${enabled ? 'ENABLE' : 'DISABLE'} ${channel}`) throw new Error('Explicit privacy confirmation is required');
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const current = this.get(channel);
      if (current.revision !== expectedRevision) throw new Error('Privacy configuration changed; refresh before retrying');
      if (current.enabled !== enabled) {
        this.db.prepare('UPDATE privacy_choices SET enabled=?, revision=revision+1, updated_at=? WHERE channel=?').run(Number(enabled), Date.now(), channel);
      }
      const result = this.get(channel);
      this.db.exec('COMMIT');
      return result;
    } catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }

  close() { this.db.close(); }
}
