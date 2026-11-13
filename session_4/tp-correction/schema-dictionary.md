# Schema Dictionary (Phase C)

Diagram: `graph-model.svg` / `graph-model.png` (source `graph-model.mmd`). Dashed purple elements are added by the change request (`cypher/05_change_request.cypher`).

**Conventions:** IDs are opaque strings assigned by TalentBridge (or derived deterministically from other IDs); display names are never identity. Enumerations are `UPPER_SNAKE` strings. Dates are Neo4j `DATE`, event times `DATETIME` in UTC. `null` means *unknown / not applicable*, never *false*.

---

## 1. Node Labels

### At a Glance

```
(:Candidate) ──MAKES_CLAIM──▶ (:SkillClaim) ──ABOUT_SKILL──▶ (:Skill) ──IN_CATEGORY──▶ (:SkillCategory)
     │                              │                              │
     │                        EVIDENCED_BY                   ALIAS_OF
     │                              ▼                              │
     ├──HAS_EXPERIENCE──▶ (:WorkExperience) ──AT_ORGANIZATION──▶ (:Organization) ──LOCATED_IN──▶ (:City)
     │                         │   │                                    │
     │                     PART_OF USED_SKILL                    PUBLISHED_BY
     │                         ▼                                        ▼
     ├──WORKED_ON──────▶ (:Project) ──USED_SKILL──▶ (:Skill)     (:Job) ──BASED_IN──▶ (:City)
     │
     ├──LIVES_IN / AVAILABLE_ONSITE_IN──▶ (:City)
     │
     └──SUBMITTED──▶ (:Application) ──FOR_JOB──▶ (:Job)
                           │
                       HAS_EVENT
                           ▼
                   (:ApplicationEvent) ──NEXT──▶ (:ApplicationEvent)
                           │
                    PERFORMED_BY
                           ▼
                      (:Recruiter) ──WORKS_FOR──▶ (:Organization)
```

---

### 1.1 `Candidate`

A person who has created a profile on TalentBridge and may apply for jobs.

| Property | Type | Required | Rule | Example |
|---|---|---|---|---|
| `candidateId` | STRING | ✅ | `C\d{2,}` | `"C01"` |
| `name` | STRING | ✅ | free text, indexed | `"Amina Idrissi"` |
| `remoteAvailable` | BOOLEAN | ❌ | `true`/`false`/`null` = unknown | `true` |
| `source` | STRING | ✅ | `TP` (platform) or `EXT` (imported) | `"TP"` |

**`remoteAvailable` meaning:**

| Value | Meaning |
|---|---|
| `true` | Candidate explicitly accepts remote work |
| `false` | Candidate prefers in-person only |
| `null` | Not stated — treated conservatively as unavailable for remote-only jobs |

> ⚠️ **`null` ≠ `false`** — the platform distinguishes "did not answer" from "refused". In CQ-07, only `remoteAvailable = true` qualifies for the remote-only talent pool.

**Example node:**
```cypher
MERGE (:Candidate {
  candidateId:     "C01",
  name:            "Amina Idrissi",
  remoteAvailable: true,
  source:          "TP"
})
```

**Example query — fetch a candidate's profile summary:**
```cypher
MATCH (c:Candidate {candidateId: "C01"})
OPTIONAL MATCH (c)-[:LIVES_IN]->(city:City)
RETURN c.name, c.remoteAvailable, city.name AS homeCity
```

---

### 1.2 `SkillClaim`

A single candidate's **self-declared** statement about one specific skill. It separates the *claim* (what the candidate says) from the *verification* (what the platform has confirmed).

| Property | Type | Required | Rule | Example |
|---|---|---|---|---|
| `claimId` | STRING | ✅ | `CL-<candidateId>-<skillId>` | `"CL-C01-S01"` |
| `level` | INTEGER | ✅ | `1` beginner · `2` intermediate · `3` advanced | `3` |
| `verificationStatus` | STRING | ✅ | `VERIFIED`, `UNVERIFIED`, `REFUTED` | `"VERIFIED"` |
| `source` | STRING | ✅ | name of the source sheet / intake form | `"cv_upload_2025"` |

**`verificationStatus` lifecycle:**

```
 UNVERIFIED  ──(evidence accepted)──▶  VERIFIED
      │
      └─────(evidence refuted)────▶  REFUTED
```

> A claim starts `UNVERIFIED`. Evidence linked by `EVIDENCED_BY` is **never** enough alone to flip the status — a human or assessment process must explicitly verify it (BR-10). This prevents automatic promotion without oversight.

**Why a separate node instead of a property on Candidate?**

A candidate may have *N* skills, each at a different level, with different verification statuses, and with different sets of evidence. A property on `Candidate` (e.g. `skills: ["Python:3", "Docker:1"]`) cannot carry that richness and cannot be traversed, indexed, or linked individually.

