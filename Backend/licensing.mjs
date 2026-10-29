import { createHash, randomUUID } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { Webhook } from 'standardwebhooks';
import { createEntitlementSigner } from './entitlements.mjs';

export class LicenseError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

export function priceForBuyer(number) {
  if (!Number.isSafeInteger(number) || number < 1) throw new Error('Invalid buyer number');
  return number <= 50 ? 299 : number <= 100 ? 499 : number <= 150 ? 799 : 999;
}

export const hashKey = key => createHash('sha256').update(key).digest('hex');

export class LicenseStore {
  constructor(path = ':memory:') {
    this.db = new DatabaseSync(path);
    this.db.exec(`
      PRAGMA journal_mode=WAL;
      CREATE TABLE IF NOT EXISTS licenses (key_hash TEXT PRIMARY KEY, revoked INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS activations (key_hash TEXT PRIMARY KEY, installation TEXT NOT NULL, activation TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY);
      CREATE TABLE IF NOT EXISTS payments (id TEXT PRIMARY KEY);
    `);
  }
  issueTestKey(key) {
    this.db.prepare('INSERT OR IGNORE INTO licenses (key_hash) VALUES (?)').run(hashKey(key));
  }
  getActivation(key) {
    return this.db.prepare('SELECT * FROM activations WHERE key_hash = ?').get(hashKey(key));
  }
  saveActivation(key, installation, activation) {
    this.db.prepare('INSERT INTO activations VALUES (?, ?, ?)').run(hashKey(key), installation, activation);
  }
  removeActivation(key) {
    this.db.prepare('DELETE FROM activations WHERE key_hash = ?').run(hashKey(key));
  }
  checkTestKey(key) {
    const license = this.db.prepare('SELECT revoked FROM licenses WHERE key_hash = ?').get(hashKey(key));
    if (!license || license.revoked) throw new LicenseError(403, 'License is invalid or revoked.');
  }
  recordPayment(event, eventID, businessID, productID) {
    if (event.business_id !== businessID) throw new LicenseError(403, 'Unexpected webhook business.');
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const inserted = this.db.prepare('INSERT OR IGNORE INTO events VALUES (?)').run(eventID).changes;
      if (inserted && event.type === 'payment.succeeded') {
        const payment = event.data;
        if (payment?.business_id !== businessID || !Array.isArray(payment.product_cart) ||
            !payment.product_cart.some(item => item.product_id === productID) ||
            typeof payment.payment_id !== 'string' || !payment.payment_id) {
          throw new LicenseError(400, 'Unexpected payment payload.');
        }
        this.db.prepare('INSERT OR IGNORE INTO payments VALUES (?)').run(payment.payment_id);
      }
      this.db.exec('COMMIT');
      return { duplicate: !inserted };
    } catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
  close() { this.db.close(); }
}

export function verifyWebhook(body, headers, secret) {
  if (!secret) throw new LicenseError(503, 'Webhooks are not configured.');
  try { return new Webhook(secret).verify(body, headers); }
  catch { throw new LicenseError(401, 'Invalid webhook signature or timestamp.'); }
}

export class LicensingService {
  constructor({ store, mode = 'mock', apiKey, productID, businessID, transport = fetch, signer = createEntitlementSigner() }) {
    if (!['mock', 'dodo-test'].includes(mode)) throw new Error('Only mock or dodo-test mode is allowed.');
    if (mode === 'dodo-test' && (!apiKey || !productID || !businessID)) throw new Error('Dodo test credentials and IDs are required.');
    Object.assign(this, { store, mode, apiKey, productID, businessID, transport, signer });
    this.pending = Promise.resolve();
  }
  run(action, body) {
    const operation = this.pending.then(() => this.perform(action, body));
    this.pending = operation.catch(() => {});
    return operation;
  }
  async provider(action, body) {
    const response = await this.transport(`https://test.dodopayments.com/licenses/${action}`, {
      method: 'POST', signal: AbortSignal.timeout(15000),
      headers: { Authorization: `Bearer ${this.apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
    if (!response.ok) {
      if ([400, 401, 403, 404, 409, 422].includes(response.status)) {
        throw new LicenseError(403, 'Dodo test activation was rejected. Check the key and activation limit.');
      }
      throw new LicenseError(503, 'Dodo test service is unavailable. Your saved activation has been retained.');
    }
    return response.status === 204 || action === 'deactivate' ? null : response.json();
  }
  async perform(action, body) {
    if (!['activate', 'validate', 'deactivate'].includes(action)) throw new LicenseError(404, 'Unknown action.');
    const { license_key: key, installation_id: installation, activation_id: activationID } = body ?? {};
    if (typeof key !== 'string' || key.length < 8 || key.length > 512 || key !== key.trim() ||
        typeof installation !== 'string' || !/^[a-zA-Z0-9-]{16,80}$/.test(installation)) {
      throw new LicenseError(400, 'A license key and installation ID are required.');
    }
    if (typeof body.nonce !== 'string' || !/^[a-zA-Z0-9-]{16,80}$/.test(body.nonce)) {
      throw new LicenseError(400, 'A fresh request nonce is required.');
    }
    if (this.mode === 'mock') this.store.checkTestKey(key);
    let active = this.store.getActivation(key);
    if (active && active.installation !== installation) throw new LicenseError(409, 'This license is active on another Mac. Deactivate it there first.');
    if (action === 'activate') {
      if (!active) {
        let activation = randomUUID();
        if (this.mode === 'dodo-test') {
          const result = await this.provider('activate', { license_key: key, name: `Dlock ${installation}` });
          if (result?.product?.product_id !== this.productID || result.business_id !== this.businessID || typeof result.id !== 'string') {
            if (typeof result?.id === 'string') await this.provider('deactivate', { license_key: key, license_key_instance_id: result.id });
            throw new LicenseError(403, 'This is not a Dlock test license.');
          }
          activation = result.id;
        }
        this.store.saveActivation(key, installation, activation);
        active = this.store.getActivation(key);
      }
    } else if (!active || activationID !== active.activation) {
      throw new LicenseError(403, 'Activation could not be verified on this Mac.');
    }
    if (action === 'deactivate') {
      if (this.mode === 'dodo-test') await this.provider('deactivate', { license_key: key, license_key_instance_id: active.activation });
      this.store.removeActivation(key);
      return { status: 'deactivated', environment: this.mode, all_future_updates: true, max_macs: 1 };
    }
    if (this.mode === 'dodo-test') {
      const result = await this.provider('validate', { license_key: key, license_key_instance_id: active.activation });
      if (result?.valid !== true) throw new LicenseError(403, 'Dodo test license is no longer valid.');
    }
    return { status: 'active', environment: this.mode, activation_id: active.activation,
      all_future_updates: true, max_macs: 1, expires_at: null,
      entitlement: this.signer.issue({ environment: this.mode, installation,
        activation: active.activation, key, nonce: body.nonce }) };
  }
}
