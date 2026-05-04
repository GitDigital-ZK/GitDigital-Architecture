Event Bus + Indexer Supernode

Unified, real‑time event backbone powering dashboards, alerts, cross‑program correlation, analytics, and AI agents — a single supernode that ingests every compliance event across the entire GitDigital stack.

No more siloed indexers. This supernode replaces per‑module database watchers with a centralised, horizontally scalable event pipeline: Redpanda (Kafka‑compatible) → processing workers → PostgreSQL (operational) + ClickHouse (analytics).

---

1. High‑Level Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         On‑Chain Programs (Solana)                            │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐│
│  │Identity  │ │KYC Engine│ │AML Risk  │ │Supergraph│ │Policy Eng│ │ZK Meta ││
│  │Registry  │ │          │ │Engine    │ │          │ │          │ │Proof   ││
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬───┘│
│       │            │            │            │            │            │     │
│       └────────────┴──────┬─────┴────────────┴────────────┴────────────┘     │
│                           │  Anchor Events + Transaction Logs                │
└───────────────────────────┼──────────────────────────────────────────────────┘
                            │  Geyser Plugin / RPC Polling / WebSocket subs
┌───────────────────────────▼──────────────────────────────────────────────────┐
│                         Event Ingestion Layer                                 │
│  ┌──────────────────────────────┐  ┌──────────────────────────────────────┐  │
│  │  Solana Geyser Plugin        │  │  Historical Backfill Worker          │  │
│  │  (near‑real‑time)            │  │  (Geyser/RPC for catch‑up)           │  │
│  └──────────────┬───────────────┘  └───────────────┬──────────────────────┘  │
│                 │                                  │                         │
│                 └──────────────┬───────────────────┘                         │
│                                │                                             │
│  ┌─────────────────────────────▼───────────────────────────────────────┐    │
│  │                          Redpanda / Kafka                            │    │
│  │  Topics: compliance.events, identity.events, aml.alerts,             │    │
│  │          policy.changes, zk.verifications, bridge.attestations       │    │
│  └─────────┬───────────────────────────────────┬───────────────────────┘    │
│            │                                   │                            │
│  ┌─────────▼──────────┐              ┌─────────▼──────────┐                  │
│  │  Stream Processors │              │  Alerting Engine   │                  │
│  │  (TypeScript/Go)   │              │  (real‑time rules) │                  │
│  └─────────┬──────────┘              └─────────┬──────────┘                  │
│            │                                   │                            │
│  ┌─────────▼──────────────────┐   ┌───────────▼────────────────────────┐    │
│  │  PostgreSQL                │   │  ClickHouse (Analytics)             │    │
│  │  (Operational state,       │   │  (Time‑series, aggregations,        │    │
│  │   unified profiles,        │   │   dashboard queries, ML training)   │    │
│  │   searchable records)      │   │                                    │    │
│  └────────────────────────────┘   └────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────────────────┐
│                         Unified Query API (REST / WS)                        │
│                                                                              │
│  ┌───────────────────────┐  ┌────────────────────┐  ┌────────────────────┐  │
│  │  Dashboard Backend    │  │  AI / ML Agents     │  │  External Services  │  │
│  └───────────────────────┘  └────────────────────┘  └────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

2. Subsystem Breakdown

Subsystem Responsibility
Solana Geyser Plugin Subscribes to account updates and transactions on the Solana validator, streams raw events with minimal latency.
Redpanda Cluster Distributed streaming platform (Kafka API). Topics for each event category, with configurable retention. Acts as the durable event log.
Stream Processors Consume raw events from Redpanda, normalise them into a common schema, enrich with cross‑program data (e.g., link an AML alert to a compliance profile), and write to operational stores.
Alerting Engine Runs user‑defined rules in real time (e.g., “risk score > 70 + jurisdiction = XX”) and dispatches notifications via WebSocket, webhook, or email.
PostgreSQL (Operational) Stores the latest materialised state: unified compliance profiles, alert queues, case management data, policy versions. Optimised for point queries and joins.
ClickHouse (Analytics) Columnar, time‑series database for analytical queries: hourly risk score aggregations, daily proof verification counts, dashboard trend charts, ML feature stores.
Unified Query API Thin GraphQL/REST layer that routes queries to the right store (Postgres for operational, ClickHouse for analytics) and provides a consolidated WebSocket stream.
Backfill Worker Processes historical transactions for bootstrapping or disaster recovery, ensuring no gaps in the event log.

---

3. Event Schema (Cross‑Program Normalised)

All on‑chain events and system events are mapped to a single event envelope:

```typescript
interface UnifiedEvent {
  // Header
  event_id:        string;           // unique, e.g., txSig + instruction index
  event_type:      string;           // e.g., "ProfileSynced", "AccessDenied", "AmlAlert"
  source_program:  string;           // e.g., "compliance_supergraph", "aml_risk_engine"
  chain:           string;           // "solana-mainnet"
  timestamp:       number;           // unix seconds

  // Subject
  subject?:        string;           // wallet pubkey
  subject_profile_snapshot?: {       // optional, if relevant
    overall_status: string;
    risk_score: number;
  };

  // Action (for policy/access events)
  action?: {
    program_id: string;
    instruction: string;
  };

  // Payload (program‑specific, but typed)
  payload:         Record<string, any>;

  // Correlation
  correlation_id?: string;           // links related events (e.g., AML case lifecycle)
  parent_event_id?: string;
}
```

Example: AML Alert Event

```json
{
  "event_id": "tx_abc123_2",
  "event_type": "AmlRiskUpdated",
  "source_program": "aml_risk_engine",
  "chain": "solana-mainnet",
  "timestamp": 1712345678,
  "subject": "5X...xyz",
  "payload": {
    "old_score": 65,
    "new_score": 85,
    "reason": "Sanctions list match",
    "is_escalation": true
  },
  "correlation_id": null
}
```

---

4. Data Models (Storage)

PostgreSQL (Operational Schema – extension of existing tables)

Key tables are already defined in previous modules (compliance_profiles, access_gate_cache, compliance_events, aml_alerts, aml_cases, etc.). The supernode normalises and stores the same data but from a unified pipeline. Additional tables:

```sql
-- Processed event log (immutable, materialised from raw events)
CREATE TABLE unified_events (
    event_id        TEXT PRIMARY KEY,
    event_type      TEXT NOT NULL,
    source_program  TEXT NOT NULL,
    subject         TEXT,
    payload         JSONB NOT NULL,
    correlation_id  TEXT,
    ingested_at     TIMESTAMPTZ NOT NULL,
    block_slot      BIGINT,
    block_time      TIMESTAMPTZ
);

-- Cross‑program correlation table (links between events)
CREATE TABLE event_correlations (
    correlation_id  TEXT PRIMARY KEY,
    root_event_id   TEXT NOT NULL,     -- first event in lifecycle
    related_events  TEXT[] NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL
);
```

ClickHouse (Analytics)

```sql
CREATE TABLE unified_events_ts (
    event_id        String,
    event_type      LowCardinality(String),
    source_program  LowCardinality(String),
    subject         String,
    payload         String,             -- JSON stored as String, can be parsed with functions
    correlation_id  Nullable(String),
    block_time      DateTime,
    block_slot      UInt64
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(block_time)
ORDER BY (subject, event_type, block_time);

-- Materialized aggregation for dashboards
CREATE MATERIALIZED VIEW hourly_risk_stats
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(hour)
ORDER BY (hour, jurisdiction)
AS SELECT
    toStartOfHour(block_time) AS hour,
    JSONExtractString(payload, 'jurisdiction') AS jurisdiction,
    count() AS event_count,
    avg(JSONExtractFloat(payload, 'composite_score')) AS avg_score,
    max(JSONExtractFloat(payload, 'composite_score')) AS max_score
FROM unified_events_ts
WHERE event_type = 'ProfileSynced'
GROUP BY hour, jurisdiction;
```

---

5. API Schema (Unified Query Layer)

Exposes both REST and GraphQL. The REST API matches the needs of the Compliance Dashboard.

```
── Query Endpoints ────────────────────────────────────────────────────
POST   /api/v0/events/search            → { events: UnifiedEvent[], total }
  Body: { types: ["AccessDenied"], subjects: [...], from: timestamp, to: timestamp }

GET    /api/v0/stats/timeseries         → [ { bucket, metrics... } ]
  Query: metric=compliant_ratio, bucket=1h, days=7

GET    /api/v0/alerts/active            → AmlAlert[]

POST   /api/v0/correlate/start          → { correlation_id }
  Body: { root_event_id, description }

GET    /api/v0/correlate/{id}           → EventCorrelation
```

WebSocket Stream (from API Gateway)

```
ws://api.gitdigital.com/events
→ Subscribe to real‑time unified events with optional filters (type, subject, etc.)
```

---

6. Stream Processing Pipelines

Status Materialisation Pipeline

```
Input topic: compliance.events  (ProfileSynced, AccessGranted, etc.)
Processor: reads events, updates:
  - compliance_profiles table (UPSERT by subject)
  - access_gate_cache (UPSERT by subject + program)
  - aml_alerts (if event_type = AmlRiskUpdated and new_score > thresholds)
Output: reliable, queryable operational state.
```

Alerting Engine

```
Input: raw unified events + current profile state
Rules:
  - Risk score crosses threshold → generate AML_ALERT
  - KYC expires in < 7 days → generate KYC_EXPIRY_WARNING
  - Blocked subject attempts action → generate ACCESS_VIOLATION
  - ZK proof nullifier used on unknown chain → generate ANOMALY
Dispatches: WebSocket to dashboard, email, webhook to integrated systems.
```