**Example — one candidate's claims:**
```cypher
MATCH (c:Candidate {candidateId: "C01"})-[:MAKES_CLAIM]->(cl:SkillClaim)-[:ABOUT_SKILL]->(s:Skill)
RETURN s.name AS skill, cl.level AS declaredLevel, cl.verificationStatus AS status
ORDER BY cl.level DESC
```
| skill | declaredLevel | status |
|---|---|---|
| Python | 3 | VERIFIED |
| Neo4j | 2 | VERIFIED |
| Docker | 1 | UNVERIFIED |
| Spark | 2 | REFUTED |

---

### 1.3 `Skill`

The **canonical, deduplicated** representation of a competency. There is exactly one `Skill` node per competency, no matter how many different spellings or aliases exist for it.

| Property | Type | Required | Rule | Example |
|---|---|---|---|---|
| `skillId` | STRING | ✅ | `S\d{2,}` | `"S01"` |
| `name` | STRING | ✅ | canonical label; unique case-insensitively (V-01) | `"Python"` |

> `name` is the **display** label. Identity is always `skillId`. Two skills cannot have the same case-insensitive name (checked by V-01), because `"python"` and `"Python"` would otherwise silently split the graph.

**Why a shared node matters (BR-1, D-2):**

Without a canonical node, a job posting for `"Python"` and a candidate claim for `"python3"` would never match. The `Alias` layer (§1.4) resolves spellings; the `Skill` node is the single point they all resolve to.

```
"Python"  ──ALIAS_OF──▶
"python3" ──ALIAS_OF──▶  (:Skill {skillId:"S01", name:"Python"})
"py"      ──ALIAS_OF──▶
```

**Example — find all aliases for a skill:**
```cypher
MATCH (a:Alias)-[:ALIAS_OF]->(s:Skill {name: "Python"})
RETURN a.label AS alias, a.key AS normalisedKey
```

---

### 1.4 `Alias`

A surface form (spelling variation, abbreviation, typo) of a skill name. The normalisation pipeline looks up every incoming string against `Alias.key` before touching the graph.

| Property | Type | Required | Rule | Example |
|---|---|---|---|---|
| `key` | STRING | ✅ | `toLower(trim(label))` — **unique** | `"ml"` |
| `label` | STRING | ✅ | first spelling seen (display only) | `"ML"` |

**Normalisation rule:** `key = toLower(trim(rawInput))`

| Raw input | `key` | Resolves to |
|---|---|---|
| `"Python"` | `"python"` | `Skill S01` |
| `"python3"` | `"python3"` | `Skill S01` |
| `"ML"` | `"ml"` | `Skill S05` (Machine Learning) |
| `"Java"` | `"java"` | `Skill S07` |
| `"JavaScript"` | `"javascript"` | `Skill S08` (different skill — not an alias of Java) |

> `alias_key_unique` constraint enforces BR-7: a normalised string can resolve to **at most one** canonical skill. A conflict (same spelling, two different skills) must go to the curation queue.

**Example — resolve an incoming string to a canonical skill:**
```cypher
MATCH (a:Alias {key: toLower(trim("ML"))})-[:ALIAS_OF]->(s:Skill)
RETURN s.skillId, s.name
// → S05, "Machine Learning"
```

---

### 1.5 `SkillCategory`

A family or domain grouping of skills (e.g. *Graph Databases*, *Programming Languages*, *Cloud Platforms*).

| Property | Type | Required | Rule | Example |
|---|---|---|---|---|
| `categoryId` | STRING | ✅ | `CAT-<NAME>` | `"CAT-GRAPH_DB"` |
| `name` | STRING | ✅ | display label | `"Graph Databases"` |

**Example — find all skills in a category:**
```cypher
MATCH (s:Skill)-[:IN_CATEGORY]->(cat:SkillCategory {name: "Graph Databases"})
RETURN s.name
// → "Neo4j", "ArangoDB", "Amazon Neptune", ...
```

**Used in CQ-13** (find candidates with project experience across two different categories — the "graph practitioner" query):
```cypher
MATCH (c:Candidate)-[:WORKED_ON]->(p:Project)-[:USED_SKILL]->(s:Skill)-[:IN_CATEGORY]->(cat)
WITH c, collect(DISTINCT cat.name) AS cats
WHERE size(cats) >= 2
RETURN c.name, cats
```

---

### 1.6 `Organization`

An employer or company that publishes jobs and employs candidates.

| Property | Type | Required | Rule | Example |
|---|---|---|---|---|
| `orgId` | STRING | ✅ | `O\d{2,}` | `"O01"` |
| `name` | STRING | ✅ | display name | `"DataFlow Inc."` |

