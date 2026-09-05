# Trust Metric Discovery

## Problem

The Vouchsafe ZI-CG model (and any vouch/attestation-based trust system) requires both sides to agree on what claims mean. Attestation tokens are only useful when verifier and attester share a vocabulary. That vocabulary naturally forms a hierarchy — broad capability groups narrowing into specific claims — which is effectively an ontology problem.

Without a discovery mechanism, each deployment invents its own claim dictionary, making cross-device and cross-deployment trust evaluation opaque. The system claims "zero infrastructure" but quietly pushes the infrastructure cost into **agreeing on what words mean**.

A second tension: the Vouchsafe evaluation algorithm requires a **trusted root** — path discovery confirms a chain originates from "a trusted principal with bounded scope." The paper frames this as "no central authority," but in practice it is **bring-your-own authority** — each verifier decides its own root set locally. This eliminates infrastructure (no server to query) but does not eliminate the trust bootstrapping problem: either a group converges on shared roots (a de facto authority) or different verifiers accept different tokens (harder coordination). For BuckitUp, the root is the device owner/admin who set up the cluster — an explicit, physical trust anchor — which fits the model well but should be acknowledged as a design choice, not an absence of authority.

## Scope

Define how BuckitUp devices discover, negotiate, and converge on a shared trust metric vocabulary — the set of attestation kinds, vouch scopes, and their hierarchical relationships.

## Requirements

### 1. Claim Vocabulary Structure

A claim vocabulary is a tree of scopes:

```
device-management
├── firmware
│   ├── firmware-version
│   └── firmware-signature-valid
├── hardware-status
│   ├── sensor-calibrated
│   └── storage-healthy
└── network
    └── connectivity-verified

user-trust
├── identity-verified
│   ├── optical-handshake
│   └── manual-approval
├── vouched
│   ├── direct-vouch
│   └── transitive-vouch
└── behavioral
    ├── tenure
    └── interaction-consistency
```

Scope attenuation (intersecting scopes along a vouch chain) requires scopes to be **comparable** — a child is always a subset of its parent.

### 2. Built-in vs Discovered Vocabulary

| Layer | Source | Mutable? |
|-------|--------|----------|
| **Core** | Compiled into firmware/app. Covers identity, vouching, revocation — the minimum for the gate to function. | No |
| **Device-local** | Owner defines additional scopes via admin UI (e.g., domain-specific sensor claims). | Yes, owner only |
| **Discovered** | Learned from peer devices during sync. A device encountering unknown scopes in received tokens can store them as opaque but preserve the hierarchy for attenuation. | Yes, append-only |

### 3. Discovery Protocol

When two BuckitUp devices sync (via Electric replication or direct peer connection):

1. **Vocabulary advertisement** — each device includes its claim vocabulary (as a signed attestation itself) in the sync payload.
2. **Merge** — the receiver unions the two vocabularies. Conflicts (same scope name, different position in hierarchy) are flagged for owner resolution.
3. **Opaque passthrough** — tokens referencing unknown scopes are stored and forwarded but cannot be evaluated locally until the vocabulary is merged. The gate treats unknown scopes as **deny** (closed-world assumption).

### 4. Attestation as Self-Describing Token

Each attestation token should carry enough metadata to be partially interpretable without prior vocabulary agreement:

| Field | Purpose |
|-------|---------|
| `kind` | Hierarchical scope path, e.g. `device-management/firmware/firmware-version` |
| `schema_version` | Integer version of the claim's payload schema |
| `value` | The actual claim payload (type depends on `kind`) |
| `human_label` | Optional display string for UI rendering of unknown claims |

This makes tokens **self-describing** — a verifier without the full vocabulary can at least display and store the claim, even if it can't evaluate scope attenuation.

### 5. Trust Root Bootstrapping

The Vouchsafe evaluation algorithm walks vouch chains backward to a **trusted root**. "Zero infrastructure" means no root *server* — not no root *identity*. Each verifier maintains its own root set.

Crucially, the trust root is **scope-dependent** — there is no single universal root. Different capability domains have different natural authorities:

