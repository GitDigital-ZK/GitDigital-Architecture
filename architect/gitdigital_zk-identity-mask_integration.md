GitDigital zk‑Identity‑Masks Integration

The privacy layer — bridges the Identity Registry, KYC Engine, and AML Engine to the zk‑Identity‑Masks system, enabling selective disclosure, private authentication, and anonymous credentialing without revealing raw personal data.

This module enables a user to generate a zero‑knowledge proof (a “mask”) attesting to specific attributes — e.g., “KYC Tier ≥ 2 AND AML score < 70 AND Jurisdiction = CH” — and present it to any verifier, all without exposing the underlying identity, tier, score, or jurisdiction. The mask leverages the underlying compliance attestations but reveals only what the user chooses.

---

1. High‑Level Architecture

```
  ┌───────────────────────────────┐
  │         Identity Registry     │
  │         (DID + Attributes)    │
  └───────────┬───────────────────┘
              │   signed attestations
              ▼
  ┌───────────────────────────────┐
  │         KYC Engine            │
  │         (Tier, Expiry,        │
  │          Jurisdiction)        │
  └───────────┬───────────────────┘
              │
              ▼
  ┌───────────────────────────────┐
  │         AML Engine            │
  │         (Risk Score, Flags)   │
  └───────────┬───────────────────┘
              │
              ▼
┌──────────────────────────────────────────────────────────────────┐
│                   zk‑Identity‑Masks Bridge                        │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐ │
│  │ Mask Circuit     │  │ On‑chain Verifier│  │ Mask Registry  │ │
│  │ (Circom)         │  │ Program (Anchor) │  │ PDA            │ │
│  └───────┬──────────┘  └───────┬──────────┘  └────────┬───────┘ │
│          │                     │                       │         │
│          └─────────────────────┴───────────────────────┘         │
│                         │                                        │
│                         ▼                                        │
│         ┌──────────────────────────────┐                         │
│         │  Mask SDK / API Gateway      │                         │
│         │  (generate, prove, verify)   │                         │
│         └──────────────────────────────┘                         │
└──────────────────────────────────────────────────────────────────┘
              │
              ▼
    Verifier / Relying Party
```

---

2. Subsystem Breakdown

Subsystem Responsibility
Mask Circuit (Circom) A generic circuit that takes as private inputs the user’s identity attributes (DID, KYC tier, jurisdiction, AML score, issuer signatures) and as public inputs a disclosure policy (what to prove) and a nullifier. The circuit verifies the issuer signatures and enforces the requested predicate, then outputs a Groth16 proof.
On‑chain Verifier Program Anchor program that verifies a mask proof, checks nullifier uniqueness, policy compliance, and optionally anchors a proof receipt.
Mask Registry PDA On‑chain record of issued masks (nullifier, policy hash, expiry) for revocation and double‑use prevention.
Mask SDK / API Gateway Client library (TypeScript / WASM) that: fetches the user’s signed attestations from the engines; composes a disclosure policy; generates the ZK mask proof; and submits it to the verifier.
Selective Disclosure Policy A structured object specifying which attributes must be proven and which constraints (e.g., { kyc_tier: { gte: 2 }, aml_score: { lt: 70 } }). The policy is hashed and becomes a public input.
Credential Bridge Off‑chain service that retrieves the user’s attestations from the Identity Registry, KYC, and AML engines and formats them as witness inputs for the mask circuit.

---

3. Solana Program Design

```rust
// programs/zk_identity_masks/src/lib.rs

declare_id!("ZkMask111111111111111111111111111111111111");

#[program]
pub mod zk_identity_masks {
    use super::*;

    /// Verifies a mask proof and records it if valid.
    pub fn verify_mask(
        ctx: Context<VerifyMask>,
        proof: Vec<u8>,
        public_inputs: Vec<[u8; 32]>,
    ) -> Result<()>;

    /// Admin: set the verifying key and supported disclosure policies.
    pub fn initialize_config(
        ctx: Context<InitConfig>,
        verifying_key: Vec<u8>,
        authority: Pubkey,
    ) -> Result<()>;

    pub fn update_config(
        ctx: Context<UpdateConfig>,
        verifying_key: Option<Vec<u8>>,
    ) -> Result<()>;

    /// Optional: revoke a mask by nullifier (issuer authority).
    pub fn revoke_mask(
        ctx: Context<RevokeMask>,
        nullifier: [u8; 32],
    ) -> Result<()>;
}
```

---

4. PDA Map

```
Seed Pattern → Account Type → Description
──────────────────────────────────────────────────────────────────────
["mask_config"]
  → MaskConfig
  → Verifying key, authority

["mask_receipt", nullifier]
  → MaskReceipt
  → Record of a verified mask: nullifier, policy_hash, expiry

["mask_revocation", nullifier]
  → MaskRevocation
  → Flags a mask as revoked
```