> An `Organization` node is shared: the same company node is referenced by multiple `WorkExperience` nodes (candidates who worked there) and multiple `Job` nodes (jobs it published). This is the property-or-node decision in action — if `employer` were a string property on `WorkExperience`, you could never find "all jobs at DataFlow" or "all candidates who worked at DataFlow" without a string scan.

**Example:**
```cypher
// All candidates who have worked at a given organization
MATCH (c:Candidate)-[:HAS_EXPERIENCE]->(e:WorkExperience)-[:AT_ORGANIZATION]->(o:Organization {name: "DataFlow Inc."})
RETURN DISTINCT c.name
```

---

### 1.7 `City`

A shared geographic reference node. Used for candidate home location, onsite availability, organization location, and job location.

| Property | Type | Required | Rule | Example |
|---|---|---|---|---|
| `cityId` | STRING | ✅ | `CITY-<NAME>` | `"CITY-PARIS"` |
| `name` | STRING | ✅ | display name | `"Paris"` |
| `countryCode` | STRING | ✅ | ISO-3166 alpha-2 | `"FR"` |

> `City` is a **reference node** (like `Skill` and `SkillCategory`): it is shared across the graph so that location-based queries can traverse to it from any direction. If `city` were a string property on `Job`, the query "find all candidates available in the same city as job J01" would require string matching instead of a graph traversal.

**Example — location-aware job search:**
```cypher
MATCH (j:Job {jobId: "J01"})-[:BASED_IN]->(city:City)
MATCH (c:Candidate)-[:AVAILABLE_ONSITE_IN]->(city)
RETURN c.name, city.name
```

---

### 1.8 `WorkExperience`

One **employment period** at one organization. A candidate may have multiple, possibly overlapping, work experiences (e.g. a freelance contract alongside a full-time role — BR-5).

| Property | Type | Required | Rule | Example |
|---|---|---|---|---|
| `experienceId` | STRING | ✅ | `E\d{2,}` | `"E01"` |
| `roleTitle` | STRING | ✅ | free text | `"Senior Data Engineer"` |
| `employmentType` | STRING | ✅ | `FULL_TIME`, `INTERNSHIP`, `CONTRACT`, `FREELANCE` | `"FULL_TIME"` |
| `startDate` | DATE | ✅ | | `2022-03-01` |
| `endDate` | DATE | ❌ | `null` = ongoing; must be ≥ startDate (V-07) | `null` |

> `endDate = null` means the candidate **currently works** in this role. CQ-11 uses this to find recent experience: "does this period overlap the last 2 years?"

**Why a node, not a relationship property?**

A relationship like `(Candidate)-[:WORKED_AT {role, start, end}]->(Organization)` cannot be linked to by `SkillClaim` evidence or connected to `Project` nodes. Once a fact needs its own connections, it becomes a node (the hub-node refactoring pattern).

**Example — candidate's work history:**
```cypher
MATCH (c:Candidate {candidateId: "C08"})-[:HAS_EXPERIENCE]->(e:WorkExperience)-[:AT_ORGANIZATION]->(o)
RETURN e.roleTitle, e.employmentType,
       toString(e.startDate) AS start,
       coalesce(toString(e.endDate), "ongoing") AS end,
       o.name AS company
ORDER BY e.startDate DESC
```

---

### 1.9 `Project`

A specific work item or deliverable inside a `WorkExperience`. Used to provide finer-grained skill evidence than the entire employment period.

| Property | Type | Required | Rule | Example |
|---|---|---|---|---|
| `projectId` | STRING | ✅ | `P\d{2,}` | `"P01"` |
| `name` | STRING | ✅ | | `"Graph migration pipeline"` |
| `startDate` | DATE | ✅ | | `2023-01-15` |
| `endDate` | DATE | ✅ | null = ongoing | `2023-06-30` |

> A `Project` is always `PART_OF` a `WorkExperience` — it cannot exist independently. It adds specificity: "I used Neo4j **on this project** during that job", not just "I used Neo4j at that company."

**Example:**
```cypher
MATCH (c:Candidate {candidateId: "C01"})-[:WORKED_ON]->(p:Project)-[:USED_SKILL]->(s:Skill)
MATCH (p)-[:PART_OF]->(e:WorkExperience)-[:AT_ORGANIZATION]->(o)
RETURN p.name AS project, s.name AS skill, o.name AS company,
       toString(p.startDate) AS start, toString(p.endDate) AS end
```

---

### 1.10 `Job`

A job posting published by an organization.

