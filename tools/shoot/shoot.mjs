#!/usr/bin/env node
// Headless-Chrome screenshot harness for the NextCue web build.
//
// Drives Chrome over the DevTools protocol with Node's built-in WebSocket
// (Node >= 22), so it needs no npm packages. A scenario is a JSON file of
// steps; see tools/shoot/scenarios/*.json.
//
//   node tools/shoot/shoot.mjs tools/shoot/scenarios/profile_shelf.json
//
// Step vocabulary:
//   {"viewport": {"width": 390, "height": 844, "dpr": 3}}
//   {"goto": "http://localhost:8099/"}          full navigation
//   {"hash": "/profile"}                         in-app route change
//   {"seed": {"key": value, ...}}                shared_preferences entries
//   {"clearStorage": true}
//   {"reload": true}
//   {"waitFlutter": 30000}                       until <flutter-view> exists
//   {"wait": 1500}                               milliseconds
//   {"tap": [x, y]}                              CSS pixels
//   {"drag": {"from": [x, y], "to": [x, y], "ms": 400}}
//   {"wheel": {"at": [x, y], "dy": 600}}
//   {"eval": "document.title"}                   result is logged
//   {"shot": "docs/audit/before-profile.png"}    relative to the app root
//   {"shotWebp": "...", "quality": 82}

import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

const appRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

const chromeCandidates = [
  process.env.CHROME_PATH,
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
  '/usr/bin/google-chrome',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
].filter(Boolean);

function findChrome() {
  const hit = chromeCandidates.find((p) => existsSync(p));
  if (!hit) throw new Error('Chrome not found; set CHROME_PATH');
  return hit;
}

class Cdp {
  constructor(ws) {
    this.ws = ws;
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = [];
    ws.onmessage = (ev) => {
      const msg = JSON.parse(typeof ev.data === 'string' ? ev.data : ev.data.toString());
      if (msg.id && this.pending.has(msg.id)) {
        const { resolve: ok, reject: fail } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        if (msg.error) fail(new Error(`${msg.error.message} (${msg.error.code})`));
        else ok(msg.result);
      } else if (msg.method) {
        for (const l of this.listeners) l(msg);
      }
    };
  }

  static async connect(url) {
    const ws = new WebSocket(url);
    await new Promise((ok, fail) => {
      ws.onopen = ok;
      ws.onerror = (e) => fail(new Error(`WebSocket error: ${e.message ?? e}`));
    });
    return new Cdp(ws);
  }

  send(method, params = {}, sessionId) {
    const id = this.nextId++;
    const payload = { id, method, params };
    if (sessionId) payload.sessionId = sessionId;
    this.ws.send(JSON.stringify(payload));
    return new Promise((ok, fail) => this.pending.set(id, { resolve: ok, reject: fail }));
  }

  close() {
    try { this.ws.close(); } catch { /* already closed */ }
  }
}

