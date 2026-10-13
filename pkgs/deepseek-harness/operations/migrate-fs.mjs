import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { ensure, MAX_FILE } from './migrate-registry.mjs';

export const hash = data => createHash('sha256').update(data).digest('hex');
export const identity = stat => Object.fromEntries(['dev', 'ino', 'mode', 'uid', 'gid', 'nlink', 'size', 'mtimeNs', 'ctimeNs'].map(key => [key, String(stat[key])]));
export const directoryIdentity = stat => Object.fromEntries(['dev', 'ino', 'mode', 'uid', 'gid'].map(key => [key, String(stat[key])]));
const equal = (left, right) => JSON.stringify(left) === JSON.stringify(right);

export class SafeTree {
  constructor(home) {
    ensure(typeof home === 'string' && path.isAbsolute(home) && path.resolve(home) === home && home !== '/' && !home.includes('\0'), 'An explicit canonical absolute DSH_HOME is required');
    this.home = home;
    this.handles = new Map();
    this.lock = null;
    try {
      ensure(fs.realpathSync(home) === home, 'DSH_HOME ancestors must not be symlinks');
      for (let ancestor = path.dirname(home); ; ancestor = path.dirname(ancestor)) {
        const info = fs.lstatSync(ancestor, { bigint: true });
        ensure(info.isDirectory() && (ancestor === '/' || info.uid === 0n || info.uid === BigInt(process.getuid())), 'Unsafe ancestor ownership');
        ensure((info.mode & 0o022n) === 0n || (info.uid === 0n && (info.mode & 0o1000n) !== 0n), 'Unsafe ancestor permissions');
        if (ancestor === '/') break;
      }
      const before = fs.lstatSync(home, { bigint: true });
      this.check(before, home);
      ensure(before.isDirectory(), 'DSH_HOME must be a directory');
      const fd = fs.openSync(home, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_DIRECTORY);
      this.handles.set('', { fd, info: directoryIdentity(before) });
      ensure(equal(identity(before), identity(fs.fstatSync(fd, { bigint: true }))), 'DSH_HOME changed during open');
      this.device = before.dev;
      this.assertDirectories();
    } catch (error) { this.close(); throw error; }
  }
  check(stat, relative) {
    ensure(stat.isDirectory() || stat.isFile(), `Unsafe type or symlink: ${relative}`);
    ensure(stat.uid === BigInt(process.getuid()) && (stat.mode & 0o022n) === 0n, `Unsafe ownership or permissions: ${relative}`);
    if (this.device !== undefined) ensure(stat.dev === this.device, `Cross-device path: ${relative}`);
    if (stat.isFile()) ensure(stat.nlink === 1n, `Unexpected hardlink: ${relative}`);
  }
  parts(relative) {
    ensure(typeof relative === 'string' && !relative.includes('\0') && (relative === '' || relative.split('/').every(part => part && part !== '.' && part !== '..')), 'Unsafe relative path');
    return relative === '' ? [] : relative.split('/');
  }
  raw(relative) {
    this.parts(relative);
    if (relative === '') return this.home;
    const parent = path.posix.dirname(relative);
    const handle = this.directory(parent === '.' ? '' : parent);
    return `/proc/self/fd/${handle.fd}/${path.posix.basename(relative)}`;
  }
  assertDirectories() {
    ensure(fs.realpathSync(this.home) === this.home, 'DSH_HOME ancestor changed');
    for (const [relative, handle] of this.handles) {
      const current = fs.lstatSync(relative === '' ? this.home : this.raw(relative), { bigint: true });
      this.check(current, relative);
      ensure(equal(directoryIdentity(current), handle.info) && equal(directoryIdentity(fs.fstatSync(handle.fd, { bigint: true })), handle.info), `Directory inode changed: ${relative || 'DSH_HOME'}`);
    }
  }
  directory(relative) {
    this.parts(relative);
    if (this.handles.has(relative)) return this.handles.get(relative);
    const target = this.raw(relative);
    const before = fs.lstatSync(target, { bigint: true });
    this.check(before, relative);
    ensure(before.isDirectory(), `Expected directory: ${relative}`);
    const fd = fs.openSync(target, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_DIRECTORY);
    const handle = { fd, info: directoryIdentity(before) };
    this.handles.set(relative, handle);
    ensure(equal(identity(before), identity(fs.fstatSync(fd, { bigint: true }))), `Directory changed during open: ${relative}`);
    return handle;
  }
  stat(relative, optional = false) {
    this.assertDirectories();
    let value;
    try { value = fs.lstatSync(this.raw(relative), { bigint: true }); }
    catch (error) { if (optional && error.code === 'ENOENT') return null; throw error; }
    this.check(value, relative);
    this.assertDirectories();
    return value;
  }
  entries(relative) {
    const before = this.stat(relative);
    ensure(before.isDirectory(), `Expected directory: ${relative}`);
    const handle = this.directory(relative);
    const directory = fs.opendirSync(`/proc/self/fd/${handle.fd}`);
    const names = [];
    try {
      for (let entry; (entry = directory.readSync()) !== null;) {
        ensure(names.length < 10_000, `Directory entry bound exceeded: ${relative}`);
        names.push(entry.name);
      }
    } finally { directory.closeSync(); }
    ensure(equal(identity(before), identity(this.stat(relative))), `Directory changed during scan: ${relative}`);
    return names.sort();
  }
  read(relative) {
    const before = this.stat(relative);
    ensure(before.isFile() && before.size <= BigInt(MAX_FILE), `Expected bounded regular file: ${relative}`);
    const fd = fs.openSync(this.raw(relative), fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK | fs.constants.O_NOATIME);
    try {
      ensure(equal(identity(before), identity(fs.fstatSync(fd, { bigint: true }))), `File changed during open: ${relative}`);
      const data = Buffer.alloc(Number(before.size) + 1);
      let offset = 0;
      while (offset < data.length) {
        const count = fs.readSync(fd, data, offset, data.length - offset, offset);
        if (!count) break;
        offset += count;
      }
      ensure(offset === Number(before.size), `File size changed during bounded read: ${relative}`);
      ensure(equal(identity(before), identity(fs.fstatSync(fd, { bigint: true }))) && equal(identity(before), identity(this.stat(relative))), `File changed during read: ${relative}`);
      const bytes = data.subarray(0, offset);
      return { data: bytes, identity: identity(before), sha256: hash(bytes) };
    } finally { fs.closeSync(fd); }
  }
  lockExclusive(executable) {
    ensure(executable && path.isAbsolute(executable), 'DSH_MIGRATE_FLOCK must name the absolute util-linux flock executable');
    const relative = '.operations.lock';
    const stat = this.stat(relative);
    ensure(stat.isFile(), 'Operations lock must be a regular single-link file');
    const fd = fs.openSync(this.raw(relative), fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
    this.lock = { fd, info: identity(stat) };
    ensure(equal(identity(fs.fstatSync(fd, { bigint: true })), this.lock.info), 'Operations lock inode changed');
    const result = spawnSync(executable, ['--exclusive', '--nonblock', '--conflict-exit-code', '75', '3'], { stdio: ['ignore', 'pipe', 'pipe', fd], timeout: 5000 });
    ensure(!result.error && result.status === 0, result.status === 75 ? 'Live .operations.lock; stop all packaged DSH writers before migration' : 'Unable to acquire exclusive flock');
    ensure(/\bFLOCK\s+ADVISORY\s+WRITE\b/.test(fs.readFileSync(`/proc/self/fdinfo/${fd}`, 'utf8')), 'Exclusive flock was not established');
    this.assertLock();
  }
  assertLock() {
    ensure(this.lock && equal(identity(this.stat('.operations.lock')), this.lock.info), 'Operations lock inode changed');
  }
  sync(relative) {
    this.assertLock();
    fs.fsyncSync(this.directory(relative).fd);
    this.assertDirectories();
  }
  mkdir(relative) {
    this.assertLock();
    ensure(this.stat(relative, true) === null, `Directory already exists: ${relative}`);
    fs.mkdirSync(this.raw(relative), { mode: 0o700 });
    this.directory(relative);
    this.sync(path.posix.dirname(relative) === '.' ? '' : path.posix.dirname(relative));
    this.sync(relative);
  }
  writeNew(relative, data, mode = 0o600) {
    this.assertLock();
    ensure(data.length <= MAX_FILE, 'Write byte bound exceeded');
    ensure(this.stat(relative, true) === null, `Refusing existing file: ${relative}`);
    const fd = fs.openSync(this.raw(relative), fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o600);
    try {
      fs.writeFileSync(fd, data);
      fs.fchmodSync(fd, mode);
      fs.fsyncSync(fd);
      const current = this.stat(relative);
      ensure(equal(identity(current), identity(fs.fstatSync(fd, { bigint: true }))), `Written file inode changed: ${relative}`);
    } finally { fs.closeSync(fd); }
    this.sync(path.posix.dirname(relative));
    return this.read(relative);
  }
  assertFile(relative, expected) {
    if (expected === null) {
      ensure(this.stat(relative, true) === null, `Unexpected existing target: ${relative}`);
      return;
    }
    const current = this.read(relative);
    ensure(current.sha256 === expected.sha256 && (!expected.identity || equal(current.identity, expected.identity)), `Unrelated or changed bytes/inode: ${relative}`);
  }
  rename(from, to, expectedSource, expectedTarget) {
    this.assertLock();
    this.assertFile(from, expectedSource);
    this.assertFile(to, expectedTarget);
    fs.renameSync(this.raw(from), this.raw(to));
    this.sync(path.posix.dirname(to));
    if (path.posix.dirname(to) !== path.posix.dirname(from)) this.sync(path.posix.dirname(from));
    this.assertFile(to, { sha256: expectedSource.sha256 });
  }
  remove(relative, expected) {
    this.assertLock();
    this.assertFile(relative, expected);
    fs.unlinkSync(this.raw(relative));
    this.sync(path.posix.dirname(relative));
  }
  close() {
    if (this.lock) { fs.closeSync(this.lock.fd); this.lock = null; }
    for (const { fd } of [...this.handles.values()].reverse()) fs.closeSync(fd);
    this.handles.clear();
  }
}