| Property | Type | Required | Rule | Example |
|---|---|---|---|---|
| `jobId` | STRING | ✅ | `J\d{2,}` | `"J01"` |
| `title` | STRING | ✅ | free text | `"Graph Data Engineer"` |
| `workMode` | STRING | ✅ | `REMOTE`, `HYBRID`, `ONSITE` | `"HYBRID"` |
| `status` | STRING | ✅ | `OPEN`, `CLOSED` (indexed) | `"OPEN"` |

**`workMode` and location logic (V-11, BR-8):**

| `workMode` | `BASED_IN` city | Location rule for SUITABLE |
|---|---|---|
| `REMOTE` | absent (null) | Candidate must have `remoteAvailable = true` |
| `HYBRID` | required | Candidate must have `AVAILABLE_ONSITE_IN` that city |
| `ONSITE` | required | Candidate must have `AVAILABLE_ONSITE_IN` that city |

**Example — open jobs requiring Python:**
```cypher
MATCH (j:Job {status: "OPEN"})-[r:REQUIRES_SKILL]->(s:Skill {name: "Python"})
RETURN j.title, j.workMode, r.priority, r.minLevel
```

---

### 1.11 `Recruiter`

A TalentBridge user (or employer representative) who acts on applications — reviews, shortlists, or rejects candidates.

| Property | Type | Required | Rule | Example |
|---|---|---|---|---|
| `recruiterId` | STRING | ✅ | `R\d{2,}` | `"R01"` |
| `name` | STRING | ✅ | | `"Sophie Martin"` |

> A `Recruiter` node can also carry the `:Assessor` label (v2 change request), making them multi-labelled: `(:Recruiter:Assessor)`. This is the specific-label pattern — a recruiter who assesses claims is both a recruiter and an assessor.

---

### 1.12 `Application`

One candidate's case for one specific job. There is exactly **one `Application` node per (candidate, job) pair** — the `applicationId` is derived as `APP-<candidateId>-<jobId>`.

| Property | Type | Required | Rule | Example |
|---|---|---|---|---|
| `applicationId` | STRING | ✅ | `APP-<candidateId>-<jobId>` | `"APP-C01-J01"` |

> The application **itself** has no status property. Its current state is always derived from the **last `ApplicationEvent`** in its history chain. This is the append-only event-sourcing pattern (§5).

**Why a node and not a direct relationship?**

`(Candidate)-[:APPLIED_TO {status}]->(Job)` cannot carry a history of events. Once a candidate can apply, withdraw, and reapply (BR-9), the connection needs its own identity — a hub node.

---

### 1.13 `ApplicationEvent`

An **immutable fact** in the history of an application. Events are never updated or deleted — the current state is always the last event in the chain.

| Property | Type | Required | Rule | Example |
|---|---|---|---|---|
| `eventId` | STRING | ✅ | `AEV\d{2,}` | `"AEV01"` |
| `type` | STRING | ✅ | `APPLIED`, `WITHDRAWN`, `REAPPLIED`, `REVIEWED`, `REJECTED`, `REINSTATED` | `"APPLIED"` |
| `at` | DATETIME | ✅ | UTC; indexed | `2026-01-15T09:30:00Z` |
| `seq` | INTEGER | derived | chronological position (1, 2, 3, …) | `1` |
| `attemptNo` | INTEGER | derived | how many times the candidate has applied | `1` |
| `decision` | STRING | ❌ | `SHORTLIST`, `REJECT`, `REINSTATE` | `"SHORTLIST"` |
| `note` | STRING | ❌ | free text by recruiter | `"Strong Neo4j experience"` |

**Full lifecycle example:**

```
AEV01: type=APPLIED,    at=2026-01-15, seq=1, attemptNo=1
  ──NEXT──▶
AEV02: type=WITHDRAWN,  at=2026-02-01, seq=2, attemptNo=1
  ──NEXT──▶
AEV03: type=REAPPLIED,  at=2026-03-10, seq=3, attemptNo=2
  ──NEXT──▶
AEV04: type=REVIEWED,   at=2026-03-12, seq=4, attemptNo=2, decision=SHORTLIST
```

**Example — find the current status of an application:**
```cypher
MATCH (c:Candidate {candidateId: "C01"})-[:SUBMITTED]->(app:Application)-[:FOR_JOB]->(j:Job {jobId: "J01"})
MATCH (app)-[:HAS_EVENT]->(ev:ApplicationEvent)
WHERE NOT (ev)-[:NEXT]->()          // last event = no outgoing NEXT
RETURN ev.type AS currentStatus, ev.at AS since
```

---

### 1.14 `SkillAssessment` *(v2 — change request)*

A **dated, external judgement** of a skill claim — as opposed to the candidate's own self-declaration. Added by the change request to distinguish platform-assessed proficiency from raw claims.

