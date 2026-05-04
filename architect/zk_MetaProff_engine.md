ZK MetaProof Engine

Unified Zero‑Knowledge Credential — the universal GitDigital passport

A single Groth16 proof that attests:

“I am a valid GitDigital user with Active Identity, Active KYC (≥ required tier), and AML score below threshold — without revealing identity, tier, jurisdiction, score, or any issuer.”

This meta‑proof aggregates the individual ZK proofs from the Identity, KYC, and AML engines into one compact, privacy‑preserving credential that can be verified on‑chain in a single transaction.

---

1. High‑Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     ZK MetaProof Engine                                 │
│          Single Unified Proof over Identity + KYC + AML                 │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    MetaProof Circuit (.circom)                    │  │
│  │  ┌─────────────┐  ┌─────────────────┐  ┌────────────────────┐    │  │
│  │  │ Identity    │  │ KYC Credential  │  │ AML Risk Proof     │    │  │
│  │  │ Proof       │  │ Proof           │  │                    │    │  │
│  │  │ (Groth16)   │  │ (Groth16)       │  │ (Groth16)          │    │  │
│  │  └──────┬──────┘  └───────┬─────────┘  └─────────┬──────────┘    │  │
│  │         │                 │                      │               │  │
│  │         └─────────────────▼──────────────────────┘               │  │
│  │                    ┌──────────────────┐                           │  │
│  │                    │   Aggregator     │                           │  │
│  │                    │   Logic          │                           │  │
│  │                    │   (AND + range   │                           │  │
│  │                    │    checks)       │                           │  │
│  │                    └────────┬─────────┘                           │  │
│  │                             │                                      │  │
│  │                    Public Outputs:                                 │  │
│  │                    ├─ policy_hash                                  │  │
│  │                    ├─ subject_nullifier                            │  │
│  │                    └─ expiry_timestamp                             │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │              Solana Verification Program (Anchor)                 │  │
│  │  ┌───────────────────────┐    ┌───────────────────────────────┐  │  │
│  │  │ verify_meta_proof     │    │  PDA: MetaProofRecord         │  │  │
│  │  │ (Groth16 verify +     │    │  ├─ proof_hash                 │  │  │
│  │  │  policy & nullifier   │    │  ├─ subject_nullifier          │  │  │
│  │  │  checks)              │    │  ├─ policy                     │  │  │
│  │  └───────────────────────┘    │  └─ verified_at                │  │  │
│  │                               └───────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                     Off‑Chain Services                            │  │
│  │  • Prover (browser / server) — snarkjs, WASM                      │  │
│  │  • MetaProof Cache — SQL for verified proofs                      │  │
│  │  • Revocation List — nullifier‑based                              │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

2. Subsystem Breakdown

Subsystem Responsibility
MetaProof Circuit (Circom) Recursive aggregation circuit: verifies three individual engine proofs and adds policy/threshold constraints, then outputs a single Groth16 proof.
Solana MetaProof Verifier Program On‑chain program that verifies the Groth16 proof via Alt‑BN128 precompile, checks policy requirements, nullifier uniqueness, and expiration.
MetaProofRecord PDA On‑chain anchor recording verified proof hash, subject nullifier, policy, and timestamp to prevent double‑use and enable audit.
Nullifier Registry PDA that stores used nullifiers to prevent proof replay across all verifications.
Prover SDK Client library (TypeScript/WASM) that generates the meta‑proof from the three sub‑proofs and user’s private inputs.
Off‑chain MetaProof Cache SQL table storing verified proofs for quick lookups and dashboards.
Revocation Service Allows engine issuers to revoke underlying credentials; affected nullifiers added to revocation list.

---

3. Solana Program Design

```rust
// programs/zk_metaproof/src/lib.rs

declare_id!("ZkMetaP11111111111111111111111111111111111");

#[program]
pub mod zk_metaproof {
    use super::*;

    pub fn verify_meta_proof(
        ctx: Context<VerifyMetaProof>,
        proof: Vec<u8>,
        public_inputs: Vec<[u8; 32]>,
    ) -> Result<()>;
    // Verifies the Groth16 proof, then:
    //   - checks policy hash matches current requirement
    //   - checks nullifier is unused
    //   - checks expiry not passed
    //   - writes MetaProofRecord

    pub fn revoke_nullifier(
        ctx: Context<RevokeNullifier>,
        nullifier: [u8; 32],
    ) -> Result<()>;
    // Authority (engine issuers) revokes a nullifier

    pub fn initialize_config(
        ctx: Context<InitializeConfig>,
        verifying_key: Vec<u8>,
        authority: Pubkey,
    ) -> Result<()>;

    pub fn update_config(
        ctx: Context<UpdateConfig>,
        verifying_key: Option<Vec<u8>>,
        authority: Option<Pubkey>,
    ) -> Result<()>;
}
```

