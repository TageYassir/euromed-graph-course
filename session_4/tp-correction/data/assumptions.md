# Data assumptions and dataset extension

All data is **synthetic**. Names are invented; any resemblance to real people or companies is accidental.
The CSV files in this folder are the human-readable source; `cypher/02_load_data.cypher` contains the same rows as inline `UNWIND` lists so the load runs on a fresh database without copying files into Neo4j's `import/` folder. Column `source` = `TP` (given by the assignment) or `EXT` (added by the team).

## 1. Transformations applied to the TP source tables

| Source | Transformation | Why |
|---|---|---|
| Home city / onsite cities (text) | Shared `City` nodes (`CITY-RABAT`, ...) linked by `LIVES_IN` and `AVAILABLE_ONSITE_IN` | Same city reused by candidates, jobs, organizations; avoids spelling drift |
| Remote available Yes/No | `Candidate.remoteAvailable` boolean; `null` = unknown | Single yes/no fact about the person, no extra attributes needed |
| Skill aliases (comma text) | One `Alias` node per normalised key (`toLower(trim(label))`), canonical label also registered | Exact-key lookup; uniqueness constraint prevents an alias pointing to 2 skills |
| Claims table | Reified `SkillClaim` node per (candidate, skill), id `CL-<cand>-<skill>` | Level, status, source and evidence links belong to the claim, not to the person or the skill |
| Verified / Unverified | `VERIFIED` / `UNVERIFIED` copied as given; new value `REFUTED` = verified false | Rule 10; TP note "verification is not proficiency" |
| Skills used (experience) | `USED_SKILL` edge from `WorkExperience` to `Skill`, plus a derived `EVIDENCED_BY {reviewStatus:'POTENTIAL'}` edge from the matching claim | Shows *where and when* a skill was used without upgrading verification |
| End date "—" | `endDate` absent (null) = ongoing | Open-ended periods; queries use `coalesce(endDate, $asOf)` |
| Mode / onsite city | `Job.workMode` ∈ {REMOTE, HYBRID, ONSITE}; `BASED_IN` city only for HYBRID/ONSITE | Applies the TP geography rule consistently |
| Mandatory? Yes/No | `REQUIRES_SKILL.priority` ∈ {MANDATORY, PREFERRED} + `minLevel` | Requirement facts belong to the job–skill pair |
| Application events | `Application` (one per candidate+job) with immutable `ApplicationEvent`s; `seq`, `attemptNo` and `NEXT` derived by timestamp | History preserved; Reapplied starts attempt 2 inside the same application case |

## 2. Assumptions on missing or ambiguous values

- **Unknown vs. unverified vs. false.** No `SkillClaim` = unknown (we assert nothing). `UNVERIFIED` = claim exists, check not completed. `REFUTED` = check completed and claim judged false. Missing `remoteAvailable` would be `null`, never `false`.
- **Verification is never derived.** An experience that used a skill is only *potential* evidence. C08's verified Cypher claim has no evidence link and is flagged by CQ-09 as a provenance gap; we do not delete or downgrade it.
- **Verification dates/assessors** are unknown in the TP data and stay null (see change request migration).
- **Employment type** (FULL_TIME, INTERNSHIP, CONTRACT, FREELANCE) for TP experiences was inferred from the role title ("ML Intern" → INTERNSHIP, "KG Consultant" → CONTRACT). It is descriptive only and no query result depends on it except CQ-17's display column.
- **"Last 2 years"** is computed against a parameter `$asOf` (default `2026-11-12`, the project date) so tests are reproducible; window = `[asOf − 2 years, asOf]`, period overlap semantics.
- **Application attempts.** One `Application` node per (candidate, job). `REAPPLIED` increments `attemptNo`; `WITHDRAWN` closes the current attempt. Recruiter actions (`REVIEWED`, `REJECTED`, `REINSTATED`) are events of the same application.
- **Closed jobs.** No closing date is given, so we do not invent one; validation V-06 checks that a closed job has no application events at all.
- **Duplicates.** Identity is the business ID only. Two people named "Amina Idrissi" (C01, C07) stay two nodes; a merge would require a human decision recorded as provenance (out of scope).

## 3. Dataset extension (team, `source = EXT`)

| Requirement (TP §6.8) | Minimum | Added |
|---|---|---|
| Candidates | 4 | 4 (C07–C10) |
| Organizations | 2 | 2 (O04, O05) |
| Jobs | 3 | 3 (J05–J07) |
| Skills | 5 | 5 (S10–S14) |
| Experiences | 5 | 5 (E07–E11) + 3 projects (P01–P03) |
| Skill claims | 8 | 16 |
| Application events | 6 | 9 (AEV07–AEV15) + 2 recruiters |

### Tricky cases included on purpose

| Category | Case | Where it is tested |
|---|---|---|
| Duplicate display names | C07 "Amina Idrissi" (Tangier) vs. C01 "Amina Idrissi" (Rabat) | A-10; IDs differ, all CQs key on `candidateId` |
| Alias that could be wrongly merged | `Spark` (Apache Spark, S10) vs. `SPARQL` (S11): substring/prefix search would confuse them. Also `JS` must reach JavaScript, never Java | A-7, V-05, CQ-10b; `DISTINCT_FROM` edges document the decision |
| Overlapping work experiences | C08: E08 full-time at O04 (2023-01 → 2025-06) overlaps E09 freelance at O05 (2024-03 → 2024-12) | CQ-17 |
| Unverified mandatory claim | C09 claims Apache Spark level 3 but UNVERIFIED; Spark is mandatory for J05 | A-8, CQ-12a (rejection explanation) |
| Reapplication / status reversal | C09/J05 Applied → Withdrawn → Reapplied; C10/J06 Applied → Rejected (R01) → Reinstated (R02) | A-9, CQ-08, CQ-16 |
| Extra: verified-false claim | C09 JavaScript `REFUTED` | CQ-09 |
| Extra: job nobody can fill | J07 needs SPARQL ≥2 and RDF ≥2; C07 has RDF only at level 1, C05 has no SPARQL | CQ-15 |
| Extra: "2 of 3" partial match | C08 meets Python and Cypher for J01 but has no Neo4j claim | CQ-03 |
