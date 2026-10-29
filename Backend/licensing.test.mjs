import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Webhook } from 'standardwebhooks';
import { LicenseStore, LicensingService, priceForBuyer, verifyWebhook } from './licensing.mjs';

const key = 'DLOCK-FIXTURE-KEY';
const firstMac = 'installation-000001';
const secondMac = 'installation-000002';
function fixture(context) {
  const store = new LicenseStore();
  store.issueTestKey(key);
  context.after(() => store.close());
  return { store, service: new LicensingService({ store }) };
}
const request = installation => ({ license_key: key, installation_id: installation, nonce: randomUUID() });

test('all pricing boundaries and invalid input', () => {
  for (const [number, expected] of [[1, 299], [50, 299], [51, 499], [100, 499], [101, 799], [150, 799], [151, 999], [10000, 999]]) {
    assert.equal(priceForBuyer(number), expected);
  }
  for (const invalid of [0, -1, 1.2, '50', NaN]) assert.throws(() => priceForBuyer(invalid));
});

test('activation is lifetime and idempotent on same installation', async context => {
  const { service } = fixture(context);
  const first = await service.run('activate', request(firstMac));
  const retry = await service.run('activate', request(firstMac));
  assert.equal(first.activation_id, retry.activation_id);
  assert.equal(first.expires_at, null);
  assert.equal(first.all_future_updates, true);
  assert.equal(first.max_macs, 1);
});

test('simultaneous activations permit only one Mac', async context => {
  const { service } = fixture(context);
  const results = await Promise.allSettled([service.run('activate', request(firstMac)), service.run('activate', request(secondMac))]);
  assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
  assert.equal(results.find(result => result.status === 'rejected').reason.status, 409);
});

test('deactivate, transfer, and reject old activation', async context => {
  const { service } = fixture(context);
  const first = await service.run('activate', request(firstMac));
  const original = { ...request(firstMac), activation_id: first.activation_id };
  assert.equal((await service.run('validate', original)).status, 'active');
  await service.run('deactivate', original);
  const transferred = await service.run('activate', request(secondMac));
  assert.notEqual(transferred.activation_id, first.activation_id);
  await assert.rejects(service.run('validate', original), { status: 409 });
  await assert.rejects(service.run('deactivate', original), { status: 409 });
});

test('invalid keys, missing identity and forged activation rejected', async context => {
  const { service } = fixture(context);
  await assert.rejects(service.run('activate', { ...request(firstMac), license_key: 'unknown-key' }), { status: 403 });
  await assert.rejects(service.run('activate', { license_key: key }), { status: 400 });
  await assert.rejects(service.run('activate', null), { status: 400 });
  await service.run('activate', request(firstMac));
  await assert.rejects(service.run('validate', { ...request(firstMac), activation_id: 'forged' }), { status: 403 });
});

test('revocation is observed at validation', async context => {
  const { service, store } = fixture(context);
  const active = await service.run('activate', request(firstMac));
  store.db.exec('UPDATE licenses SET revoked = 1');
  await assert.rejects(service.run('validate', { ...request(firstMac), activation_id: active.activation_id }), { status: 403 });
});

