# architect solana-kyc-credential-engine

---

## 1. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    KYC Credential Engine                            │
│                                                                     │
│  ┌─────────────┐   ┌──────────────┐   ┌───────────────────────┐   │
│  │  KYC Portal │──▶│  Issuer SDK  │──▶│   Anchor Program      │   │
│  │  (Frontend) │   │  (TS/Rust)   │   │   (On-chain Engine)   │   │
│  └─────────────┘   └──────────────┘   └───────────────────────┘   │
│         │                                         │                │
│         ▼                                         ▼                │
│  ┌─────────────────┐               ┌──────────────────────────┐   │
│  │  KYC Provider   │               │     PDA Accounts         │   │
│  │  (Persona /     │               │  - IssuerRecord          │   │
│  │   Sumsub / etc) │               │  - KycRecord             │   │
│  └─────────────────┘               │  - AmlRecord             │   │
│         │                          │  - ReviewQueue           │   │
│         ▼                          │  - ComplianceConfig      │   │
│  ┌─────────────────┐               └──────────────────────────┘   │
│  │  ZK Attestation │                          │                   │
│  │  Generator      │                          ▼                   │
│  └─────────────────┘               ┌──────────────────────────┐   │
│                                    │  Off-chain Indexer        │   │
│                                    │  (SQL + Event Bus)        │   │
│                                    └──────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. Subsystem Breakdown

| Subsystem | Responsibility |
|---|---|
| **Issuer Registry** | Whitelist and manage authorized KYC/AML issuers |
| **KYC Engine** | Accept, store, and manage KYC credential records |
| **AML Engine** | Screen and flag subjects against AML rule sets |
| **Review Queue** | Manual review workflow for flagged or borderline cases |
| **ZK Attestation Layer** | Privacy-preserving proof of KYC status |
| **Compliance Config** | Governance-controlled thresholds, jurisdictions, rules |
| **Expiry Manager** | Track and enforce credential expiry on-chain |
| **Indexer Service** | Off-chain event-driven SQL for fast compliance queries |

---

## 3. Solana Program Design

```rust
// programs/kyc_credential_engine/src/lib.rs

declare_id!("KYCEng111111111111111111111111111111111111111");

#[program]
pub mod kyc_credential_engine {
    use super::*;

    // ── Admin ──────────────────────────────────────────────────
    pub fn initialize_engine(
        ctx: Context<InitEngine>,
        config: ComplianceConfigParams
    ) -> Result<()>;

    pub fn update_config(
        ctx: Context<UpdateConfig>,
        config: ComplianceConfigParams
    ) -> Result<()>;

    // ── Issuer Management ──────────────────────────────────────
    pub fn register_issuer(
        ctx: Context<RegisterIssuer>,
        params: IssuerParams
    ) -> Result<()>;

    pub fn suspend_issuer(ctx: Context<SuspendIssuer>) -> Result<()>;

    pub fn revoke_issuer(ctx: Context<RevokeIssuer>) -> Result<()>;

    // ── KYC Credentials ───────────────────────────────────────
    pub fn issue_kyc(
        ctx: Context<IssueKyc>,
        params: KycParams
    ) -> Result<()>;

    pub fn update_kyc(
        ctx: Context<UpdateKyc>,
        params: KycUpdateParams
    ) -> Result<()>;

    pub fn revoke_kyc(
        ctx: Context<RevokeKyc>,
        reason: RevocationReason
    ) -> Result<()>;

    pub fn expire_kyc(ctx: Context<ExpireKyc>) -> Result<()>;

    // ── AML Screening ─────────────────────────────────────────
    pub fn submit_aml_result(
        ctx: Context<SubmitAml>,
        params: AmlParams
    ) -> Result<()>;

    pub fn flag_aml(
        ctx: Context<FlagAml>,
        reason: AmlFlagReason
    ) -> Result<()>;

    pub fn clear_aml_flag(
        ctx: Context<ClearAml>,
        resolution: String
    ) -> Result<()>;

    // ── Review Queue ──────────────────────────────────────────
    pub fn submit_for_review(
        ctx: Context<SubmitReview>,
        reason: String
    ) -> Result<()>;

    pub fn resolve_review(
        ctx: Context<ResolveReview>,
        decision: ReviewDecision
    ) -> Result<()>;

    // ── ZK Verification ───────────────────────────────────────
    pub fn verify_kyc_zk(
        ctx: Context<VerifyKycZk>,
        proof: Vec<u8>,
        public_inputs: Vec<[u8; 32]>
    ) -> Result<()>;
}
```

