# PQ Account Recovery with a Passkey (WebAuthn PRF)

**Status:** proposed. Opt-in. Client-only: no server change.

**Code:** every path below is in the frontend repository, `Buckitup-chat/chat-frontend`.

**Builds on:**
- [pq_user_storage.done.md](pq_user_storage.done.md) for the row the envelope lives in;
- [pq_recovery_shares.proposed.md](pq_recovery_shares.proposed.md), community backup, whose vault envelope it reuses;
- [pq_access_gating.done.md](pq_access_gating.done.md) for read gating in `trust` mode.

**Depends on:** the frontend's vault moving to WebAuthn PRF. In that plan:
- the vault's keys are locked under a key derived from the passkey's PRF output (`src/lib/pq/vaultLock.ts`, HKDF domain `buckitup/vault-lock/v1`);
- `@lo-fi/local-vault` and `@lo-fi/local-data-lock` are removed;
- its first step is the probe page `sandbox/prf-probe` (branch `feat/prf-probe`), which records PRF support per device.

## 1. Why

**Today** an account's secret keys exist only in the browser's storage for the app. When the browser clears it, or the device is lost, the passkey can no longer sign the person in. The passkey survives, because it lives in the operating system, iCloud Keychain or Google Password Manager. What it unlocked is gone.

**With this feature** the account's keys are kept on the server in an envelope that only that passkey opens.

| Case | Covered | Condition |
|---|---|---|
| Browser data cleared, same device | Yes | Any passkey: it is not part of the browser's storage |
| New device | Yes | A synced passkey only. A hardware key or a device-bound passkey does not move to a new device |

No backup file and no guardians are needed.

## 2. What it changes in the threat model

| | Today | With the envelope |
|---|---|---|
| What taking over the account needs | The passkey **and** the storage of one particular device | The passkey alone |
| Who can do it | Someone holding the unlocked device | Also whoever controls the person's Apple or Google account and can pass user verification on a device the passkeys sync to |

Hence two rules:
- the feature is off by default;
- before it is turned on, the person reads this trade-off in plain words.

## 3. Cryptography

Everything but the PRF call exists already. The envelope is `src/lib/pq/vaultEnvelope.ts`; the user_storage row is `src/lib/recovery/vault.ts`. Community backup uses both.

```
salt_r = SHA-256("buckitup/vault-recovery/v1")          # a constant in the code, 32 bytes
P      = PRF(passkey, salt_r)                            # WebAuthn extensions.prf.eval.first, 32 bytes
R      = HKDF-SHA3-256(P, salt = "buckitup/prf-recovery/v1", info = "wrap", L = 32)   # invariants/09_symmetric_keys.md

locator = deriveVaultLocator(R)      # the user_storage uuid (salt buckitup/vault-locator/v1)
value   = sealVault(json, R)         # version ‖ nonce ‖ AES-256-GCM (salt buckitup/vault-seal/v1)
json    = BackupContents             # what a backup file holds: identity + keys (exportBackup)
```

- **The salt is a constant.**
  - A wiped device keeps nothing it could be stored in, and without it the envelope's address cannot be derived.
  - It needs no secrecy: the secret is the one inside the passkey, which makes P unique per passkey.
  - It is built as the probe builds its salts: SHA-256 of a label.
- **P is never used directly.**
  - R comes from P through HKDF in its own domain. The address and the seal key come from R under the envelope's salts.
  - R cannot meet a community-backup wrap key, which is random.
- **Golden vector.** A fixed P → R → locator is pinned in `tests/pqCheckpoint.test.ts`. Changing any label bumps its `/v1` and re-pins the vector.
- **Key hygiene.** P and R are wiped (`fill(0)`) as soon as they are used, as the wrap key is in `recoveryRestore.store.js`.

## 4. Flows

### 4.1 Turning it on (on a device where the account is open)

1. A "Recovery with passkey" card in Backup Center shows whether recovery is on and explains § 2. The person confirms.
2. The client runs an assertion with the passkey:
   - `allowCredentials` = the credential that locks the vault;
   - `userVerification: 'required'`;
   - `extensions.prf.eval.first = salt_r`.

   If no PRF result comes back, it says so plainly and stops.
3. The client reads the `authenticatorData` flags BE and BS (backup eligible, backup state) to tell whether the passkey syncs. With BE = 0 it warns: "This passkey does not sync. Recovery will work after this browser's data is cleared, but not on a new device."
4. It computes R and calls `publishVault({ userHash, signSkey, wrapKey: R, json: exportBackup() })`, then waits for the server to accept the write.
5. It records the envelope in the account's `recovery-passkeys` slot (`patchSlotJson` with `$keyed`):
   - key: a hash of the credential id;
   - value: `{ label, locator, synced: BS, created_at }`.

   The slot exists to list and retire envelopes; neither P nor R is written to it.