| Property | Type | Required | Rule | Example |
|---|---|---|---|---|
| `assessmentId` | STRING | ✅ | | `"ASM-C01-S01-01"` |
| `level` | INTEGER | ❌ | `1..3`; `null` if REFUTED | `3` |
| `assessedAt` | DATE | ❌ | null = unknown (migrated from v1) | `2025-11-01` |
| `method` | STRING | ✅ | e.g. `"CODING_TEST"`, `"INTERVIEW"` | `"CODING_TEST"` |
| `outcome` | STRING | ✅ | e.g. `"PASS"`, `"FAIL"` | `"PASS"` |
| `origin` | STRING | ✅ | `ASSESSMENT_V2` or `MIGRATED_FROM_V1_CLAIM` | `"ASSESSMENT_V2"` |

> `origin = MIGRATED_FROM_V1_CLAIM` marks assessments that were back-filled from existing v1 claims during the schema migration. These should be treated as lower-confidence than a fresh `ASSESSMENT_V2` result.

---

### 1.15 `Assessor` *(v2 — change request)*

A person or panel who performed a `SkillAssessment`. Can be multi-labelled with `:Recruiter` if the assessor is already in the system.

| Property | Type | Required | Rule | Example |
|---|---|---|---|---|
| `assessorId` | STRING | ✅ | | `"R01"` (when also a Recruiter) |
| `name` | STRING | ✅ | | `"Sophie Martin"` |

---

## 2. Relationship Types

### 2.1 Core Skill Graph

---

#### `MAKES_CLAIM` — `(Candidate)→(SkillClaim)`

**Cardinality:** 1 : N (one candidate, many claims; each claim belongs to exactly one candidate)

**What it means:** The candidate has declared a proficiency in a skill. The claim is theirs — its validity is a separate question.

```cypher
// How many claims does each candidate have?
MATCH (c:Candidate)-[:MAKES_CLAIM]->(cl:SkillClaim)
RETURN c.name, count(cl) AS totalClaims
```

---

#### `ABOUT_SKILL` — `(SkillClaim)→(Skill)`

**Cardinality:** N : 1 (many claims can be about the same canonical skill; each claim is about exactly one skill)

**What it means:** Connects a claim to the canonical skill it concerns. This is what makes "find all candidates who claim Python" work — you query the canonical `Skill` node, not free text.

```cypher
// All VERIFIED claimants for a given skill
MATCH (cl:SkillClaim {verificationStatus: "VERIFIED"})-[:ABOUT_SKILL]->(s:Skill {name: "Python"})
MATCH (c:Candidate)-[:MAKES_CLAIM]->(cl)
RETURN c.name, cl.level
```

---

#### `EVIDENCED_BY` — `(SkillClaim)→(WorkExperience | Project)`

**Cardinality:** N : M

**Properties:**

| Property | Type | Values | Meaning |
|---|---|---|---|
| `evidenceType` | STRING | `DIRECT`, `DERIVED` | Was this link set manually or auto-derived? |
| `reviewStatus` | STRING | `POTENTIAL`, `ACCEPTED`, `REJECTED` | Has a human reviewed this evidence link? |
| `derivedBy` | STRING | rule name | If auto-derived, which rule created it |

**What it means:** A piece of work experience or a project that might support a claim. Critically:

> ⚠️ `EVIDENCED_BY` links **never automatically change** `verificationStatus`. A claim with 10 `ACCEPTED` evidence links is still `UNVERIFIED` until a platform process explicitly verifies it (BR-10). This prevents gaming the system.

**Example — find claims with no supporting evidence at all (CQ-09):**
```cypher
MATCH (c:Candidate)-[:MAKES_CLAIM]->(cl:SkillClaim)
WHERE cl.verificationStatus <> "VERIFIED"
  AND NOT (cl)-[:EVIDENCED_BY]->()
MATCH (cl)-[:ABOUT_SKILL]->(s:Skill)
RETURN c.name, s.name AS skill, cl.verificationStatus
```

---

#### `ALIAS_OF` — `(Alias)→(Skill)`

**Cardinality:** N : 1

**What it means:** A spelling or abbreviation maps to exactly one canonical skill. The uniqueness constraint on `Alias.key` ensures no alias resolves to two different skills (BR-7).

**Why `Java` and `JavaScript` must not alias each other:**
```
(:Alias {key:"java"})       ──ALIAS_OF──▶ (:Skill {name:"Java"})
(:Alias {key:"javascript"}) ──ALIAS_OF──▶ (:Skill {name:"JavaScript"})
```
These are two separate `Alias` nodes with two separate targets. A recruiter searching for "Java" will not accidentally find JavaScript developers.

---

#### `IN_CATEGORY` — `(Skill)→(SkillCategory)`

**Cardinality:** N : 1