---

## 4. PDA Map

```
Seed Pattern → Account Type → Description
────────────────────────────────────────────────────────────────
["compliance_config"]
  → ComplianceConfig
  → Global engine settings, jurisdiction rules, thresholds

["issuer", issuer_pubkey]
  → IssuerRecord
  → Authorized KYC/AML issuer profile and permissions

["kyc", subject_wallet]
  → KycRecord
  → Subject's KYC status, tier, jurisdiction, expiry

["aml", subject_wallet]
  → AmlRecord
  → AML screening result, risk score, flag status

["review", subject_wallet]
  → ReviewQueueRecord
  → Pending manual review case with reason and status

["zk_kyc_proof", subject_wallet, verifier_pubkey]
  → ZkKycProofRecord
  → On-chain anchor of a verified ZK KYC proof
```

```rust
// PDA derivation
let (kyc_pda, bump) = Pubkey::find_program_address(
    &[b"kyc", subject_wallet.as_ref()],
    &program_id
);

let (aml_pda, bump) = Pubkey::find_program_address(
    &[b"aml", subject_wallet.as_ref()],
    &program_id
);

let (issuer_pda, bump) = Pubkey::find_program_address(
    &[b"issuer", issuer_pubkey.as_ref()],
    &program_id
);
```

---

## 5. API Schema

### REST Endpoints

```
── Admin ──────────────────────────────────────────────────────
POST   /v1/engine/initialize              → initialize engine config
PUT    /v1/engine/config                  → update compliance config
GET    /v1/engine/config                  → fetch current config

── Issuers ────────────────────────────────────────────────────
POST   /v1/issuer/register                → { tx_sig, issuer_pda }
PUT    /v1/issuer/{pubkey}/suspend        → { tx_sig }
DELETE /v1/issuer/{pubkey}/revoke         → { tx_sig }
GET    /v1/issuer/{pubkey}                → IssuerRecord
GET    /v1/issuers                        → IssuerRecord[]

── KYC ────────────────────────────────────────────────────────
POST   /v1/kyc/issue                      → { tx_sig, kyc_pda }
PUT    /v1/kyc/{subject}/update           → { tx_sig }
DELETE /v1/kyc/{subject}/revoke           → { tx_sig }
GET    /v1/kyc/{subject}                  → KycRecord
GET    /v1/kyc/{subject}/status           → { status, tier, expires_at }

── AML ────────────────────────────────────────────────────────
POST   /v1/aml/submit                     → { tx_sig, aml_pda }
POST   /v1/aml/{subject}/flag             → { tx_sig }
POST   /v1/aml/{subject}/clear            → { tx_sig }
GET    /v1/aml/{subject}                  → AmlRecord

── Review Queue ───────────────────────────────────────────────
POST   /v1/review/submit                  → { tx_sig, review_pda }
POST   /v1/review/{subject}/resolve       → { tx_sig }
GET    /v1/review/queue                   → ReviewQueueRecord[]
GET    /v1/review/{subject}               → ReviewQueueRecord

── ZK ─────────────────────────────────────────────────────────
POST   /v1/zk/prove-kyc                   → { proof, public_inputs }
POST   /v1/zk/verify-kyc                  → { valid: bool, proof_pda }
```

### Request/Response Types

```typescript
interface KycParams {
  subject:          string;         // wallet pubkey
  kyc_tier:         KycTier;        // Basic | Enhanced | Institutional
  jurisdiction:     string;         // ISO 3166-1 alpha-2 (e.g. "US", "GB")
  document_hash:    string;         // sha256 of KYC docs (never stored raw)
  issuer_did:       string;
  expires_at:       number | null;  // unix ts
  metadata_uri:     string;         // IPFS link to encrypted attestation
}

interface AmlParams {
  subject:          string;
  risk_score:       number;         // 0–100
  screening_source: string;         // e.g. "Chainalysis", "Elliptic"
  result:           AmlResult;      // Clean | Review | Flagged
  report_hash:      string;         // sha256 of AML report
  screened_at:      number;
}

interface IssuerParams {
  issuer_pubkey:    string;
  issuer_name:      string;
  issuer_did:       string;
  permissions:      IssuerPermissions;
  jurisdiction:     string[];
  metadata_uri:     string;
}
```