---

5. API Schema

REST Endpoints

```
── Mask Generation ──────────────────────────────────────────────────
POST   /v1/mask/generate              → { proof, public_inputs }
  Body: {
    subject: string;
    disclosure_policy: DisclosurePolicy;
    expiry?: number;
  }

── On‑chain Verification ────────────────────────────────────────────
POST   /v1/mask/verify                → { tx_sig, receipt_pda, valid }
  Body: { proof, public_inputs }

GET    /v1/mask/status/{nullifier}     → { valid, revoked, expiry }

── Admin ────────────────────────────────────────────────────────────
POST   /v1/mask/revoke                → { tx_sig }
  Body: { nullifier, reason }
```

Core Request Types

```typescript
interface DisclosurePolicy {
  requirements: {
    kyc_tier?: { gte: number };           // 1,2,3
    aml_score?: { lt: number };           // 0‑100
    jurisdiction?: { in: string[] };      // ISO codes
    identity_type?: { eq: string };       // "individual","business"
  };
}

interface GenerateMaskRequest {
  subject: string;
  disclosure_policy: DisclosurePolicy;
  expiry?: number;                        // unix timestamp
}

interface MaskProofResult {
  proof: Uint8Array;
  public_inputs: Uint8Array[];            // [ policy_hash, nullifier, expiry_timestamp ]
}
```

---

6. Data Models

On‑chain (Rust)

```rust
#[account]
pub struct MaskConfig {
    pub authority: Pubkey,
    pub verifying_key: Vec<u8>,
    pub bump: u8,
}

#[account]
pub struct MaskReceipt {
    pub nullifier:      [u8; 32],
    pub policy_hash:    [u8; 32],
    pub expiry:         i64,
    pub verified_at:    i64,
    pub bump:           u8,
}

#[account]
pub struct MaskRevocation {
    pub nullifier:  [u8; 32],
    pub authority:  Pubkey,
    pub reason:     String,
    pub revoked_at: i64,
    pub bump:       u8,
}
```

Off‑chain SQL (Mask Cache)

```sql
CREATE TABLE mask_receipts (
    nullifier     TEXT PRIMARY KEY,
    policy_hash   TEXT NOT NULL,
    expiry        TIMESTAMPTZ,
    verified_at   TIMESTAMPTZ DEFAULT NOW(),
    revoked       BOOLEAN DEFAULT FALSE
);
```

---

7. Client SDK

```typescript
// sdk/src/ZkIdentityMaskSDK.ts
export class ZkIdentityMaskSDK {
  program: Program<ZkIdentityMasks>;

  async generateMask(
    subject: PublicKey,
    disclosurePolicy: DisclosurePolicy,
    expiry?: number
  ): Promise<MaskProofResult> {
    // 1. Fetch attestations from engines (via CPI simulation or off‑chain API)
    const attestations = await this.fetchAttestations(subject);
    // 2. Prepare circuit witnesses
    const witness = {
      did: attestations.did,
      identity_status: attestations.identity_status,
      kyc_tier: attestations.kyc_tier,
      jurisdiction: attestations.jurisdiction,
      aml_score: attestations.aml_composite_score,
      issuer_signatures: attestations.signatures,
      policy: disclosurePolicy,
      nullifier: deriveNullifier(subject, disclosurePolicy),
      expiry: expiry ?? MAX_EXPIRY,
    };
    // 3. Generate proof via snarkjs (WASM)
    const { proof, publicInputs } = await snarkjs.groth16.fullProve(
      witness,
      'mask_circuit.wasm',
      'mask_circuit_final.zkey'
    );
    return { proof, publicInputs };
  }

  async verifyMask(proof: Uint8Array, publicInputs: Uint8Array[]): Promise<string> {
    const [receiptPda] = PublicKey.findProgramAddressSync(
      [Buffer.from('mask_receipt'), publicInputs[1]],
      PROGRAM_ID
    );
    return this.program.methods
      .verifyMask(Array.from(proof), publicInputs.map(i => Array.from(i)))
      .accounts({ maskReceipt: receiptPda, config: configPda })
      .rpc();
  }

  async isMaskValid(nullifier: Uint8Array): Promise<boolean> {
    try {
      const receipt = await this.program.account.maskReceipt.fetch(
        findMaskReceiptPDA(nullifier)[0]
      );
      return !receipt.expired && !receipt.revoked;
    } catch { return false; }
  }
}
```

---

8. Workflows

Selective Disclosure Mask Generation

