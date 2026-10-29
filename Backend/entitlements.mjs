import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, sign } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync, chmodSync } from 'node:fs';

export const dailyInterval = 24 * 60 * 60;
export const offlineInterval = 30 * dailyInterval;

export function createEntitlementSigner(privateKey = generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).privateKey) {
  const publicKey = createPublicKey(privateKey);
  const jwk = publicKey.export({ format: 'jwk' });
  const raw = Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, 'base64url'), Buffer.from(jwk.y, 'base64url')]);
  return {
    publicKey: raw.toString('base64'),
    issue({ environment, installation, activation, key, nonce }, now = Math.floor(Date.now() / 1000)) {
      if (typeof nonce !== 'string' || !/^[a-zA-Z0-9-]{16,80}$/.test(nonce)) throw new Error('A fresh request nonce is required.');
      const payload = Buffer.from(JSON.stringify({
        version: 1, app: 'com.dlock.app', environment, installation_id: installation,
        activation_id: activation, license_hash: createHash('sha256').update(key).digest('hex'),
        nonce, issued_at: now, recheck_after: now + dailyInterval, offline_until: now + offlineInterval
      }));
      return { key_id: 'test-v1', payload: payload.toString('base64'),
        signature: sign('sha256', payload, { key: privateKey, dsaEncoding: 'ieee-p1363' }).toString('base64') };
    }
  };
}

export function loadTestSigner(path) {
  if (!existsSync(path)) {
    const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    writeFileSync(path, privateKey.export({ type: 'pkcs8', format: 'pem' }), { flag: 'wx', mode: 0o600 });
  }
  chmodSync(path, 0o600);
  return createEntitlementSigner(createPrivateKey(readFileSync(path)));
}