---

## 6. Data Models

### On-chain (Rust)

```rust
#[account]
pub struct ComplianceConfig {
    pub authority:           Pubkey,
    pub kyc_required_tiers:  Vec<KycTier>,
    pub aml_threshold:       u8,            // risk score 0-100
    pub allowed_jurisdictions: Vec<String>, // ISO codes, max 64
    pub review_timeout_secs: i64,
    pub paused:              bool,
    pub version:             u8,
    pub bump:                u8,
}

#[account]
pub struct IssuerRecord {
    pub pubkey:       Pubkey,
    pub did:          String,           // max 128
    pub name:         String,           // max 64
    pub permissions:  IssuerPermissions,
    pub jurisdictions: Vec<String>,     // max 16
    pub status:       IssuerStatus,
    pub metadata_uri: String,
    pub registered_at: i64,
    pub bump:         u8,
}

#[account]
pub struct KycRecord {
    pub subject:       Pubkey,
    pub issuer:        Pubkey,
    pub kyc_tier:      KycTier,
    pub jurisdiction:  String,          // max 8
    pub document_hash: [u8; 32],        // sha256, never raw PII
    pub status:        KycStatus,
    pub issued_at:     i64,
    pub expires_at:    Option<i64>,
    pub metadata_uri:  String,          // max 256
    pub version:       u32,
    pub bump:          u8,
}

#[account]
pub struct AmlRecord {
    pub subject:          Pubkey,
    pub issuer:           Pubkey,
    pub risk_score:       u8,           // 0–100
    pub result:           AmlResult,
    pub flag_reason:      Option<String>,
    pub report_hash:      [u8; 32],
    pub screening_source: String,       // max 64
    pub screened_at:      i64,
    pub resolved_at:      Option<i64>,
    pub bump:             u8,
}

#[account]
pub struct ReviewQueueRecord {
    pub subject:    Pubkey,
    pub submitted_by: Pubkey,
    pub reason:     String,             // max 256
    pub status:     ReviewStatus,
    pub decision:   Option<ReviewDecision>,
    pub submitted_at: i64,
    pub resolved_at:  Option<i64>,
    pub bump:       u8,
}

// ── Enums ────────────────────────────────────────────────────
#[derive(AnchorSerialize, AnchorDeserialize, Clone, PartialEq)]
pub enum KycTier { Basic, Enhanced, Institutional }

#[derive(AnchorSerialize, AnchorDeserialize, Clone, PartialEq)]
pub enum KycStatus { Active, Expired, Suspended, Revoked }

#[derive(AnchorSerialize, AnchorDeserialize, Clone, PartialEq)]
pub enum AmlResult { Clean, Review, Flagged }

#[derive(AnchorSerialize, AnchorDeserialize, Clone, PartialEq)]
pub enum AmlFlagReason { SanctionsList, PEP, HighRisk, SuspiciousActivity }

#[derive(AnchorSerialize, AnchorDeserialize, Clone, PartialEq)]
pub enum IssuerStatus { Active, Suspended, Revoked }

#[derive(AnchorSerialize, AnchorDeserialize, Clone, PartialEq)]
pub enum ReviewStatus { Pending, InReview, Resolved }

#[derive(AnchorSerialize, AnchorDeserialize, Clone, PartialEq)]
pub enum ReviewDecision { Approved, Rejected, Escalated }

#[derive(AnchorSerialize, AnchorDeserialize, Clone, PartialEq)]
pub enum RevocationReason { Expired, Fraud, Voluntary, Regulatory }

bitflags::bitflags! {
    pub struct IssuerPermissions: u64 {
        const ISSUE_KYC_BASIC       = 0b0001;
        const ISSUE_KYC_ENHANCED    = 0b0010;
        const ISSUE_KYC_INSTITUTION = 0b0100;
        const ISSUE_AML             = 0b1000;
        const REVIEW_QUEUE          = 0b10000;
    }
}
```

### Off-chain SQL