Cross‑Program Correlation

```
Example: Sanctions Hit Lifecycle
  1. AML Risk Engine detects sanctions match → AmlAlert created.
  2. Compliance Officer creates a case via Dashboard → CaseCreated event.
  3. Officer marks SAR filed → SarFiled event.
  The correlation_id links all three events under one lifecycle.
```

---

7. Client SDK

```typescript
// sdk/src/EventBusClient.ts
export class EventBusClient {
  private ws: WebSocket;
  
  subscribeToEvents(
    filters: EventFilters,
    callback: (event: UnifiedEvent) => void
  ): () => void {
    const params = new URLSearchParams({
      types: filters.types?.join(','),
      subjects: filters.subjects?.join(','),
    });
    const socket = new WebSocket(`wss://api.gitdigital.com/events?${params}`);
    socket.onmessage = (msg) => {
      const event = JSON.parse(msg.data);
      callback(event);
    };
    return () => socket.close();
  }

  async searchEvents(query: EventSearchQuery): Promise<UnifiedEvent[]> {
    const res = await fetch('/api/v0/events/search', {
      method: 'POST',
      body: JSON.stringify(query),
    });
    return res.json();
  }
}
```

---

8. Security Considerations

Threat Mitigation
Event injection / forgery Only events verified against Solana signatures or signed by the Geyser plugin (trusted source) are accepted. Client‑submitted events never bypass signature verification.
Data leakage over WebSocket WebSocket endpoint authenticated via JWT; role‑based filtering ensures only authorised fields are streamed (e.g., no raw PII).
DoS on event bus Redpanda with authentication and TLS; ingestion rate‑limited; consumer groups for scalable processing.
Storage poisoning Stream processors validate event schemas and reject malformed payloads before writing to databases.
Unauthorised access to analytics ClickHouse access restricted to backend services only; API layer enforces RBAC.

---

9. Compliance Considerations

Requirement Implementation
Immutable audit trail Redpanda log stored with configurable retention (e.g., 7 years); each event is a signed, timestamped record.
Right to erasure / correction Events are not deleted but can be superseded by a correction event with proper metadata; operational state can be updated via override workflows.
Data residency Redpanda and databases deployed in chosen jurisdictions; topic partitioning can isolate regions.
Evidence for regulatory reporting The full event correlation chain can be exported as a cryptographically verifiable report.

---

10. Integration Points

Module Integration
Compliance Supergraph Major producer of profile sync and access decision events.
AML Risk Engine Produces risk updates and sanctions matches.
Policy Engine Produces authorization outcome events.
ZK MetaProof Engine Produces proof verification events.
Cross‑Chain Bridge Produces attestation emission events.
Compliance Dashboard Primary consumer of real‑time event streams and historical queries.
AI / ML Agents Read from ClickHouse for training and anomaly detection.
External Monitoring Webhook / event streaming to external SIEMs or compliance platforms.

---

11. Deployment & Tech Stack

· Streaming: Redpanda (drop‑in Kafka replacement, single binary, easy ops).
· Stream Processors: TypeScript (Node.js) consumers using kafkajs, deployed as Docker containers, orchestrated with Kubernetes or systemd.
· Geyser Plugin: Rust, runs alongside Solana validator (or a dedicated RPC node).
· Databases: PostgreSQL 15+ with pg_partman for partitioning; ClickHouse for analytics.
· API Gateway: Node.js (Express) or Apollo GraphQL, authenticates via JWT.
· Monitoring: Prometheus + Grafana for pipeline health.

---

12. Documentation

Processor Error Codes (internal)

```typescript
enum ProcessorError {
  SCHEMA_VALIDATION_FAILED,
  DB_WRITE_FAILED,
  DEAD_LETTER,
  RATE_LIMITED,
}
```

Repository Structure

```
event-bus-indexer/
├── geyser-plugin/               # Solana geyser plugin (Rust)
├── redpanda/                    # Docker compose for local dev
├── processors/                  # Stream processing services
│   ├── profile-materializer/    # Updates PostgreSQL profiles
│   ├── alerting-engine/         # Real‑time rules engine
│   ├── analytics-ingest/        # Writes to ClickHouse
│   └── correlation-worker/      # Links related events
├── api/                         # Unified Query API
│   ├── src/
│   │   ├── routes/
│   │   ├── websocket/
│   │   └── app.ts
├── schemas/                     # Avro/JSON Schema definitions
├── sql/
│   ├── postgres/
│   └── clickhouse/
└── tests/
    └── integration/
```

---

Status: Event Bus + Indexer Supernode architecture complete.
Unifies all compliance events into a single stream, feeds operational and analytical stores, and powers real‑time dashboards and AI agents.
Ready for deployment alongside Redpanda and stream processor implementation.
