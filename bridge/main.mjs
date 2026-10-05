import { readFile, writeFile, mkdir, stat, rename, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';

export async function installDraplineCE(window) {
  const gameRoot = fileURLToPath(new URL('../../../../', import.meta.url)).replace(/[\\/]+$/, '').toLowerCase();
  const tag = createHash('sha256').update(gameRoot).digest('hex').slice(0, 12);
  const runtime = process.env.DRAPLINE_CE_RUNTIME || join(tmpdir(), 'DRAPLINE-CE-' + tag);
  await mkdir(runtime, { recursive: true });
  const source = await readFile(new URL('./renderer.js', import.meta.url), 'utf8');
  const server = `${process.pid}-${Date.now()}`;
  let available = false, busy = false, lastToken = '', ackClient = '', ackSeq = 0, lastError = '';
  const statusPath = join(runtime, 'status.tsv');
  const publish = async snapshot => {
    const status = { protocol: 1, pid: process.pid, server, time: Date.now(), game_root: gameRoot, client: ackClient, seq: ackSeq, ...snapshot };
    const text = Object.entries(status).map(([k,v]) => `${k}\t${String(v ?? '').replace(/[\r\n\t]/g, ' ')}`).join('\n') + '\n';
    const tmp = statusPath + `.${process.pid}.tmp`;
    await writeFile(tmp, text, 'utf8');
    for (let attempt = 0; ; attempt++) {
      try { await rename(tmp, statusPath); break; }
      catch (e) {
        if (!['EPERM', 'EBUSY', 'EACCES'].includes(e.code) || attempt >= 5) throw e;
        await new Promise(resolve => setTimeout(resolve, 10 * (attempt + 1)));
      }
    }
  };
  window.webContents.on('did-start-loading', () => { available = false; });
  window.webContents.on('did-finish-load', async () => {
    try { await window.webContents.executeJavaScript(source); available = true; }
    catch (e) { lastError = String(e.message); }
  });
  await publish({ ready: 0, scene: 'Loading', error: '' });
  const timer = setInterval(async () => {
    if (busy || window.isDestroyed()) return;
    busy = true;
    try {
      if (!available) { await publish({ ready: 0, scene: 'Loading', error: lastError }); return; }
      let client = '', lease = false;
      try {
        const heartbeat = join(runtime, 'heartbeat.txt');
        const [s, text] = await Promise.all([stat(heartbeat), readFile(heartbeat, 'utf8')]);
        client = text.trim();
        lease = /^[A-Za-z0-9_-]{1,80}$/.test(client) && Date.now() - s.mtimeMs < 2500;
      } catch {}
      let request = null;
      try {
        const raw = await readFile(join(runtime, 'request.tsv'), 'utf8');
        const p = raw.trim().split('\t');
        if (lease && raw.endsWith('\n') && p.length === 5 && p[0] === client && raw !== lastToken && /^\d+$/.test(p[1])) {
          request = { op: p[2], key: p[3], value: Number(p[4]) };
          lastToken = raw; ackClient = client; ackSeq = Number(p[1]);
        }
      } catch {}
      const state = await window.webContents.executeJavaScript(`globalThis.__drapCE.tick(${JSON.stringify(request)},${lease},${JSON.stringify(client)})`);
      if (request) lastError = state.error;
      state.error = lastError;
      await publish(state);
    } catch (e) {
      lastError = String(e.message || e);
      try { await publish({ ready: 0, scene: 'Disconnected', error: lastError }); } catch {}
    } finally { busy = false; }
  }, 100);
  timer.unref();
  window.on('closed', () => {
    clearInterval(timer);
    readFile(statusPath, 'utf8').then(text => {
      if (text.includes(`server\t${server}\n`)) return rm(statusPath, { force: true });
    }).catch(() => {});
  });
}