```sql
-- Compliance config cache
CREATE TABLE compliance_config (
    id              SERIAL PRIMARY KEY,
    authority       TEXT NOT NULL,
    aml_threshold   SMALLINT NOT NULL DEFAULT 70,
    paused          BOOLEAN DEFAULT FALSE,
    version         SMALLINT DEFAULT 1,
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Issuer registry
CREATE TABLE issuer_records (
    pda             TEXT PRIMARY KEY,
    pubkey          TEXT NOT NULL UNIQUE,
    did             TEXT NOT NULL,
    name            TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'Active',
    permissions     BIGINT NOT NULL,
    jurisdictions   TEXT[] NOT NULL,
    metadata_uri    TEXT,
    registered_at   TIMESTAMPTZ
);

-- KYC records
CREATE TABLE kyc_records (
    pda             TEXT PRIMARY KEY,
    subject         TEXT NOT NULL UNIQUE,
    issuer_pda      TEXT REFERENCES issuer_records(pda),
    kyc_tier        TEXT NOT NULL,
    jurisdiction    TEXT NOT NULL,
    document_hash   TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'Active',
    issued_at       TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ,
    metadata_uri    TEXT,
    version         INTEGER DEFAULT 1
);

-- AML records
CREATE TABLE aml_records (
    pda               TEXT PRIMARY KEY,
    subject           TEXT NOT NULL,
    issuer_pda        TEXT REFERENCES issuer_records(pda),
    risk_score        SMALLINT NOT NULL,
    result            TEXT NOT NULL,
    flag_reason       TEXT,
    report_hash       TEXT NOT NULL,
    screening_source  TEXT NOT NULL,
    screened_at       TIMESTAMPTZ,
    resolved_at       TIMESTAMPTZ
);

-- Review queue
CREATE TABLE review_queue (
    pda           TEXT PRIMARY KEY,
    subject       TEXT NOT NULL,
    submitted_by  TEXT NOT NULL,
    reason        TEXT NOT NULL,
    status        TEXT NOT NULL DEFAULT 'Pending',
    decision      TEXT,
    submitted_at  TIMESTAMPTZ,
    resolved_at   TIMESTAMPTZ
);

-- ZK proof anchors
CREATE TABLE zk_kyc_proofs (
    pda             TEXT PRIMARY KEY,
    subject         TEXT NOT NULL,
    verifier        TEXT NOT NULL,
    proof_hash      TEXT NOT NULL,
    public_inputs   JSONB,
    verified_at     TIMESTAMPTZ
);

-- Indexes
CREATE INDEX idx_kyc_subject     ON kyc_records(subject);
CREATE INDEX idx_kyc_status      ON kyc_records(status);
CREATE INDEX idx_kyc_jurisdiction ON kyc_records(jurisdiction);
CREATE INDEX idx_aml_subject     ON aml_records(subject);
CREATE INDEX idx_aml_result      ON aml_records(result);
CREATE INDEX idx_review_status   ON review_queue(status);
```

---

## 7. Client SDK