Once the vault is on PRF, the ordinary login already runs an assertion for the vault's lock key. Turning recovery on can share that assertion, with the lock salt as `first` and the recovery salt as `second`, so the passkey is not asked twice.

### 4.2 Recovering (wiped or new device)

1. The login screen offers "Restore with passkey", including when the device has no local account.
2. The client runs a discoverable assertion:
   - no `allowCredentials`;
   - `userVerification: 'required'`;
   - `extensions.prf.eval.first = salt_r`.

   The browser offers this site's passkeys.
3. It computes R and calls `fetchVault(R)`, which reads `getPublicStorageRowsByUuid(locator)` and opens the envelope.
4. Outcomes:

| Result | What the person sees |
|---|---|
| `absent` | Recovery with this passkey is not set up on this server |
| `foreign` | The same: rows exist at the address, none opens under this key |
| Network failure | The server did not answer, try again. Never "no backup" |
| No PRF result | This passkey or browser does not support recovery |

5. The `BackupContents` go to `importBackup`, as from a backup file. The new local vault is locked with the **same** passkey through PRF; no new passkey is created.
6. Check that `identity.user_hash` equals the hash of the public key derived from the envelope's `sign_skey`. `importBackup` has no explicit check of this today. Add it there, for every restore path: file, guardians, device link, passkey.

### 4.3 Retiring

- The client writes a new version of the row at `locator` with `deleted_flag: true` and an empty value, then removes the entry from `recovery-passkeys`.
- **Limit:** the previous version stays in `user_storage_versions`, which is publicly readable. Retiring means "the app no longer uses it", not "the ciphertext is gone": the passkey still opens the old version.
- If the passkey is compromised, the answer is a retraction of the identity (new keys), not retiring the envelope. The client says so.

### 4.4 Several passkeys, and changing the passkey

- **One envelope per passkey.** PRF results differ between passkeys. All envelopes are listed in `recovery-passkeys`.
- **Changing the passkey.** When the vault is re-locked to a new passkey, the client offers to turn recovery on for the new one and to retire the old one's envelope.

## 5. What the server sees

- **Turning it on:** the account wrote one more opaque user_storage row at a random-looking uuid, indistinguishable from a settings slot.
- **Recovering:**
  - an anonymous read of the rows at a uuid, from some IP address;
  - the server can tie that address to the account at that moment;
  - community backup has the same property.
- **What it never sees:** P, R, or the passkey's secret. R cannot be brute-forced: it comes from 32 bytes of HMAC computed inside the authenticator.

## 6. Limits

- **PRF support.** The probe's table decides where the feature is offered; without PRF the card does not appear.
- **The passkey is bound to its domain (RP ID).** An envelope made on `buckitup.xyz` opens only there. The row syncs to other servers, but a passkey of another origin cannot open it: a Raspberry Pi on its own origin, for example.
- **`trust` mode.** Reading `user_storage` needs a read session there ([pq_access_gating.done.md](pq_access_gating.done.md#read-gating-read-sessions)). An anonymous client holding no keys cannot open one, so recovery fails on such a server. Community backup has the same limit (open question 2).
- **The envelope holds the keys as they were when it was written.**
  - Account keys do not change, so no rewrite is needed.
  - If `exportBackup` gains or changes fields (`meta_seed` and the like), the envelope is resealed at the next login.

## 7. Code

New:
- `src/lib/recovery/passkeyRecovery.ts`:
  - `RECOVERY_PRF_LABEL`, `recoverySalt()`, `recoveryWrapKey(P)`;
  - `enable()`, `recover()` and `retire()`, built on `publishVault` and `fetchVault` (`src/lib/recovery/vault.ts`).

Changed:
- **WebAuthn calls** live in `vaultLock.ts` from the PRF plan. It needs a second salt and access to the BE/BS flags.
- **The `recovery-passkeys` slot** sits next to the other recovery slots.
- **UI:**
  - the Backup Center card;
  - the login-screen button;
  - an entry in the storage-persistence reminders: data may be cleared and there is no backup → offer passkey recovery when the passkey syncs.

Tests:
- The golden vector P → R → locator.
- A fake PRF (a deterministic HMAC) in unit tests:
  - turning on → clearing local data → recovering gives the same `user_hash`;
  - a foreign row at the same address is skipped;
  - retiring writes a tombstone;
  - a network failure is never reported as `absent`.
- E2E on Chrome's virtual authenticator with `hasPrf`: turn on, clear storage, recover.

## 8. Open questions

1. With a synced passkey (BS = 1), offer it right after the account is created, or only from Backup Center and the reminders?
2. `trust` mode: should reading envelope rows (by uuid, without `user_hash`) be exempt from read gating? One decision covers this envelope and community backup alike. It is a server-side decision.