**What it means:** A skill belongs to a family. Used in CQ-13 to find "graph practitioners" — candidates with project experience across at least two skill categories.

```cypher
MATCH (s:Skill)-[:IN_CATEGORY]->(cat:SkillCategory)
RETURN cat.name AS category, collect(s.name) AS skills
```

---

#### `DISTINCT_FROM` — `(Skill)→(Skill)`

**Cardinality:** N : M

**Properties:** `reason` (STRING) — why these were explicitly marked as distinct

**What it means:** A curated guard against accidental merging of two skills that look similar. Added by a human after a curation review.

```cypher
// Example: Java and JavaScript are explicitly NOT the same skill
MERGE (s1:Skill {skillId: "S07"}) // Java
MERGE (s2:Skill {skillId: "S08"}) // JavaScript
MERGE (s1)-[:DISTINCT_FROM {reason: "different language family, common confusion"}]->(s2)
```

---

### 2.2 Work History Graph

---

#### `HAS_EXPERIENCE` — `(Candidate)→(WorkExperience)`

**Cardinality:** 1 : N

**What it means:** A candidate's employment record. Multiple overlapping experiences are allowed (BR-5 — e.g., a freelance contract alongside a full-time job).

---

#### `AT_ORGANIZATION` — `(WorkExperience)→(Organization)`

**Cardinality:** N : 1

**What it means:** The experience took place at this company. The same `Organization` node is shared by all candidates who worked there — enabling "find all candidates who worked at DataFlow Inc." without string matching.

---

#### `USED_SKILL` — `(WorkExperience | Project)→(Skill)`

**Cardinality:** N : M

**What it means:** A skill was actively used during this period or project. This is the **usage** link — separate from the **claim** link. A candidate might have used Python in a project without having a formal `SkillClaim` for Python (though that would be unusual).

> Usage ≠ Proficiency. `USED_SKILL` records what happened; `SkillClaim.level` records how good the candidate says they are.

**Example — CQ-11: candidates who used Python in the last 2 years:**
```cypher
WITH date($asOf) AS asOf
MATCH (c:Candidate)-[:HAS_EXPERIENCE|WORKED_ON]->(x)-[:USED_SKILL]->(s:Skill)
MATCH (a:Alias {key: toLower(trim($skillTerm))})-[:ALIAS_OF]->(s)
WHERE x.startDate <= asOf
  AND (x.endDate IS NULL OR x.endDate >= asOf - duration({years: 2}))
RETURN DISTINCT c.name
```

---

#### `PART_OF` — `(Project)→(WorkExperience)`

**Cardinality:** N : 1

**What it means:** A project is always contained within an employment period. A project cannot exist without a parent work experience.

---

#### `WORKED_ON` — `(Candidate)→(Project)`

**Cardinality:** N : M

**What it means:** A shortcut from candidate to project, derived from `HAS_EXPERIENCE → PART_OF`. Stored directly so project-level queries do not have to traverse through `WorkExperience` every time.

---

### 2.3 Location Graph

---

#### `LIVES_IN` — `(Candidate)→(City)`

**Cardinality:** N : 1 (a candidate has one home city)

---

#### `AVAILABLE_ONSITE_IN` — `(Candidate)→(City)`

**Cardinality:** N : M (a candidate may be available in multiple cities for onsite work)

**Example — used in the SUITABLE location rule (V-11):**
```cypher
// For a HYBRID job in Paris, is candidate C01 available?
MATCH (j:Job {jobId: "J01"})-[:BASED_IN]->(city:City)
MATCH (c:Candidate {candidateId: "C01"})
RETURN exists((c)-[:AVAILABLE_ONSITE_IN]->(city)) AS onsiteAvailable
```

---

#### `LOCATED_IN` — `(Organization)→(City)`

**Cardinality:** N : 1

---

### 2.4 Job Graph

---

#### `PUBLISHED_BY` — `(Job)→(Organization)`

**Cardinality:** N : 1

---

#### `BASED_IN` — `(Job)→(City)`

**Cardinality:** N : 0..1

> Only `HYBRID` and `ONSITE` jobs have a `BASED_IN` city. `REMOTE` jobs have none. This is enforced by V-11.

---

#### `REQUIRES_SKILL` — `(Job)→(Skill)`

**Cardinality:** N : M, ≤ 1 per (Job, Skill) pair (V-03)

**Properties:**

| Property | Type | Values | Meaning |
|---|---|---|---|
| `priority` | STRING | `MANDATORY`, `PREFERRED` | Hard requirement vs. nice-to-have |
| `minLevel` | INTEGER | `1..3` | Minimum declared level required |

> ⚠️ `PREFERRED` requirements **never exclude** a candidate from being SUITABLE. They are surfaced in the match explanation (CQ-12) to aid ranking, but a candidate missing a preferred skill is still eligible.