```typescript
// sdk/src/KycCredentialEngineSDK.ts

import { Connection, PublicKey }        from '@solana/web3.js';
import { AnchorProvider, Program, BN }  from '@coral-xyz/anchor';
import { KycCredentialEngine }          from './types';
import { IDL }                          from './idl';

export const PROGRAM_ID =
  new PublicKey('KYCEng111111111111111111111111111111111111111');

export class KycCredentialEngineSDK {
  program: Program<KycCredentialEngine>;

  constructor(connection: Connection, wallet: any) {
    const provider = new AnchorProvider(connection, wallet, {});
    this.program   = new Program(IDL, PROGRAM_ID, provider);
  }

  // ── PDA Helpers ──────────────────────────────────────────
  findKycPDA(subject: PublicKey): [PublicKey, number] {
    return PublicKey.findProgramAddressSync(
      [Buffer.from('kyc'), subject.toBuffer()],
      PROGRAM_ID
    );
  }

  findAmlPDA(subject: PublicKey): [PublicKey, number] {
    return PublicKey.findProgramAddressSync(
      [Buffer.from('aml'), subject.toBuffer()],
      PROGRAM_ID
    );
  }

  findIssuerPDA(issuer: PublicKey): [PublicKey, number] {
    return PublicKey.findProgramAddressSync(
      [Buffer.from('issuer'), issuer.toBuffer()],
      PROGRAM_ID
    );
  }

  findReviewPDA(subject: PublicKey): [PublicKey, number] {
    return PublicKey.findProgramAddressSync(
      [Buffer.from('review'), subject.toBuffer()],
      PROGRAM_ID
    );
  }

  // ── Issuer ───────────────────────────────────────────────
  async registerIssuer(params: IssuerParams): Promise<string> {
    const [issuerPDA] = this.findIssuerPDA(
      new PublicKey(params.issuer_pubkey)
    );
    return this.program.methods
      .registerIssuer(params)
      .accounts({ issuerRecord: issuerPDA })
      .rpc();
  }

  // ── KYC ─────────────────────────────────────────────────
  async issueKyc(params: KycParams): Promise<string> {
    const subject    = new PublicKey(params.subject);
    const [kycPDA]   = this.findKycPDA(subject);

    return this.program.methods
      .issueKyc({
        ...params,
        documentHash: Array.from(
          Buffer.from(params.document_hash, 'hex')
        ),
        expiresAt: params.expires_at
          ? new BN(params.expires_at)
          : null,
      })
      .accounts({ kycRecord: kycPDA })
      .rpc();
  }

  async revokeKyc(
    subject: PublicKey,
    reason: RevocationReason
  ): Promise<string> {
    const [kycPDA] = this.findKycPDA(subject);
    return this.program.methods
      .revokeKyc(reason)
      .accounts({ kycRecord: kycPDA })
      .rpc();
  }

  // ── AML ─────────────────────────────────────────────────
  async submitAmlResult(params: AmlParams): Promise<string> {
    const subject    = new PublicKey(params.subject);
    const [amlPDA]   = this.findAmlPDA(subject);

    return this.program.methods
      .submitAmlResult({
        ...params,
        reportHash: Array.from(
          Buffer.from(params.report_hash, 'hex')
        ),
      })
      .accounts({ amlRecord: amlPDA })
      .rpc();
  }

  async flagAml(
    subject: PublicKey,
    reason: AmlFlagReason
  ): Promise<string> {
    const [amlPDA] = this.findAmlPDA(subject);
    return this.program.methods
      .flagAml(reason)
      .accounts({ amlRecord: amlPDA })
      .rpc();
  }

  // ── Review ───────────────────────────────────────────────
  async submitForReview(
    subject: PublicKey,
    reason: string
  ): Promise<string> {
    const [reviewPDA] = this.findReviewPDA(subject);
    return this.program.methods
      .submitForReview(reason)
      .accounts({ reviewRecord: reviewPDA })
      .rpc();
  }

  async resolveReview(
    subject: PublicKey,
    decision: ReviewDecision
  ): Promise<string> {
    const [reviewPDA] = this.findReviewPDA(subject);
    return this.program.methods
      .resolveReview(decision)
      .accounts({ reviewRecord: reviewPDA })
      .rpc();
  }

  // ── Queries ──────────────────────────────────────────────
  async getKycRecord(subject: PublicKey) {
    const [pda] = this.findKycPDA(subject);
    return this.program.account.kycRecord.fetch(pda);
  }

  async getAmlRecord(subject: PublicKey) {
    const [pda] = this.findAmlPDA(subject);
    return this.program.account.amlRecord.fetch(pda);
  }

  async isKycActive(subject: PublicKey): Promise<boolean> {
    try {
      const record = await this.getKycRecord(subject);
      const now    = Math.floor(Date.now() / 1000);
      return (
        record.status.active !== undefined &&
        (record.expiresAt === null || record.expiresAt.toNumber() > now)
      );
    } catch {
      return false;
    }
  }

  async isAmlClean(subject: PublicKey): Promise<boolean> {
    try {
      const record = await this.getAmlRecord(subject);
      return record.result.clean !== undefined;
    } catch {
      return false;
    }
  }

  async getReviewQueue() {
    return this.program.account.reviewQueueRecord.all([
      {
        memcmp: {
          offset: 8 + 32 + 32 + 4,
          bytes: Buffer.from('Pending').toString('base64'),
        },
      },
    ]);
  }
}
```

---

## 8. Workflows

### Full KYC Issuance Flow

```
KYC Provider (Persona / Sumsub)
    │
    ├─ 1. Subject submits documents to KYC portal (off-chain)
    ├─ 2. Provider verifies identity, assigns tier + jurisdiction
    ├─ 3. Provider hashes documents: sha256(docs) = document_hash
    ├─ 4. Provider uploads encrypted attestation → IPFS → metadata_uri
    │
Authorized Issuer
    ├─ 5. SDK: issueKyc({ subject, kyc_tier, jurisdiction, document_hash, expires_at })
    ├─ 6. Program: check issuer is registered + has ISSUE_KYC_* permission
    ├─ 7. Program: check compliance_config not paused
    ├─ 8. Program: create KycRecord PDA
    ├─ 9. Program: emit KycIssued event
    └─ 10. Indexer: writes to kyc_records SQL table
```

