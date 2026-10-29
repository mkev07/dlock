import { createServer } from 'node:http';
import { mkdirSync, chmodSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { LicenseError, LicenseStore, LicensingService, verifyWebhook } from './licensing.mjs';
import { loadTestSigner } from './entitlements.mjs';

const mode = process.env.DLOCK_LICENSE_MODE ?? 'mock';
const path = resolve(process.env.DLOCK_LICENSE_DATABASE ?? `./data/${mode}-licenses.sqlite`);
mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
const store = new LicenseStore(path);
chmodSync(path, 0o600);
if (mode === 'mock') store.issueTestKey('DLOCK-LOCAL-TEST-ONLY');
const businessID = process.env.DODO_TEST_BUSINESS_ID;
const productID = process.env.DODO_TEST_PRODUCT_ID;
const signingPath = resolve('./data/test-signing-private.pem');
mkdirSync(dirname(signingPath), { recursive: true, mode: 0o700 });
const signer = loadTestSigner(signingPath);
const service = new LicensingService({ store, mode, apiKey: process.env.DODO_TEST_API_KEY, productID, businessID, signer });
const limits = new Map();

const server = createServer(async (request, response) => {
  response.setHeader('Content-Type', 'application/json');
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('X-Content-Type-Options', 'nosniff');
  try {
    if (request.headers.origin || !['127.0.0.1:8787', 'localhost:8787'].includes(request.headers.host)) throw new LicenseError(403, 'Native local testing only.');
    if (request.method !== 'POST') throw new LicenseError(405, 'Use POST.');
    const now = Date.now();
    const address = request.socket.remoteAddress;
    for (const [key, value] of limits) if (value.until < now) limits.delete(key);
    const entry = limits.get(address) ?? { count: 0, until: now + 60000 };
    limits.set(address, entry);
    if (++entry.count > 60) throw new LicenseError(429, 'Too many requests. Retry in a minute.');
    const chunks = [];
    let size = 0;
    for await (const chunk of request) {
      size += chunk.length;
      if (size > 65536) throw new LicenseError(413, 'Request too large.');
      chunks.push(chunk);
    }
    const raw = Buffer.concat(chunks).toString('utf8');
    let result;
    if (request.url === '/v1/webhooks/dodo') {
      if (mode !== 'dodo-test') throw new LicenseError(404, 'Dodo webhooks are disabled in mock mode.');
      const event = verifyWebhook(raw, request.headers, process.env.DODO_TEST_WEBHOOK_SECRET);
      result = store.recordPayment(event, request.headers['webhook-id'], businessID, productID);
    } else {
      if (!request.headers['content-type']?.startsWith('application/json')) throw new LicenseError(415, 'Use JSON.');
      const match = /^\/v1\/licenses\/(activate|validate|deactivate)$/.exec(request.url);
      if (!match) throw new LicenseError(404, 'Unknown route.');
      let body;
      try { body = JSON.parse(raw); } catch { throw new LicenseError(400, 'Invalid JSON.'); }
      result = await service.run(match[1], body);
    }
    response.writeHead(200).end(JSON.stringify(result));
  } catch (error) {
    const known = error instanceof LicenseError;
    response.writeHead(known ? error.status : 503).end(JSON.stringify({ error: known ? error.message : 'Test licensing service unavailable. Retry without deleting your saved activation.' }));
  }
});
server.requestTimeout = 20000;
server.headersTimeout = 10000;
server.listen(8787, '127.0.0.1', () => console.log(`Dlock licensing: ${mode}, loopback only, port 8787. No live payments.`));
for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, () => server.close(() => { store.close(); process.exit(0); }));
