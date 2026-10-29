import { createEntitlementSigner } from '../Backend/entitlements.mjs';
import { LicenseStore, LicensingService } from '../Backend/licensing.mjs';

const signer = createEntitlementSigner();
const store = new LicenseStore();
try {
  const key = 'DLOCK-INTEROP-FIXTURE';
  const installation = 'interop-installation-000001';
  const nonce = 'interop-request-000001';
  store.issueTestKey(key);
  const response = await new LicensingService({ store, signer }).run('activate', {
    license_key: key, installation_id: installation, nonce
  });
  const claims = JSON.parse(Buffer.from(response.entitlement.payload, 'base64'));
  console.log(JSON.stringify({ publicKey: signer.publicKey, entitlement: response.entitlement,
    nonce, issuedAt: claims.issued_at,
    credential: { installationID: installation, key, activationID: response.activation_id } }));
} finally { store.close(); }