### AML Screening Flow

```
AML Screening Service (Chainalysis / Elliptic)
    │
    ├─ 1. Screen subject wallet against sanctions + PEP lists
    ├─ 2. Compute risk_score (0–100), assign AmlResult
    ├─ 3. Hash AML report: report_hash
    │
    ├─ If risk_score < aml_threshold (e.g. < 70)
    │       └─ submitAmlResult({ result: Clean })
    │
    ├─ If risk_score >= threshold and < 90
    │       ├─ submitAmlResult({ result: Review })
    │       └─ submitForReview("Score 75 – manual review required")
    │
    └─ If risk_score >= 90 OR sanctions match
            ├─ submitAmlResult({ result: Flagged })
            └─ flagAml({ reason: SanctionsList })
```

### ZK KYC Proof Flow

```
Subject wants to prove KYC status to a DeFi protocol
    │
    ├─ 1. Off-chain: generate ZK proof
    │       Public  inputs: kyc_pda, kyc_tier, jurisdiction
    │       Private inputs: document_hash, issuer_sig, subject_key
    │       Statement: "I have Active KYC of tier >= Enhanced in jurisdiction US"
    │
    ├─ 2. SDK: verifyKycZk({ proof, public_inputs })
    ├─ 3. Program: call alt_bn128 precompile → verify Groth16
    ├─ 4. Program: confirm kyc_pda is Active + not expired
    ├─ 5. Program: create ZkKycProofRecord
    └─ 6. DeFi protocol: reads ZkKycProofRecord → grants access
         (never sees raw identity data)
```

### Review Queue Resolution

```
Compliance Officer
    │
    ├─ 1. GET /v1/review/queue → list of Pending cases
    ├─ 2. Review off-chain IPFS metadata + AML report
    │
    ├─ Decision: Approved
    │       ├─ resolveReview({ decision: Approved })
    │       └─ If KYC was pending → issueKyc(...)
    │
    ├─ Decision: Rejected
    │       └─ resolveReview({ decision: Rejected })
    │          (no KYC issued; subject notified off-chain)
    │
    └─ Decision: Escalated
            └─ resolveReview({ decision: Escalated })
               (moves to senior compliance officer queue)
```

---

## 9. Security Considerations

| Threat | Mitigation |
|---|---|
| Unauthorized KYC issuance | Issuer must be registered; permissions bitmask enforced on-chain |
| PII on-chain | Only `document_hash` (sha256) stored; raw data on IPFS encrypted |
| KYC forgery | Document hash verified against IPFS metadata; issuer signature required |
| Stale credentials | `expires_at` enforced on-chain; `isKycActive()` checks timestamp |
| AML threshold manipulation | `aml_threshold` stored in `ComplianceConfig`; authority is multisig |
| Proof replay | ZK proofs include nullifier (subject + timestamp); double-use rejected |
| Issuer compromise | Authority can `suspend_issuer` or `revoke_issuer` immediately |
| Review queue abuse | Only issuers with `REVIEW_QUEUE` permission can submit/resolve |
| Config hijack | `ComplianceConfig` authority is a Squads 5/9 multisig |
| Jurisdiction bypass | Jurisdiction string validated against allowed list in config |

---

## 10. Compliance Considerations

| Requirement | Implementation |
|---|---|
| FATF Travel Rule | `jurisdiction` field on `KycRecord`; cross-border flows gated by jurisdiction allow-list |
| GDPR Article 25 | No raw PII on-chain; IPFS data is encrypted; `document_hash` is one-way |
| 5AMLD / 6AMLD | Enhanced KYC tier required for high-risk jurisdictions; AML screening mandatory |
| OFAC / Sanctions | `AmlFlagReason::SanctionsList` blocks subject immediately |
| PEP Screening | `AmlFlagReason::PEP` triggers mandatory review queue |
| Accredited Investor | `KycTier::Institutional` required for RWA interactions |
| Audit Trail | All state changes emit on-chain events; immutable and timestamped |
| Right to Erasure | Raw data deleted off-chain; on-chain hash remains (no PII) |
| Record Retention | `expires_at` enforced; issuer controls renewal cycle |
| Cross-border Compliance | `allowed_jurisdictions` in `ComplianceConfig` governs which regions are served |

---

## 11. Integration Points

