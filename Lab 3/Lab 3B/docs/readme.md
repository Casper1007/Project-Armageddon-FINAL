<!-- Trigger CI/CD workflow: test commit -->
Lab 3 — Japan Medical
Cross-Region Architecture with Legal Data Residency (APPI Compliance)
Scenario Overview
  A Japanese medical organization operates:
  A primary medical data system in Tokyo
  A satellite medical office in São Paulo
    A single global application URL: chrisbarm-growls.com
  Global access via CloudFront
  Strict legal requirement:
    All Japanese patient medical data (PHI) must remain physically stored in Japan

This is not a theoretical exercise.
This is how regulated global healthcare systems are actually built.

Why This Lab Exists (Read This Carefully)
Japan’s privacy law — 個人情報保護法 (APPI) — requires that personally identifiable medical information for Japanese citizens must not be stored outside Japan, unless extremely specific legal mechanisms are in place.

For healthcare:
  The safe, standard interpretation is:
    Store PHI only inside Japan

Even if:
    The patient is traveling
    The doctor is overseas
    The application is globally accessible

📌 Access is allowed. Storage is not.
That single sentence is the key mental shift.

Legal Reality → Architectural Consequence

Because of APPI:
| Component             | Allowed Location                           |
| --------------------- | ------------------------------------------ |
| RDS (Medical Records) | **Tokyo only** (`ap-northeast-1`)          |
| Backups / snapshots   | **Tokyo only**                             |
| Read replicas         | ❌ Not allowed outside Japan                |
| App access            | ✅ Allowed globally                         |
| CloudFront            | ✅ Allowed (edge cache, no PHI persistence) |
| EC2 in São Paulo      | ✅ Allowed (stateless compute only)         |

This forces a hub-and-spoke architecture:
  Tokyo is the data authority
  Other regions are compute-only extensions

Regional Architecture Breakdown
🇯🇵 Tokyo — Primary Region (ap-northeast-1)
Tokyo hosts everything that touches patient data at rest:
    RDS (MySQL / PostgreSQL)
    Primary VPC
    Application tier (EC2 / ASG)
    Transit Gateway attachment
    Parameter Store & Secrets Manager (authoritative)
    Logging, auditing, backups

Tokyo is the single source of truth.
If Tokyo goes down:
    The system degrades
    But data residency is never violated

This is intentional.

🇧🇷 São Paulo — Satellite Region (sa-east-1)
São Paulo exists only to improve access latency for doctors and staff physically located there.
São Paulo contains:
    VPC
    EC2 + Auto Scaling Group
    No databases
    No local persistence of PHI
    No backups
    No replicas

Every read/write:
    Traverses the AWS backbone
    Goes directly to Tokyo RDS
    Is encrypted in transit
    Is logged and auditable
São Paulo is stateless compute.

Why Transit Gateway Is Used (Not VPC Peering)
At this scale and sensitivity:
    VPC peering becomes brittle
    Routing rules multiply
    Auditing cross-region flows becomes harder
Transit Gateway provides:
    Centralized routing
    Explicit control of allowed paths
    Clear inspection points
    Enterprise-grade segmentation
In regulated environments:
    Transit Gateway is preferred because it creates a visible, controllable data corridor.

That matters for audits.

Operational Note (TGW Peering Apply Order)
If the TGW peering attachment is pending acceptance, Terraform cannot create
the association/propagation/routes on the first apply. Use a two-phase apply:
  1) Apply Tokyo to create the peering request.
  2) Apply Sao Paulo to accept the peering.
  3) Re-run apply in both regions once the attachment is available.

CloudFront’s Role (Single URL, Multiple Regions)
    There is only one public URL: https://chrisbarm-growls.com

CloudFront:
    Terminates TLS
    Applies WAF
    Routes users to the nearest healthy region
    Never stores PHI
    Only caches:
        Static assets
        Non-sensitive responses
        Content explicitly marked cacheable

  CloudFront is legally safe because:
    It is not a data stor
    It does not persist medical records
    It respects cache control rules

Data Flow (End-to-End)

Let’s walk a real example.

Example: Japanese patient visiting São Paulo
    1. Patient visits clinic in São Paulo
    2. Doctor opens chrisbarm-growls.com
    3. CloudFront routes request to São Paulo EC2
    4. São Paulo EC2:
        Authenticates request
        Does not store PHI locally
        Opens encrypted connection to Tokyo RDS via Transit Gateway
    5. Data is read/written only in Tokyo
    6. Response is returned to São Paulo doctor

At no point:
    Is PHI stored outside Japan
    Is data replicated
    Is a local database created

This satisfies APPI compliance.

Why This Is the Correct Tradeoff
What Japan cares about
    Data sovereignty
    Auditability
    Legal certainty

What the business cares about
    Doctors can work where patients are
    Latency is reasonable
    Single global app
    No duplicated systems

This architecture:
    Accepts slightly higher latency
    In exchange for legal compliance and operational simplicity

That is the correct trade in healthcare.

What Would Be Illegal (And Why)

❌ RDS Read Replica in São Paulo
→ Data at rest outside Japan

❌ Aurora Global Database
→ Storage replication outside Japan

❌ Local cache of patient records on EC2 disk
→ Persistent PHI outside Japan

❌ CloudFront caching PHI
→ Edge persistence outside Japan

These are not “bad practices.”
They are compliance violations.

Why This Lab Matters for Your Career
  Most engineers:
    Learn “multi-region for availability”
    Learn “replicate everything everywhere”

Regulated reality is different.
This lab teaches you to:
    Translate law into architecture
    Design global systems with asymmetric constraints
    Explain why a slower design is the correct one
    Speak confidently to:
      Security
      Legal
      Compliance
      Auditors

If you can explain this architecture clearly, you are senior-level.

How to Talk About This in an Interview

    “I designed a multi-region medical application where all PHI remained in Japan to comply with APPI.
    CloudFront provided global access, São Paulo ran stateless compute only, and all reads/writes traversed a Transit Gateway to Tokyo RDS.
    The design intentionally traded some latency for legal certainty and auditability.”

That answer will stop the room.

One Sentence to Remember
  ---> Global access does not require global storage.

That sentence is the heart of modern regulated cloud architecture.