---

4. PDA Map

```
Seed Pattern → Account Type → Description
──────────────────────────────────────────────────────────────────────
["metaproof_config"]
  → MetaProofConfig
  → Verifying key, authority (multisig), supported policies

["metaproof_record", subject_nullifier]
  → MetaProofRecord
  → Proof verification anchor; ensures nullifier is used only once

["nullifier_revocation", nullifier]
  → NullifierRevocation
  → Marks a nullifier as revoked by an issuer authority

["metaproof_policy", policy_name]
  → MetaProofPolicy
  → Defines what the meta‑proof must attest (e.g., KycEnhanced)
```

---

5. API Schema

REST Endpoints

```
── MetaProof Generation (off‑chain) ───────────────────────────────────
POST   /v1/metaproof/generate          → { proof, public_inputs }
  Body: {
    identity_proof,
    kyc_proof,
    aml_proof,
    required_policy: "KycEnhanced",
    expiry_timestamp: 1712345678
  }

── On‑chain Verification ──────────────────────────────────────────────
POST   /v1/metaproof/verify            → { tx_sig, record_pda, valid }
GET    /v1/metaproof/status/{nullifier} → { valid, verified_at, revoked }
GET    /v1/metaproof/records/{subject}  → MetaProofRecord[]  (by nullifier prefix)
POST   /v1/metaproof/revoke            → { tx_sig }  (admin only)

── Configuration ──────────────────────────────────────────────────────
GET    /v1/metaproof/config             → MetaProofConfig
```

Core Request Types

```typescript
interface GenerateMetaProofRequest {
  identity_proof: {
    proof: Uint8Array;
    public_inputs: [string, string][];
  };
  kyc_proof: {
    proof: Uint8Array;
    public_inputs: [string, string][];
  };
  aml_proof: {
    proof: Uint8Array;
    public_inputs: [string, string][];
  };
  required_policy: string;      // e.g., "KycEnhanced"
  expiry_timestamp: number;     // unix seconds
}

interface MetaProofResult {
  proof: Uint8Array;
  public_inputs: Uint8Array[];  // [policy_hash, subject_nullifier, expiry_timestamp]
}

interface VerifyMetaProofRequest {
  proof: Uint8Array;
  public_inputs: Uint8Array[];
}
```

---

6. Data Models

On‑chain (Rust)

```rust
#[account]
pub struct MetaProofConfig {
    pub authority:          Pubkey,      // multisig that can update VK / policies
    pub verifying_key:      Vec<u8>,     // Groth16 VK serialized
    pub supported_policies: Vec<MetaProofPolicy>,  // max 10
    pub bump:               u8,
}

#[account]
pub struct MetaProofRecord {
    pub proof_hash:         [u8; 32],    // keccak256(proof)
    pub subject_nullifier:  [u8; 32],    // unique per subject + policy
    pub policy_hash:        [u8; 32],    // hash of required policy
    pub expiry_timestamp:   i64,
    pub verified_at:        i64,
    pub bump:               u8,
}

#[account]
pub struct NullifierRevocation {
    pub nullifier:      [u8; 32],
    pub revoked_by:     Pubkey,          // issuer authority
    pub reason:         String,          // max 128
    pub revoked_at:     i64,
    pub bump:           u8,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct MetaProofPolicy {
    pub name:                 String,      // "KycEnhanced"
    pub required_compliance:  AccessPolicy, // from supergraph
    pub max_aml_score:        u8,           // e.g., 70
    pub min_kyc_tier:         u8,           // 2 = Enhanced
}
```

Off‑chain SQL (MetaProof Cache)

```sql
CREATE TABLE metaproof_records (
    proof_hash          TEXT PRIMARY KEY,
    subject_nullifier   TEXT NOT NULL UNIQUE,
    policy_hash         TEXT NOT NULL,
    expiry_timestamp    TIMESTAMPTZ NOT NULL,
    verified_at         TIMESTAMPTZ DEFAULT NOW(),
    revoked             BOOLEAN DEFAULT FALSE
);

CREATE TABLE metaproof_revocations (
    nullifier       TEXT PRIMARY KEY,
    revoked_by      TEXT NOT NULL,
    reason          TEXT,
    revoked_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Index for quick nullifier lookups
CREATE INDEX idx_nullifier ON metaproof_records(subject_nullifier);
```

---

7. Client SDK