| Scope domain | Natural root | Authority over |
|---|---|---|
| **Device** | Admin | Firmware, hardware config, network, sensor calibration |
| **Identity / origin** | Owner (identity creator) | Who this identity is, what keys represent it |
| **Room** | Room creator | Membership, message permissions, moderation |
| **Content** | Author | Authenticity and integrity of authored messages |
| **Peer trust** | Each user individually | Personal vouch graph, who they choose to trust |

A single vouch chain evaluation is always scoped — "does this chain lead to a root that has authority *in this domain*?" A device admin root carries no weight for room membership; a room creator root carries no weight for firmware claims. Scope attenuation and root authority work together: the root must match the scope being evaluated.

In BuckitUp's model:

- **First-contact key exchange** (optical handshake, manual approval) establishes trust anchors per domain. This is an out-of-band ceremony, not infrastructure.
- **Transitive trust** flows from domain-appropriate roots via vouch chains with attenuating scope.
- **Cross-domain authority does not exist.** An admin vouch for device management never implies room access. Authority stays in its lane.

This means BuckitUp does not need a global PKI or certificate authority, but it does require that every capability evaluation traces back to a root whose authority covers the scope in question.

### 6. Vocabulary Governance — No Central Authority

There is no vocabulary root. Scopes gain meaning through **usage across the trust graph**, not through decree:

- Any identity can define and use any scope path in its attestations and vouches.
- A scope becomes **locally meaningful** to a verifier when multiple identities the verifier trusts use it consistently (same `kind` path, compatible `schema_version`, compatible payload shapes).
- **Convergence is emergent.** If Alice and Bob both issue attestations with `kind: device-management/firmware/firmware-version` and they trust each other, the term is de facto shared. No registration step.
- **Divergence is tolerated.** If two unconnected clusters use the same scope path with incompatible semantics, that's fine — they don't trust each other, so the conflict never materializes in a single evaluation.
- **Scope reputation.** A verifier can weight a scope's reliability by how many of its trusted peers use it — analogous to how EigenTrust weights vouch quality by the voucher's own trust score. A scope used only by one low-trust identity carries little semantic weight.
- The compiled **core vocabulary** (§2) is a bootstrap convenience, not an authority. Devices ship with a common starting set so they can interoperate on day one, but nothing prevents the trust graph from evolving past it.

## Relationship to Access Gating

This req extends the `trust` mode defined in [pq_access_gating](pq_access_gating.proposed.md). Specifically:

- The **trust score components** (verification_level, vouches, chain_distance, etc.) become attestation `kind` values in the core vocabulary.
- **Vouch scopes** in the gating req become entries in the claim hierarchy.
- **Open Question §8** (offline trust evaluation with self-contained tokens) depends on tokens being self-describing per §4 above.

## Open Questions

1. **How deep should the core vocabulary go?** A minimal core (identity + vouch + revoke) maximizes flexibility but forces every deployment to reinvent common claims. A richer core (including device-management, firmware, user-trust) reduces duplication but may not fit all use cases.

2. **Should vocabulary changes propagate retroactively?** If the owner adds a new scope, do existing tokens referencing a parent scope implicitly cover the new child? (Vouchsafe says no — scopes attenuate, never expand.)

3. **Version migration.** When `schema_version` increments for a `kind`, how are old tokens handled? Options: ignore (old tokens stop matching), translate (migration function per kind), or dual-evaluate (accept both versions until a cutoff).

4. **Vocabulary size limits.** A malicious or careless peer could advertise an enormous vocabulary to waste storage. Should there be a cap on discovered vocabulary size per peer?

5. **Multi-root divergence.** When a device trusts multiple roots that disagree (different vouch chains yield different authorization for the same token), what wins? Options: any-path-admits (permissive), all-paths-must-admit (restrictive), or weighted by root trust level.

## Status

Proposed.

## References

- [Vouchsafe ZI-CG](https://arxiv.org/abs/2601.02254) — scope attenuation requires comparable scopes, implying a shared vocabulary
- [pq_access_gating](pq_access_gating.proposed.md) — trust mode and vouch mechanics this req extends