test('activation survives service restart without storing plaintext license keys', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'dlock-license-'));
  try {
    let store = new LicenseStore(join(directory, 'licenses.sqlite'));
    store.issueTestKey(key);
    const active = await new LicensingService({ store }).run('activate', request(firstMac));
    assert.equal(store.db.prepare('SELECT key_hash FROM licenses').get().key_hash.includes(key), false);
    store.close();
    store = new LicenseStore(join(directory, 'licenses.sqlite'));
    const result = await new LicensingService({ store }).run('validate', { ...request(firstMac), activation_id: active.activation_id });
    assert.equal(result.status, 'active');
    store.close();
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test('live provider mode is forbidden', context => {
  const { store } = fixture(context);
  assert.throws(() => new LicensingService({ store, mode: 'live' }));
  assert.throws(() => new LicensingService({ store, mode: 'dodo-test' }));
});

test('Dodo adapter uses test host and verifies product and business', async context => {
  const { store } = fixture(context);
  const calls = [];
  const service = new LicensingService({ store, mode: 'dodo-test', apiKey: 'fixture-only', productID: 'dlock-test', businessID: 'business-test', transport: async (url, options) => {
    assert.equal(new URL(url).origin, 'https://test.dodopayments.com');
    calls.push([url, JSON.parse(options.body)]);
    return new Response(JSON.stringify(url.endsWith('activate') ? { id: 'provider-instance', product: { product_id: 'dlock-test' }, business_id: 'business-test' } : { valid: true }), { status: 200 });
  } });
  const result = await service.run('activate', request(firstMac));
  assert.equal(result.environment, 'dodo-test');
  assert.equal(result.activation_id, 'provider-instance');
  assert.equal(calls.length, 2);
});

test('wrong Dodo product rolls back upstream activation', async context => {
  const { store } = fixture(context);
  let rollback = false;
  const service = new LicensingService({ store, mode: 'dodo-test', apiKey: 'fixture-only', productID: 'dlock-test', businessID: 'business-test', transport: async url => {
    if (url.endsWith('/deactivate')) { rollback = true; return new Response(null, { status: 204 }); }
    return new Response(JSON.stringify({ id: 'other-instance', product: { product_id: 'wrong' }, business_id: 'business-test' }));
  } });
  await assert.rejects(service.run('activate', request(firstMac)), { status: 403 });
  assert.equal(rollback, true);
  assert.equal(store.getActivation(key), undefined);
});

test('provider outage during deactivation retains local activation', async context => {
  const { store } = fixture(context);
  store.saveActivation(key, firstMac, 'provider-instance');
  const service = new LicensingService({ store, mode: 'dodo-test', apiKey: 'fixture-only', productID: 'dlock-test', businessID: 'business-test', transport: async () => new Response(null, { status: 503 }) });
  await assert.rejects(service.run('deactivate', { ...request(firstMac), activation_id: 'provider-instance' }), { status: 503 });
  assert.equal(store.getActivation(key).activation, 'provider-instance');
});

test('signed webhooks reject tampering, old timestamps and wrong secrets', () => {
  const secret = randomBytes(32).toString('base64');
  const webhook = new Webhook(secret);
  const body = JSON.stringify({ type: 'payment.succeeded', business_id: 'business-test', data: {} });
  const timestamp = new Date();
  const headers = { 'webhook-id': 'evt-test', 'webhook-timestamp': String(Math.floor(timestamp.getTime() / 1000)), 'webhook-signature': webhook.sign('evt-test', timestamp, body) };
  assert.equal(verifyWebhook(body, headers, secret).type, 'payment.succeeded');
  assert.throws(() => verifyWebhook(body + ' ', headers, secret), { status: 401 });
  assert.throws(() => verifyWebhook(body, headers, randomBytes(32).toString('base64')), { status: 401 });
  const old = new Date(Date.now() - 600000);
  assert.throws(() => verifyWebhook(body, { ...headers, 'webhook-timestamp': String(Math.floor(old.getTime() / 1000)), 'webhook-signature': webhook.sign('evt-test', old, body) }, secret), { status: 401 });
  assert.throws(() => verifyWebhook(body, headers, null), { status: 503 });
});

test('webhook retries and distinct events for same payment do not double-count', context => {
  const { store } = fixture(context);
  const event = { type: 'payment.succeeded', business_id: 'business-test', data: { business_id: 'business-test', payment_id: 'pay-test', product_cart: [{ product_id: 'dlock-test' }] } };
  assert.deepEqual(store.recordPayment(event, 'evt-1', 'business-test', 'dlock-test'), { duplicate: false });
  assert.deepEqual(store.recordPayment(event, 'evt-1', 'business-test', 'dlock-test'), { duplicate: true });
  store.recordPayment(event, 'evt-2', 'business-test', 'dlock-test');
  assert.equal(store.db.prepare('SELECT COUNT(*) AS count FROM payments').get().count, 1);
  assert.throws(() => store.recordPayment({ ...event, business_id: 'other' }, 'evt-3', 'business-test', 'dlock-test'), { status: 403 });
  assert.throws(() => store.recordPayment({ ...event, data: { ...event.data, product_cart: [{ product_id: 'other' }] } }, 'evt-4', 'business-test', 'dlock-test'), { status: 400 });
});