```typescript
// sdk/src/ZkMetaProofSDK.ts

export class ZkMetaProofSDK {
  program: Program<ZkMetaProof>;

  // ── Generate Meta‑Proof (client‑side) ──────────────────────────
  async generateMetaProof(
    identityProof: ProofBundle,
    kycProof: ProofBundle,
    amlProof: ProofBundle,
    policy: MetaProofPolicy,
    expiry: number
  ): Promise<MetaProofResult> {
    // 1. Load WASM prover & circuit
    // 2. Aggregate proofs using recursive SNARK aggregation in circom
    // 3. Output single Groth16 proof + public inputs
    const { proof, publicInputs } = await snarkjs.groth16.fullProve(
      {
        identity_proof: identityProof.proof,
        identity_inputs: identityProof.publicInputs,
        kyc_proof: kycProof.proof,
        kyc_inputs: kycProof.publicInputs,
        aml_proof: amlProof.proof,
        aml_inputs: amlProof.publicInputs,
        policy_hash: poseidonHash(policy),
        subject_nullifier: deriveNullifier(subject, policy),
        expiry_timestamp: expiry
      },
      'meta_circuit.wasm',
      'meta_circuit_final.zkey'
    );
    return { proof, publicInputs };
  }

  // ── On‑chain Verification ──────────────────────────────────────
  async verifyMetaProof(
    proof: Uint8Array,
    publicInputs: Uint8Array[]
  ): Promise<string> {
    const proofHash = keccak256(proof);
    const [recordPDA] = PublicKey.findProgramAddressSync(
      [Buffer.from('metaproof_record'), publicInputs[1]], // subject_nullifier
      PROGRAM_ID
    );
    return this.program.methods
      .verifyMetaProof(Array.from(proof), publicInputs.map(i => Array.from(i)))
      .accounts({
        metaProofRecord: recordPDA,
        metaProofConfig: configPDA,
        nullifierRevocation: nullifierRevocationPDA(publicInputs[1]),
      })
      .rpc();
  }

  // ── Check if nullifier is valid ────────────────────────────────
  async isNullifierValid(nullifier: Uint8Array): Promise<boolean> {
    try {
      const record = await this.program.account.metaProofRecord.fetch(
        findMetaProofRecordPDA(nullifier)[0]
      );
      return !record.expired && !record.revoked;
    } catch { return false; }
  }
}
```

---

8. Workflows

MetaProof Generation Flow

```
User has already obtained:
  ◦ Identity ZK proof (proves they are registered)
  ◦ KYC ZK proof (proves tier and validity)
  ◦ AML ZK proof (proves score below threshold)

1. User selects required policy (e.g., "KycEnhanced") and expiry.
2. Client SDK loads the MetaProof WASM circuit.
3. Circuit internally:
    a. Verifies Identity proof (Groth16) using embedded VK.
    b. Verifies KYC proof (Groth16).
    c. Verifies AML proof (Groth16).
    d. Checks that KYC tier ≥ policy.min_kyc_tier (range proof).
    e. Checks that AML score ≤ policy.max_aml_score.
    f. Computes policy_hash = Poseidon(policy) and
       subject_nullifier = Poseidon(subject, policy) (binding to user).
    g. Asserts expiry_timestamp > current timestamp.
4. Outputs a single Groth16 proof with public inputs:
    [policy_hash, subject_nullifier, expiry_timestamp].
5. The proof, together with those three public inputs, can now be submitted to Solana.
```

On‑Chain Verification Flow

```
Caller (any program or user) submits verify_meta_proof(proof, [policy_hash, subject_nullifier, expiry])

1. Program loads MetaProofConfig PDA, retrieves Groth16 verifying key.
2. Calls alt_bn128 precompile to verify the proof:
   - If invalid → revert.
3. Checks that policy_hash matches one of the supported policies in config.
4. Checks that expiry_timestamp > current_slot timestamp.
5. Checks that subject_nullifier has not been used before:
   - Reads MetaProofRecord PDA; if it exists → revert (double‑use).
   - Reads NullifierRevocation PDA; if it exists and not expired → revert.
6. Writes MetaProofRecord PDA:
   - proof_hash = keccak256(proof)
   - subject_nullifier
   - policy_hash
   - expiry_timestamp
   - verified_at = Clock::get()?.unix_timestamp
7. Emits MetaProofVerified event.
8. Returns Ok.
```

Revocation Flow

