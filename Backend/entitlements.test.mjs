import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, createPublicKey, verify } from 'node:crypto';
import { mkdtempSync, statSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createEntitlementSigner, loadTestSigner, dailyInterval, offlineInterval } from './entitlements.mjs';
import { LicenseStore, LicensingService } from './licensing.mjs';

function publicKey(signer) {
  const raw = Buffer.from(signer.publicKey, 'base64');
  return createPublicKey({ key: { kty: 'EC', crv: 'P-256',
    x: raw.subarray(1, 33).toString('base64url'), y: raw.subarray(33).toString('base64url') }, format: 'jwk' });
}

test('entitlements use verifiable P256 signatures, daily checks and a fixed 30-day window', () => {
  const signer = createEntitlementSigner();
  const input = { environment: 'mock', installation: 'installation-000001', activation: 'activation-1',
    key: 'DLOCK-FIXTURE-KEY', nonce: 'fresh-request-000001' };
  const signed = signer.issue(input, 1800000000);
  const bytes = Buffer.from(signed.payload, 'base64');
  const signature = Buffer.from(signed.signature, 'base64');
  assert.equal(signature.length, 64);
  assert.equal(verify('sha256', bytes, { key: publicKey(signer), dsaEncoding: 'ieee-p1363' }, signature), true);
  assert.equal(verify('sha256', Buffer.concat([bytes, Buffer.from(' ')]), { key: publicKey(signer), dsaEncoding: 'ieee-p1363' }, signature), false);
  const claims = JSON.parse(bytes);
  assert.equal(claims.recheck_after - claims.issued_at, dailyInterval);
  assert.equal(claims.offline_until - claims.issued_at, offlineInterval);
  assert.equal(claims.installation_id, input.installation);
  assert.equal(claims.nonce, input.nonce);
  assert.equal(claims.license_hash, createHash('sha256').update(input.key).digest('hex'));
  assert.equal(bytes.includes(input.key), false);
  assert.throws(() => signer.issue({ ...input, nonce: '' }));
});

test('test signing key survives restarts and is owner-only', () => {
  const directory = mkdtempSync(join(tmpdir(), 'dlock-signing-'));
  try {
    const path = join(directory, 'private.pem');
    const original = loadTestSigner(path);
    assert.equal(loadTestSigner(path).publicKey, original.publicKey);
    assert.equal(statSync(path).mode & 0o777, 0o600);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test('service signs only verified activations and rejects missing nonces', async () => {
  const store = new LicenseStore();
  try {
    const signer = createEntitlementSigner();
    const service = new LicensingService({ store, signer });
    const body = { license_key: 'DLOCK-FIXTURE-KEY', installation_id: 'installation-000001', nonce: 'fresh-request-000001' };
    store.issueTestKey(body.license_key);
    await assert.rejects(service.run('activate', { ...body, nonce: undefined }), { status: 400 });
    const response = await service.run('activate', body);
    const claims = JSON.parse(Buffer.from(response.entitlement.payload, 'base64'));
    assert.equal(claims.activation_id, response.activation_id);
    await service.run('deactivate', { ...body, activation_id: response.activation_id });
    await assert.rejects(service.run('validate', { ...body, activation_id: response.activation_id }), { status: 403 });
  } finally { store.close(); }
});