**Example — the SUITABLE skill rule (CQ-02):**
```cypher
// For job J01, find candidates who meet ALL mandatory requirements
MATCH (j:Job {jobId: "J01"})-[req:REQUIRES_SKILL {priority: "MANDATORY"}]->(s:Skill)
WITH j, collect({skill: s, minLevel: req.minLevel}) AS requirements, count(s) AS totalMandatory

MATCH (c:Candidate)-[:MAKES_CLAIM]->(cl:SkillClaim {verificationStatus: "VERIFIED"})-[:ABOUT_SKILL]->(s)
WHERE cl.level >= requirements[0].minLevel   // simplified; real query checks each requirement
WITH c, count(DISTINCT s) AS metCount, totalMandatory
WHERE metCount = totalMandatory
RETURN c.name
```

---

### 2.5 Application Graph

---

#### `SUBMITTED` — `(Candidate)→(Application)`

**Cardinality:** 1 : N

---

#### `FOR_JOB` — `(Application)→(Job)`

**Cardinality:** N : 1

---

#### `HAS_EVENT` — `(Application)→(ApplicationEvent)`

**Cardinality:** 1 : N

---

#### `NEXT` — `(ApplicationEvent)→(ApplicationEvent)`

**Cardinality:** 0..1 : 0..1 (a linked list — each event points to the next one)

**What it means:** The chronological chain of events for one application. The **first event** has no incoming `NEXT`; the **last event** has no outgoing `NEXT`.

```
AEV01 ──NEXT──▶ AEV02 ──NEXT──▶ AEV03 ──NEXT──▶ AEV04
 APPLIED        WITHDRAWN        REAPPLIED        REVIEWED
```

---

#### `PERFORMED_BY` — `(ApplicationEvent)→(Recruiter)`

**Cardinality:** N : 0..1

> Only recruiter-initiated events (REVIEWED, REJECTED, REINSTATED) have a `PERFORMED_BY` link. Candidate-initiated events (APPLIED, WITHDRAWN, REAPPLIED) do not.

---

#### `WORKS_FOR` — `(Recruiter)→(Organization)`

**Cardinality:** N : 1

---

### 2.6 Assessment Graph *(v2 — change request)*

---

#### `ASSESSES` — `(SkillAssessment)→(SkillClaim)`

**Cardinality:** N : 1 — one assessment targets one claim; a claim may have multiple assessments over time.

---

#### `ASSESSED_BY` — `(SkillAssessment)→(Assessor)`

**Cardinality:** N : 0..1 — null = unknown assessor (migrated from v1).

---

#### `BASED_ON` — `(SkillAssessment)→(WorkExperience | Project)`

**Cardinality:** N : M — the evidence the assessor reviewed when making their judgement.

---

#### `DISPUTES` — `(Candidate)→(SkillAssessment)` *(dashed — change request)*

**Properties:**

| Property | Type | Meaning |
|---|---|---|
| `at` | DATETIME | When the dispute was raised |
| `reason` | STRING | Candidate's explanation |
| `status` | STRING | `OPEN` or `RESOLVED` |

**What it means:** A candidate can formally challenge an assessment they disagree with. The dispute is on the **relationship**, not a node, because a dispute belongs to the connection between a specific candidate and a specific assessment — it has no identity of its own.

---

## 3. Identity Strategy

### Deterministic IDs

| Node | ID pattern | Example | Derived from |
|---|---|---|---|
| Candidate | `C\d{2,}` | `C01` | TalentBridge system |
| Skill | `S\d{2,}` | `S01` | TalentBridge system |
| Job | `J\d{2,}` | `J01` | TalentBridge system |
| Organization | `O\d{2,}` | `O01` | TalentBridge system |
| City | `CITY-<NAME>` | `CITY-PARIS` | Derived from city name |
| SkillClaim | `CL-<candidateId>-<skillId>` | `CL-C01-S01` | Deterministic composite |
| Application | `APP-<candidateId>-<jobId>` | `APP-C02-J01` | Deterministic composite |
| Alias | `toLower(trim(label))` | `ml` | The alias text itself |

> **Why deterministic IDs matter:** Re-running the ingestion script uses `MERGE` on these IDs. Because the same input always produces the same ID, `MERGE` finds the existing node and updates it instead of creating a duplicate. This is the idempotency guarantee (validated by V-09: identical counts after two runs).

> **Never use `elementId()`** as a reference — Neo4j's internal element ID is not stable across exports, imports, or database restores.

---

## 4. Constraints and Indexes