```
1. User decides they want to prove “KYC tier ≥ 2” and “AML score < 70”.
2. They call the Mask SDK with their subject pubkey and the disclosure policy.
3. SDK fetches the user’s signed attestations from the Identity Registry,
   KYC Engine, and AML Engine (via off‑chain API or CPI simulation).
4. SDK prepares the witness: the actual attribute values plus the issuer
   signatures, and the public inputs (policy hash, nullifier, expiry).
5. Circuit verifies that:
   - The issuer signatures are valid (using embedded issuer public keys).
   - The attributes satisfy the predicate (e.g., kyc_tier >= 2 and aml_score < 70).
   - The policy hash matches the one derived from the supplied policy.
   - The nullifier is correctly derived from the user’s secret.
6. A single Groth16 proof is output with public inputs: policy_hash, nullifier, expiry.
7. The user can now present this proof to any verifier without revealing the actual tier or score.
```

On‑chain Mask Verification

```
1. A dApp or verifier calls mask_program.verify_mask(proof, [policy_hash, nullifier, expiry]).
2. Program verifies the Groth16 proof against the on‑chain verifying key.
3. Checks that the nullifier is unused (MaskReceipt does not exist) and not revoked.
4. Checks that the expiry is in the future.
5. Writes a MaskReceipt with the nullifier, policy hash, expiry, and current timestamp.
6. The verifier can now rely on the proof being valid and timestamped.
```

Policy Enforcement by Verifier

```
- A lending protocol wants users to prove they are from a non‑sanctioned jurisdiction
  with Enhanced KYC. The protocol defines a required DisclosurePolicy:
    { jurisdiction: { in: ["US","CH","DE"] }, kyc_tier: { gte: 2 } }
- The user generates a mask matching that policy, submits the proof.
- The lending protocol verifies the proof and checks that the policy_hash matches
  the known policy hash for “non‑sanctioned Enhanced KYC”. No further data needed.
```

---

9. Security Considerations

Threat Mitigation
Fake attestations Circuit verifies issuer signatures using hardcoded public keys of the Identity/KYC/AML engines.
Replay of mask Each mask is bound to a nullifier derived from the user’s DID; nullifier stored on‑chain and checked for double‑use.
Stale attributes Mask expiry baked into the proof; verifier checks expiry. The mask does not guarantee current status after expiry.
Policy downgrade Policy hash is a public input; verifier compares against an allow list of acceptable policies.
Private key leakage (nullifier) Nullifier derivation uses a deterministic secret; if leaked, the user can be tracked. Mitigated by using a separate purpose‑bound secret.

---

10. Compliance Considerations

Requirement Implementation
Data minimisation Only public inputs are on-chain; no identity, tier, or score revealed.
Right to be forgotten Revocation of nullifier invalidates the mask without touching personal data.
Selective disclosure Users can choose exactly which attributes to reveal; policies can require only necessary minimums.
Audit trail Mask verifications are recorded on-chain, enabling audit without exposing PII.

---

11. Integration Points

Module Integration
Identity Registry Source of DID and issuer signatures for mask generation.
KYC Engine Provides KYC tier, jurisdiction, and KYC issuer signature.
AML Engine Provides AML risk score and AML issuer signature.
Compliance Supergraph May be queried to ensure profile is active before mask generation.
Financial Core Integration Can accept mask proofs as alternative to full compliance checks for certain operations.
Policy Engine Can define which mask policies are acceptable for a given action.
Event Bus Mask verifications emitted as events.

---

12. Documentation

Events

```rust
#[event]
pub struct MaskVerified {
    pub nullifier:  [u8; 32],
    pub policy_hash: [u8; 32],
    pub expiry:     i64,
    pub timestamp:  i64,
}

#[event]
pub struct MaskRevoked {
    pub nullifier: [u8; 32],
    pub reason:    String,
    pub timestamp: i64,
}
```

Error Codes

```rust
#[error_code]
pub enum MaskError {
    #[msg("Invalid Groth16 proof")]              InvalidProof,
    #[msg("Nullifier already used")]             NullifierAlreadyUsed,
    #[msg("Nullifier revoked")]                  NullifierRevoked,
    #[msg("Mask expired")]                       MaskExpired,
    #[msg("Unauthorized")]                       Unauthorized,
}
```

Repository Structure (Addition)

```
zk-identity-masks/
├── circuits/
│   └── mask_circuit.circom
├── programs/zk_identity_masks/
│   └── src/
│       ├── lib.rs
│       ├── instructions/
│       │   ├── verify_mask.rs
│       │   └── admin.rs
│       ├── state/
│       │   ├── config.rs
│       │   ├── receipt.rs
│       │   └── revocation.rs
│       ├── errors.rs
│       └── events.rs
├── sdk/zk-identity-mask-sdk/
│   └── src/
│       ├── ZkIdentityMaskSDK.ts
│       ├── prover.ts
│       └── types.ts
├── api/                          # mask generation service
└── tests/
```

---

Status: GitDigital zk‑Identity‑Masks Integration architecture complete.
Bridges the identity, KYC, and AML engines into a privacy‑preserving selective disclosure system, enabling anonymous credentialing and private authentication.
Ready for circuit development and verifier program implementation.
