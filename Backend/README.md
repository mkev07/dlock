# Dlock licensing test service

This is a local development service, not a production payment system. It cannot
accept live payments. Dock features start disabled until a test license is
activated or a saved activation is verified online. There is no trial and no
usage analytics are sent. This local test gate is not production DRM.

## Local simulator

Requires Node 22.13 or newer (Node's SQLite module is currently experimental).

```sh
cd Backend
npm ci
npm test
npm start
```

The service binds only to `127.0.0.1:8787`. In Dlock, open Settings → License.
Enter **DLOCK-LOCAL-TEST-ONLY**, a public simulator fixture, not a paid license.
Activate, check validity, and deactivate. Deactivation releases the one active
installation slot. Failed validation/deactivation retains credentials so retry
and transfer remain possible. Reopening the app requires a new validity check
before enabling features unless a valid signed entitlement is cached. Cached
access works across app restarts for at most 30 days from the last successful
verification. The app checks daily while running, on activation, and after wake;
failed automatic attempts retry no more often than every 15 minutes. Manual
Check Validity can retry immediately. An outage never extends the signed window.
Without a valid cache, features stay off and credentials are retained. An
authoritative invalid-license response or confirmed deactivation disables Dock
protection and paid controls without deleting the remembered display preference.
The License, About, update and Quit actions remain available while locked.

SQLite persists hashed keys and activation IDs under ignored `data/`. Actual
license keys are stored in this Mac's nonsynchronizing Keychain namespace
`com.dlock.licensing.test.v1`, separate from future production credentials.
The installation ID is random, not a hardware fingerprint. One-installation
tests are not proof of tamper-resistant hardware binding.

## Signed offline access (development implementation)

The server signs exact JSON payload bytes with P-256/SHA-256 and a 64-byte
IEEE-P1363 signature. The envelope contains `key_id`, Base64 `payload`, and
Base64 `signature`. Claims bind app, environment, installation ID, activation
ID, SHA-256 license hash and a fresh client nonce. The signed policy is a
24-hour recheck interval and a strict 30-day offline deadline. The lifetime
purchase itself has no expiry; that deadline only requires reconnection.

The app verifies the signature with a pinned public key, exact policy, binding,
time window and (for online responses) nonce/freshness before saving access.
Expired, unsigned or tampered responses cannot unlock the app. An old response
cannot renew the offline window. Confirmed denial or deactivation clears the
cached entitlement; revocation/transfer cannot invalidate an already-issued
offline token remotely until the old Mac checks or its 30-day allowance ends.

`npm start` creates or reuses `Backend/data/test-signing-private.pem` (0600).
This ignored **test-only** key stays on the backend; only its public key is
compiled into Debug. To use a different development machine/key, print its
public key with the command below, update the Debug-only pin in
`LicenseEntitlement.swift`, and rebuild. Existing cached tokens must then be
verified online again. Never use this development key for production.

```sh
cd Backend
node --input-type=module -e 'import {loadTestSigner} from "./entitlements.mjs"; console.log(loadTestSigner("data/test-signing-private.pem").publicKey)'
```

The client checkpoints its highest observed wall-clock time in Keychain and
compares wall time against process uptime. A rollback exceeding five minutes
blocks offline access until a fresh online verification. The cache never gets
an extra 30 days from reopening, retries or local clock corrections. Persisting
the checkpoint is required to grant cached access. A writable local clock and
credential store cannot provide absolute rollback/tamper protection across
reboots; extraction, restoration of old Keychain state or binary modification
is outside this protection. If a denial cannot be saved due to a Keychain
failure, the current session locks but persistence across restart is not
guaranteed until storage recovers. Clock changes on the local test server are
not independent trusted time; production requires a separately hosted server.

Release uses a separate Keychain namespace and has **no test signing key,
loopback transport or enabled licensing configuration**. Production remains
fail-closed until a production HTTPS service and production public-key trust
are deliberately configured. This milestone does not enable selling licenses.

## Dodo sandbox adapter (not exercised against Dodo yet)

Set `DLOCK_LICENSE_MODE=dodo-test`, `DODO_TEST_API_KEY`,
`DODO_TEST_PRODUCT_ID`, `DODO_TEST_BUSINESS_ID`, and
`DODO_TEST_WEBHOOK_SECRET` through a secure local environment. Never commit or
paste provider secrets into source, logs, or the app. Only the fixed
`https://test.dodopayments.com` host is used. There is no live-mode switch.

Create a one-time sandbox product with a license-key entitlement:
one activation, no duration/expiry, and all future versions included. Product
and business IDs are checked on activation. Real Dodo credentials, product
configuration, purchase/key delivery, and sandbox acceptance remain required.

`POST /v1/licenses/activate`, `/validate`, `/deactivate` accept `license_key`,
`installation_id`, a fresh `nonce`, plus `activation_id` for validation/deactivation.
Activations are serialized in this single-process test service; the Dodo
entitlement must independently enforce its activation limit of one.

`POST /v1/webhooks/dodo` verifies raw-body Standard Webhooks signatures and
timestamps using the same verification library as Dodo's official SDK. The
configured business and product are checked for successful payments. Event IDs
and payment IDs are deduplicated transactionally. This is a minimal test payment
ledger, not checkout inventory, financial reporting, or license issuance. Dodo
remains the source of license validity. Refund/revocation workflows still need
real-provider tests. Never derive entitlement from a checkout redirect.

The loopback server deliberately rejects browser-origin requests and unexpected
Host headers. It has no public webhook deployment or exposed admin endpoints.
Do not point a public tunnel at it as a production deployment. There is no
checkout URL, buyer-count display, or payment-collection action in the app yet.

## Confirmed commercial rules

- One payment, one active Mac; deactivate to transfer. All future updates and
  major versions included, without license expiry.
- Buyers 1–50: USD 2.99; 51–100: USD 4.99; 101–150: USD 7.99;
  buyer 151 onward: USD 9.99. The overlapping "150+" boundary is normalized
  to 151. This schedule is unit-tested but NOT enforced by a live checkout.
- No trial and no unconditional satisfaction-refund offer. Proposed terms must
  describe failure-to-deliver remedies and preserve mandatory consumer rights;
  do not publish an absolute "no refunds" clause without legal review.
- macOS 13.0 is the deployment minimum, NOT evidence of compatibility across
  all later macOS versions or display arrangements. Publish only a tested
  compatibility matrix and verified architecture support before selling.

## Production gates

Still required: provider sandbox acceptance, approved merchant/payout setup,
deployed HTTPS backend, durable backup/reconciliation, authenticated recovery
for a lost Mac, production signing-key custody/rotation, production HTTPS and
public-key configuration, real-provider validation of the offline policy,
atomic checkout pricing/reservations, purchase/key-delivery testing, verified
revocation/refund handling, terms/privacy pages, notarized distribution, and
external device acceptance. Lifetime updates do not imply indefinite offline
validity after a transfer or revocation. No production licensing claim is made.

References: https://docs.dodopayments.com/features/license-keys and the official
TypeScript SDK's `src/resources/licenses.ts` and webhook verifier.