| Name | Kind | What It Protects |
|---|---|---|
| `candidate_id_unique` … `recruiter_id_unique` | Uniqueness + backing index | Identity; every `MERGE` and `{id: $x}` lookup is an index seek, not a scan |
| `alias_key_unique` | Uniqueness | BR-7: one alias → one canonical skill |
| `claim_status_idx` | Range index | CQ-02/03/09/12/15 — filter on `verificationStatus` |
| `job_status_idx` | Range index | CQ-04/07/18/19 — start from `OPEN` jobs |
| `app_event_at_idx` | Range index | Event ordering, time-range history (CQ-08/16) |
| `experience_end_idx` | Range index | CQ-11 — recency window on `endDate` |
| `candidate_name_idx` | Range index | Recruiter name search (non-unique) |
| `requires_priority_idx` | Relationship index | Mandatory/preferred filters on `REQUIRES_SKILL` |

**Example — why the constraint on `alias_key_unique` is critical:**

```
Without the constraint:
  (:Alias {key: "ml"}) ──ALIAS_OF──▶ (:Skill {name: "Machine Learning"})
  (:Alias {key: "ml"}) ──ALIAS_OF──▶ (:Skill {name: "MLOps"})     ← duplicate key!

  Now "ml" resolves to two different skills — CQ-10 returns ambiguous results.

With the constraint:
  The second MERGE fails immediately with a ConstraintViolationException,
  forcing the issue to the curation queue before it corrupts the graph.
```

---

## 5. Time Strategy

| Fact | Stored As | Key Rule |
|---|---|---|
| Employment period | `WorkExperience.startDate` / `endDate` (DATE) | `endDate = null` means ongoing; overlap allowed (BR-5) |
| Project period | `Project.startDate` / `endDate` (DATE) | Same rules |
| Recency queries | parameter `$asOf` passed at query time | **Never** use `date()` inside queries — results must be reproducible in tests |
| Job status | `Job.status` string (current value only) | No history in v1; versioning path = `:JobStatusChange` events (same pattern as applications) |
| Application history | Immutable `ApplicationEvent.at` (DATETIME UTC) + `seq` + `NEXT` chain | Append-only; current state = last event |
| Proficiency history *(v2)* | `SkillAssessment.assessedAt` (DATE) | Append-only; "as of date D" = latest assessment where `assessedAt ≤ D` |

**Why `$asOf` instead of `date()`?**

```cypher
// ❌ BAD — non-reproducible; runs differently depending on when you run it
MATCH (e:WorkExperience)
WHERE e.endDate IS NULL OR e.endDate >= date() - duration({years: 2})
RETURN e

// ✅ GOOD — reproducible; test results are deterministic
MATCH (e:WorkExperience)
WHERE e.endDate IS NULL OR e.endDate >= date($asOf) - duration({years: 2})
RETURN e
```

---

## 6. Skill Normalisation, Evidence, and Provenance

### Normalisation Pipeline

```
Raw input string
      │
      ▼
 toLower(trim(input))  →  normalised key
      │
      ▼
 MATCH (:Alias {key: normalisedKey})-[:ALIAS_OF]->(s:Skill)
      │
      ├── Hit  → use canonical Skill node
      │
      └── Miss → send to curation queue (do NOT auto-create a Skill)
```

> Auto-creating a `Skill` on a cache miss would silently multiply canonical nodes for the same competency. A miss must go to a human curator who decides: is this a new skill, a typo, or an alias of an existing one?

### Evidence vs. Verification

```
SkillClaim.verificationStatus
      │
      ├── UNVERIFIED  ← default; claim exists but nothing confirmed it
      │
      ├── VERIFIED    ← explicitly set by a platform process (test, interview, assessment)
      │
      └── REFUTED     ← explicitly set; evidence contradicts the claim
            │
            ▼
    EVIDENCED_BY links connect a claim to work experience / projects
    that *might* support it — but they never flip verificationStatus.
    reviewStatus on the link tracks whether a human has reviewed each link.
```

### Provenance Tracking

Every imported or derived node/edge carries a `source` or `derivedBy` property so that data quality issues can be traced back to their origin:

| Property | Carried by | Example value | Meaning |
|---|---|---|---|
| `source = "TP"` | All Candidate, Job, Org nodes | `"TP"` | Loaded from TalentBridge native tables |
| `source = "EXT"` | Candidate, Job nodes | `"EXT"` | Imported from external system |
| `source = "cv_upload_2025"` | SkillClaim | sheet name | Which intake form the claim came from |
| `derivedBy = "same_candidate_same_skill"` | `EVIDENCED_BY` edges | rule name | Auto-derived by the ingestion rule |
| `origin = "MIGRATED_FROM_V1_CLAIM"` | SkillAssessment (v2) | | Back-filled from v1 data |
| `origin = "ASSESSMENT_V2"` | SkillAssessment (v2) | | Created by the new assessment process |
