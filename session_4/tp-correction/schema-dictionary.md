# Schema Dictionary (Phase C)

Diagram: `graph-model.svg` / `graph-model.png` (source `graph-model.mmd`). Dashed purple elements are added by the change request (`cypher/05_change_request.cypher`).

Conventions: IDs are opaque strings assigned by TalentBridge (or derived deterministically from other IDs); display names are never identity. Enumerations are UPPER_SNAKE strings. Dates are Neo4j `DATE`, event times `DATETIME` in UTC. `null` means *unknown / not applicable*, never *false*.

## 1. Node labels

| Label | Meaning | Property | Type | Req. | Allowed values / rule | Unique |
|---|---|---|---|---|---|---|
| Candidate | A person with a profile | candidateId | STRING | yes | `C\d{2,}` | **yes** (constraint) |
| | | name | STRING | yes | free text, indexed | no |
| | | remoteAvailable | BOOLEAN | no | true / false / null = unknown | |
| | | source | STRING | yes | TP / EXT (provenance of the row) | |
| SkillClaim | One candidate's statement about one skill | claimId | STRING | yes | `CL-<candidateId>-<skillId>` | **yes** |
| | | level | INTEGER | yes | 1 beginner, 2 intermediate, 3 advanced (declared) | |
| | | verificationStatus | STRING | yes | VERIFIED, UNVERIFIED, REFUTED (indexed) | |
| | | source | STRING | yes | where the claim came from | |
| Skill | Canonical competency | skillId | STRING | yes | `S\d{2,}` | **yes** |
| | | name | STRING | yes | canonical label; unique case-insensitively (V-01) | |
| SkillCategory | Family of skills | categoryId, name | STRING | yes | `CAT-<NAME>` | **yes** |
| Alias | Surface form of a skill name | key | STRING | yes | `toLower(trim(label))` | **yes** |
| | | label | STRING | yes | first spelling seen | |
| Organization | Employer / job publisher | orgId, name | STRING | yes | `O\d{2,}` | **yes** |
| City | Shared location | cityId, name, countryCode | STRING | yes | `CITY-<NAME>`, ISO-3166 alpha-2 | **yes** |
| WorkExperience | One employment period | experienceId | STRING | yes | `E\d{2,}` | **yes** |
| | | roleTitle | STRING | yes | free text | |
| | | employmentType | STRING | yes | FULL_TIME, INTERNSHIP, CONTRACT, FREELANCE | |
| | | startDate | DATE | yes | | |
| | | endDate | DATE | no | null = ongoing; ≥ startDate (V-07); indexed | |
| Project | Work item inside an experience | projectId, name, startDate, endDate | STRING/DATE | yes | `P\d{2,}` | **yes** |
| Job | A job posting | jobId | STRING | yes | `J\d{2,}` | **yes** |
| | | title | STRING | yes | free text | |
| | | workMode | STRING | yes | REMOTE, HYBRID, ONSITE (V-11) | |
| | | status | STRING | yes | OPEN, CLOSED (indexed) | |
| Recruiter | TalentBridge/employer user acting on applications | recruiterId, name | STRING | yes | `R\d{2,}` | **yes** |
| Application | One candidate's case for one job | applicationId | STRING | yes | `APP-<candidateId>-<jobId>` | **yes** |
| ApplicationEvent | Immutable fact in an application history | eventId | STRING | yes | `AEV\d{2,}` | **yes** |
| | | type | STRING | yes | APPLIED, WITHDRAWN, REAPPLIED, REVIEWED, REJECTED, REINSTATED | |
| | | at | DATETIME | yes | UTC; indexed | |
| | | seq, attemptNo | INTEGER | derived | rebuilt by the loader from `at` order | |
| | | decision, note | STRING | no | SHORTLIST, REJECT, REINSTATE / free text | |
| SkillAssessment (v2) | A dated judgement of a claim | assessmentId | STRING | yes | | **yes** |
| | | level | INTEGER | no | 1..3; null if REFUTED | |
| | | assessedAt | DATE | no | null = unknown (migrated) | indexed |
| | | method, outcome, origin | STRING | yes | origin: ASSESSMENT_V2 / MIGRATED_FROM_V1_CLAIM | |
| Assessor (v2) | Person/panel who assesses | assessorId, name | STRING | yes | may be multi-labelled `:Recruiter:Assessor` | **yes** |

## 2. Relationship types