```
Issuer authority (e.g., KYC Engine admin) detects that a user’s KYC is revoked retroactively.
1. Admin calls revoke_nullifier(nullifier) with a reason.
2. Program verifies admin's authority (must match KYC engine authority or multisig).
3. Creates/updates NullifierRevocation PDA with revoked=true.
4. Any future verify_meta_proof for that nullifier will fail because revocation PDA exists.
5. Already‑verified proofs are considered invalid for new authorizations; real‑time checks can query the revocation status.
```

---

9. Security Considerations

Threat Mitigation
Proof forgery Groth16 proof verified by Solana’s alt_bn128 precompile; VK stored on‑chain and only updatable by multisig.
Double‑use (replay) Subject nullifier is unique per user+policy; once recorded, any reuse fails.
Stale proof reuse after expiry Expiry timestamp embedded in proof; program checks against clock.
Revoked underlying credential Revocation service can revoke the nullifier on‑chain; all verifications then fail.
Circuit backdoor / wrong policy constraints Circuit is audited open‑source; its verifying key frozen in program config.
Privacy leakage Public inputs reveal only hash of policy and a nullifier (no identity, tier, or score).
Policy downgrade Policy hash commitment prevents altering required criteria after proof generation.
Unauthorized revocation Only designated issuer authorities can revoke; enforced by PDA seeds and signer checks.

---

10. Compliance Considerations

Requirement Implementation
GDPR/data minimization No personal data on‑chain; only hashes and nullifiers.
Right to be forgotten Revocation of nullifier effectively invalidates the proof; no additional off‑chain deletion needed.
Auditability Every verification logged on‑chain via MetaProofRecord PDA with timestamp.
Selective disclosure The meta‑proof can be extended to prove only subsets (e.g., “KYC Tier ≥ 2” without revealing exact tier).
Regulatory reporting Verifiers can query verification history by nullifier; no raw KYC data exposed.

---

11. Integration Points

Module Integration
Compliance Supergraph Policy definitions (AccessPolicy) consumed to define MetaProofPolicy requirements.
ZK Identity Registry Identity proof is an input to the meta‑circuit.
ZK KYC Credential Engine KYC proof provides tier and jurisdiction in zero‑knowledge.
ZK AML Risk Engine AML proof provides risk score below threshold.
Policy & Authorization Engine External programs CPIs verify_meta_proof as an alternative to full compliance check; policy engine can accept a valid meta‑proof as satisfying credential requirements.
Solana Alt‑BN128 syscall On‑chain Groth16 verification.
Snarkjs / Circom Toolchain for circuit compilation, witness generation, and proof generation (WASM in browser).

---

12. Documentation

Events

```rust
#[event]
pub struct MetaProofVerified {
    pub proof_hash:        [u8; 32],
    pub subject_nullifier: [u8; 32],
    pub policy_hash:       [u8; 32],
    pub expiry_timestamp:  i64,
    pub timestamp:         i64,
}

#[event]
pub struct NullifierRevoked {
    pub nullifier:  [u8; 32],
    pub revoked_by: Pubkey,
    pub reason:     String,
    pub timestamp:  i64,
}
```

Error Codes

```rust
#[error_code]
pub enum MetaProofError {
    #[msg("Invalid Groth16 proof")]                InvalidProof,
    #[msg("Policy not supported")]                 PolicyNotSupported,
    #[msg("Proof expired")]                        ProofExpired,
    #[msg("Nullifier already used")]               NullifierAlreadyUsed,
    #[msg("Nullifier revoked")]                    NullifierRevoked,
    #[msg("Unauthorized to revoke")]               UnauthorizedRevoker,
    #[msg("Verifying key not set")]                VerifyingKeyNotSet,
}
```

Repository Structure (Addition)

```
zk-metaproof-engine/
├── circuits/
│   └── meta_proof.circom          # Aggregation circuit
├── programs/zk_metaproof/
│   └── src/
│       ├── lib.rs
│       ├── instructions/
│       │   ├── verify_meta_proof.rs
│       │   └── revoke_nullifier.rs
│       ├── state/
│       │   ├── config.rs
│       │   ├── record.rs
│       │   └── revocation.rs
│       ├── errors.rs
│       └── events.rs
├── sdk/zk-metaproof-sdk/
│   └── src/
│       ├── ZkMetaProofSDK.ts
│       ├── prover.ts               # WASM prover wrapper
│       └── types.ts
├── services/
│   └── revocation-service/        # Listens for engine events, revokes nullifiers
└── tests/
    ├── circuit/                   # Circom unit tests
    └── anchor/                    # Integration tests
```

---

Status: ZK MetaProof Engine architecture complete.
Unifies Identity, KYC, and AML into a single privacy‑preserving passport.
Ready for circuit development and on‑chain verification program.
