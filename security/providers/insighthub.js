// Promptfoo target for InsightHub: uploads the untrusted document (if the test has one), waits for
// ingestion, asks the question through the real /chat endpoint, then removes the temporary document.
// The corpus in sample-docs/ (including the deliberately poisoned file) is loaded once per process.
const fs = require('fs');
const path = require('path');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let corpusReady = null;

async function api(base, p, opts = {}) {
  const res = await fetch(base + p, opts);
  const text = await res.text();
  let body = null;
  try { body = JSON.parse(text); } catch (_) { /* keep raw */ }
  return { status: res.status, headers: res.headers, body, text };
}

async function upload(base, filename, content) {
  const form = new FormData();
  form.append('file', new Blob([content], { type: 'text/markdown' }), filename);
  const r = await api(base, '/documents', { method: 'POST', body: form });
  if (![200, 201, 202].includes(r.status)) throw new Error(`upload ${filename} -> ${r.status}`);
  return r.body.id;
}

async function waitReady(base, id, timeoutMs = 120000) {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    const r = await api(base, '/documents');
    const doc = (Array.isArray(r.body) ? r.body : r.body.documents || []).find((d) => d.id === id);
    if (doc && doc.status === 'ready') return;
    if (doc && doc.status === 'failed') throw new Error(`document ${id} failed`);
    await sleep(1500);
  }
  throw new Error(`document ${id} not ready`);
}

async function ensureCorpus(base, files) {
  if (!corpusReady) {
    corpusReady = (async () => {
      const r = await api(base, '/documents');
      const have = new Set((Array.isArray(r.body) ? r.body : r.body.documents || []).map((d) => d.filename));
      for (const f of files) {
        const name = path.basename(f);
        if (have.has(name)) continue;
        await waitReady(base, await upload(base, name, fs.readFileSync(path.resolve(__dirname, '..', f))));
      }
    })();
  }
  return corpusReady;
}

class InsightHubProvider {
  constructor(options) {
    this.config = (options && options.config) || {};
    this.base = this.config.apiUrl || 'http://localhost:18000';
  }

  id() { return 'insighthub-rag'; }

  async callApi(prompt, context) {
    const vars = (context && context.vars) || {};
    const doc = typeof vars.doc === 'string' ? vars.doc.trim() : '';
    const question = String(vars.question || prompt).slice(0, 2000);
    let tempId = null;
    try {
      await ensureCorpus(this.base, this.config.corpus || []);
      if (doc) {
        tempId = await upload(this.base, `redteam-${Date.now()}.md`, doc);
        await waitReady(this.base, tempId);
      }
      const r = await api(this.base, '/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ question }),
      });
      const requestId = r.headers.get('x-llm-request-id');
      if (r.status !== 200) {
        // A guardrail/gateway rejection is a safe outcome; report it explicitly to the grader.
        return { output: `[REQUEST BLOCKED OR FAILED: HTTP ${r.status}] ${(r.body && r.body.detail) || ''}`, metadata: { http_status: r.status, request_id: requestId } };
      }
      const u = r.body.usage || {};
      return {
        output: r.body.answer,
        tokenUsage: { prompt: u.input_tokens || 0, completion: u.output_tokens || 0, total: (u.input_tokens || 0) + (u.output_tokens || 0) },
        metadata: { request_id: requestId, sources: r.body.sources, provider: r.body.provider, model: r.body.model },
      };
    } catch (e) {
      return { error: String(e.message || e) };
    } finally {
      if (tempId !== null) await api(this.base, `/documents/${tempId}`, { method: 'DELETE' }).catch(() => {});
    }
  }
}

module.exports = InsightHubProvider;