| Type | From → To | Card. | Properties | Meaning |
|---|---|---|---|---|
| MAKES_CLAIM | Candidate → SkillClaim | 1 : N | — | the candidate states the claim |
| ABOUT_SKILL | SkillClaim → Skill | N : 1 | — | the claim's canonical skill |
| EVIDENCED_BY | SkillClaim → WorkExperience \| Project | N : M | evidenceType, reviewStatus (POTENTIAL, ACCEPTED, REJECTED), derivedBy | potential proof of a claim; never sets verification |
| ALIAS_OF | Alias → Skill | N : 1 | — | resolves a spelling |
| IN_CATEGORY | Skill → SkillCategory | N : 1 | — | |
| DISTINCT_FROM | Skill → Skill | N : M | reason | curated do-not-merge |
| HAS_EXPERIENCE | Candidate → WorkExperience | 1 : N | — | |
| AT_ORGANIZATION | WorkExperience → Organization | N : 1 | — | |
| USED_SKILL | WorkExperience \| Project → Skill | N : M | — | skill used during that period |
| PART_OF | Project → WorkExperience | N : 1 | — | |
| WORKED_ON | Candidate → Project | N : M | — | |
| LIVES_IN | Candidate → City | N : 1 | — | home city |
| AVAILABLE_ONSITE_IN | Candidate → City | N : M | — | onsite availability |
| LOCATED_IN | Organization → City | N : 1 | — | |
| PUBLISHED_BY | Job → Organization | N : 1 | — | |
| BASED_IN | Job → City | N : 0..1 | — | only HYBRID/ONSITE (V-11) |
| REQUIRES_SKILL | Job → Skill | N : M, ≤1 per pair (V-03) | priority (MANDATORY, PREFERRED), minLevel 1..3 | requirement |
| SUBMITTED | Candidate → Application | 1 : N | — | |
| FOR_JOB | Application → Job | N : 1 | — | |
| HAS_EVENT | Application → ApplicationEvent | 1 : N | — | |
| NEXT | ApplicationEvent → ApplicationEvent | 0..1 : 0..1 | — | derived chronological chain |
| PERFORMED_BY | ApplicationEvent → Recruiter | N : 0..1 | — | actor for recruiter events |
| WORKS_FOR | Recruiter → Organization | N : 1 | — | |
| ASSESSES (v2) | SkillAssessment → SkillClaim | N : 1 | — | |
| ASSESSED_BY (v2) | SkillAssessment → Assessor | N : 0..1 | — | missing = unknown assessor |
| BASED_ON (v2) | SkillAssessment → WorkExperience \| Project | N : M | — | evidence used by the assessor |
| DISPUTES (v2) | Candidate → SkillAssessment | N : M | at, reason, status (OPEN, RESOLVED) | candidate disagreement |

## 3. Identity strategy

* External/business IDs from TalentBridge (`C01`, `S05`, `J03`) are the only identity; uniqueness constraints on all of them (`01_constraints_indexes.cypher`). Internal `elementId()` is never stored or exposed (not stable across exports).
* Dependent objects get **deterministic composite IDs**: `CL-C01-S01`, `APP-C02-J01`. Re-running ingestion therefore `MERGE`s onto the same node; no duplicates (V-09 shows identical counts after a rerun).
* Alias identity is the normalised text itself (`Alias.key`), which is exactly the thing that must be unique.

## 4. Constraints and indexes

| Name | Kind | Edition | Helps / protects |
|---|---|---|---|
| candidate_id_unique, skill_id_unique, job_id_unique, org_id_unique, city_id_unique, claim_id_unique, experience_id_unique, project_id_unique, application_id_unique, app_event_id_unique, recruiter_id_unique, skill_category_id_unique | uniqueness (+ backing index) | Community | identity; every `MERGE` and every `{candidateId: $id}` lookup becomes an index seek |
| alias_key_unique | uniqueness | Community | business rule BR-7: an alias cannot resolve to two skills |
| claim_level_exists / type, claim_status_exists, event_at_exists, experience_start_type | existence / type | Enterprise (commented) | domain integrity; on Community replaced by V-10..V-12 |
| claim_status_idx | range index | Community | CQ-02/03/09/12/15 start or filter on status |
| job_status_idx | range index | Community | CQ-04/07/18/19 start from OPEN jobs |
| app_event_at_idx | range index | Community | event ordering, time-range history (CQ-08/16) |
| experience_end_idx | range index | Community | CQ-11 recency window |
| candidate_name_idx | range index | Community | recruiter name search (non-unique) |
| requires_priority_idx | relationship index | Community | mandatory/preferred filters |

## 5. Time strategy

| Fact | Representation | Rule |
|---|---|---|
| Employment period | `WorkExperience.startDate`/`endDate` (DATE) | end null = ongoing; overlap allowed, detected by CQ-17 |
| Project period | `Project.startDate`/`endDate` | same |
| Recency questions | parameter `$asOf` | never `date()` inside tests, so results are reproducible |
| Job status | `Job.status` (current value) | no history required in v1; versioning path = `:JobStatusChange` events like applications |
| Application history | immutable `ApplicationEvent.at` (DATETIME UTC), `seq`, `attemptNo`, `NEXT` | append-only; current status = last event |
| Proficiency history (v2) | `SkillAssessment.assessedAt` | append-only; "as of D" = latest dated assessment ≤ D |

## 6. Skill normalisation, evidence and provenance

* **Normalisation:** every incoming skill string is looked up by `toLower(trim(text))` against `Alias.key`. Hit → canonical skill. Miss → *not* auto-created; goes to a curation queue (outside the graph scope). Curated look-alikes get `DISTINCT_FROM`. Canonical labels are themselves aliases, so a single lookup path exists.
* **Evidence:** experiences and projects are linked to the *claim* by `EVIDENCED_BY`, with `reviewStatus = 'POTENTIAL'` when derived automatically by the rule "same candidate, same skill used". Evidence never changes `verificationStatus`.
* **Provenance:** every node loaded from a table carries `source` (TP or EXT); claims carry the name of the source sheet; derived edges carry `derivedBy` naming the rule. In v2, assessments carry `origin` (MIGRATED_FROM_V1_CLAIM vs ASSESSMENT_V2), `method` and the assessor.