| Module | Integration |
|---|---|
| **solana-identity-registry** | KYC issued as a `CredentialRecord` linked to subject's `IdentityRecord` |
| **zk-Identity-masks** | ZK proofs use `KycRecord` as witness source for privacy-preserving KYC checks |
| **GitDigital Financial Core** | Financial operations require `isKycActive()` + `isAmlClean()` before execution |
| **Aurora-zk-cryptography-framework** | Groth16 circuits for ZK KYC proof generation |
| **solana-governance-policy-engine** | Governance participation gated by KYC tier |
| **ZK-5D-Badge-Authority-app** | KYC tier feeds into badge authority level assignment |
| **zk-authorship-license** | Institutional authorship requires `KycTier::Institutional` |
| **Persona / Sumsub** | Off-chain KYC provider webhooks trigger issuer SDK calls |
| **Chainalysis / Elliptic** | AML screening results submitted via `submitAmlResult` |

---

## 12. Documentation

### Events

```rust
#[event]
pub struct KycIssued {
    pub subject:    Pubkey,
    pub issuer:     Pubkey,
    pub kyc_tier:   KycTier,
    pub jurisdiction: String,
    pub expires_at: Option<i64>,
    pub timestamp:  i64,
}

#[event]
pub struct KycRevoked {
    pub subject:  Pubkey,
    pub reason:   RevocationReason,
    pub timestamp: i64,
}

#[event]
pub struct AmlResultSubmitted {
    pub subject:    Pubkey,
    pub risk_score: u8,
    pub result:     AmlResult,
    pub timestamp:  i64,
}

#[event]
pub struct AmlFlagged {
    pub subject:  Pubkey,
    pub reason:   AmlFlagReason,
    pub timestamp: i64,
}

#[event]
pub struct ReviewResolved {
    pub subject:   Pubkey,
    pub decision:  ReviewDecision,
    pub timestamp: i64,
}

#[event]
pub struct ZkKycVerified {
    pub subject:   Pubkey,
    pub verifier:  Pubkey,
    pub kyc_tier:  KycTier,
    pub timestamp: i64,
}
```

### Error Codes

```rust
#[error_code]
pub enum KycError {
    #[msg("Engine is paused")]                    EnginePaused,
    #[msg("Issuer not registered")]               IssuerNotRegistered,
    #[msg("Issuer lacks required permission")]    IssuerPermissionDenied,
    #[msg("Subject already has active KYC")]      DuplicateKyc,
    #[msg("KYC record is revoked")]               KycRevoked,
    #[msg("KYC record has expired")]              KycExpired,
    #[msg("AML flag is active – action blocked")] AmlFlagActive,
    #[msg("Jurisdiction not allowed")]            JurisdictionBlocked,
    #[msg("Invalid ZK proof")]                    InvalidZkProof,
    #[msg("Risk score exceeds threshold")]        RiskThresholdExceeded,
    #[msg("Review still pending")]                ReviewPending,
    #[msg("Unauthorized")]                        Unauthorized,
}
```

### Repository Structure

```
kyc-credential-engine/
├── programs/kyc_credential_engine/
│   └── src/
│       ├── lib.rs
│       ├── instructions/
│       │   ├── initialize_engine.rs
│       │   ├── register_issuer.rs
│       │   ├── suspend_issuer.rs
│       │   ├── issue_kyc.rs
│       │   ├── update_kyc.rs
│       │   ├── revoke_kyc.rs
│       │   ├── submit_aml_result.rs
│       │   ├── flag_aml.rs
│       │   ├── clear_aml_flag.rs
│       │   ├── submit_for_review.rs
│       │   ├── resolve_review.rs
│       │   └── verify_kyc_zk.rs
│       ├── state/
│       │   ├── compliance_config.rs
│       │   ├── issuer_record.rs
│       │   ├── kyc_record.rs
│       │   ├── aml_record.rs
│       │   └── review_queue_record.rs
│       ├── errors.rs
│       └── events.rs
├── sdk/
│   └── src/
│       ├── KycCredentialEngineSDK.ts
│       ├── types.ts
│       └── idl.json
├── services/
│   ├── indexer/
│   ├── api/
│   └── webhooks/          ← Persona / Sumsub / Chainalysis handlers
├── schemas/
│   └── postgres/
└── tests/
    ├── anchor/
    └── integration/
```

---

**Status:** Architecture complete. Ready for `anchor build`.