async function waitForDevtools(port, timeoutMs = 15000) {
  const until = Date.now() + timeoutMs;
  while (Date.now() < until) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/json/version`);
      if (res.ok) return (await res.json()).webSocketDebuggerUrl;
    } catch { /* not up yet */ }
    await sleep(150);
  }
  throw new Error('Chrome DevTools endpoint did not come up');
}

async function main() {
  const scenarioPath = process.argv[2];
  if (!scenarioPath) {
    console.error('usage: node tools/shoot/shoot.mjs <scenario.json>');
    process.exit(2);
  }
  // Strip a UTF-8 BOM: Windows PowerShell 5.1 writes one with -Encoding utf8.
  const scenario = JSON.parse(readFileSync(resolve(scenarioPath), 'utf8').replace(/^﻿/, ''));
  const steps = scenario.steps ?? scenario;

  const port = 9300 + Math.floor(Math.random() * 600);
  const profile = mkdtempSync(join(tmpdir(), 'nextcue-shoot-'));
  const chrome = spawn(findChrome(), [
    '--headless=new',
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${profile}`,
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-extensions',
    '--hide-scrollbars',
    '--mute-audio',
    '--enable-unsafe-swiftshader',
    '--ignore-gpu-blocklist',
    'about:blank',
  ], { stdio: 'ignore' });

  let cdp;
  try {
    cdp = await Cdp.connect(await waitForDevtools(port));
    const { targetId } = await cdp.send('Target.createTarget', { url: 'about:blank' });
    const { sessionId } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
    const s = (method, params) => cdp.send(method, params, sessionId);
    await s('Page.enable');
    await s('Runtime.enable');

    const logs = [];
    cdp.listeners.push((msg) => {
      if (msg.sessionId !== sessionId) return;
      if (msg.method === 'Runtime.consoleAPICalled') {
        const text = msg.params.args.map((a) => a.value ?? a.description ?? '').join(' ');
        logs.push(`[console.${msg.params.type}] ${text}`);
      } else if (msg.method === 'Runtime.exceptionThrown') {
        logs.push(`[exception] ${msg.params.exceptionDetails?.exception?.description ?? msg.params.exceptionDetails?.text}`);
      }
    });

    const evaluate = async (expression) => {
      const r = await s('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
      if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description ?? 'eval failed');
      return r.result.value;
    };

    const pointer = async (type, x, y, buttons) => s('Input.dispatchMouseEvent', {
      type, x, y, button: 'left', buttons, clickCount: 1, pointerType: 'mouse',
    });

    for (const step of steps) {
      const [kind] = Object.keys(step);
      const v = step[kind];
      switch (kind) {
        case 'viewport':
          await s('Emulation.setDeviceMetricsOverride', {
            width: v.width, height: v.height, deviceScaleFactor: v.dpr ?? 1, mobile: v.mobile ?? true,
          });
          break;
        case 'goto':
          await s('Page.navigate', { url: v });
          await sleep(500);
          break;
        case 'hash':
          await evaluate(`location.hash = ${JSON.stringify('#' + v)}`);
          break;
        case 'clearStorage':
          await evaluate('localStorage.clear()');
          break;
        case 'seed': {
          const body = Object.entries(v)
            .map(([k, val]) => `localStorage.setItem(${JSON.stringify('flutter.' + k)}, ${JSON.stringify(JSON.stringify(val))});`)
            .join('\n');
          await evaluate(body);
          break;
        }
        case 'reload':
          await s('Page.reload', { ignoreCache: true });
          await sleep(500);
          break;
        case 'waitFlutter': {
          const until = Date.now() + (v || 30000);
          while (Date.now() < until) {
            if (await evaluate("!!document.querySelector('flutter-view')")) break;
            await sleep(250);
          }
          break;
        }
        case 'wait':
          await sleep(v);
          break;
        case 'tap':
          await pointer('mouseMoved', v[0], v[1], 0);
          await pointer('mousePressed', v[0], v[1], 1);
          await sleep(60);
          await pointer('mouseReleased', v[0], v[1], 0);
          break;
        case 'drag': {
          const steps = Math.max(8, Math.round((v.ms ?? 300) / 16));
          const [x0, y0] = v.from;
          const [x1, y1] = v.to;
          await pointer('mouseMoved', x0, y0, 0);
          await pointer('mousePressed', x0, y0, 1);
          for (let i = 1; i <= steps; i++) {
            const t = i / steps;
            await pointer('mouseMoved', x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, 1);
            await sleep(16);
          }
          await pointer('mouseReleased', x1, y1, 0);
          break;
        }
        case 'wheel':
          await s('Input.dispatchMouseEvent', {
            type: 'mouseWheel', x: v.at[0], y: v.at[1], deltaX: v.dx ?? 0, deltaY: v.dy ?? 0,
          });
          break;
        case 'eval':
          console.log(`eval → ${JSON.stringify(await evaluate(v))}`);
          break;
        case 'shot':
        case 'shotWebp': {
          const out = resolve(appRoot, v);
          mkdirSync(dirname(out), { recursive: true });
          const format = kind === 'shotWebp' ? 'webp' : 'png';
          const { data } = await s('Page.captureScreenshot', {
            format, quality: format === 'webp' ? (step.quality ?? 82) : undefined,
          });
          writeFileSync(out, Buffer.from(data, 'base64'));
          console.log(`shot → ${v}`);
          break;
        }
        default:
          throw new Error(`unknown step: ${kind}`);
      }
    }

    if (logs.length) {
      console.log('--- page console ---');
      for (const l of logs.slice(-40)) console.log(l);
    }
  } finally {
    cdp?.close();
    chrome.kill();
    await sleep(300);
    try { rmSync(profile, { recursive: true, force: true }); } catch { /* chrome may hold files briefly */ }
  }
}

main().catch((e) => {
  console.error(e.stack ?? e);
  process.exit(1);
});
