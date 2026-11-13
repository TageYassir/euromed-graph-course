# Modeling Decisions (Phase B)

Twelve decision records follow (the TP requires eight). Each is traced to CQs/business rules (BR-x, see `requirements-and-cqs.md`).

---

### D-1 Candidate's name
```text
Concept: Candidate display name
Options considered: property on Candidate; separate :Person/:Name node
Decision: PROPERTY Candidate.name (indexed, NOT unique). Identity = candidateId.
CQs supported: CQ-01, CQ-12 (display); A-10 (duplicate names)
Justification: No CQ traverses through a name; a name has no relationships of its own.
Trade-off: Name history / transliterations (Idrissi vs. Idrissy) cannot be modeled without a later node.
Example: (:Candidate {candidateId:'C01', name:'Amina Idrissi'}), (:Candidate {candidateId:'C07', name:'Amina Idrissi'})
```

### D-2 Skill `Python`
```text
Concept: Skill
Options considered: string property on candidates/jobs; list property; shared node
Decision: shared canonical NODE :Skill {skillId, name} + :SkillCategory node.
CQs supported: CQ-02, CQ-03, CQ-04, CQ-10, CQ-13, CQ-19
Justification: The same skill joins candidates, jobs, experiences and projects; matching is a
               join on node identity, not on spelling. Categories are needed by CQ-13.
Trade-off: One more hop for every skill lookup; new skills require curation.
Example: (:Job)-[:REQUIRES_SKILL]->(:Skill {skillId:'S01'})<-[:ABOUT_SKILL]-(:SkillClaim)
```

### D-3 Candidate's proficiency in Python
```text
Concept: Proficiency level
Options considered: property on Candidate (pythonLevel); property on Skill; property on a
                    HAS_SKILL relationship; intermediate SkillClaim node; separate assessment node
Decision: INTERMEDIATE NODE :SkillClaim {claimId, level, verificationStatus, source}
          (Candidate)-[:MAKES_CLAIM]->(SkillClaim)-[:ABOUT_SKILL]->(Skill)
CQs supported: CQ-01, CQ-02, CQ-03, CQ-05, CQ-09, CQ-12, change request
Justification: Level is specific to the (candidate, skill) pair (BR-2), so it cannot live on
               either endpoint. A relationship property would be enough for CQ-01..03, but
               CQ-05/CQ-09 need EVIDENCE attached to the claim, and relationships cannot be
               the endpoint of other relationships in an LPG. The claim is therefore reified.
Trade-off: One extra hop and one extra node per claim; simple "who knows Python" queries are
           longer than (c)-[:HAS_SKILL {level}]->(s).
Example: (C01)-[:MAKES_CLAIM]->(:SkillClaim {level:3, verificationStatus:'VERIFIED'})-[:ABOUT_SKILL]->(Python)
```

### D-4 Job requirement for Python
```text
Concept: Requirement (mandatory/preferred, minimum level)
Options considered: two relationship types REQUIRES/PREFERS; one type with priority property;
                    :Requirement node
Decision: RELATIONSHIP WITH PROPERTIES (Job)-[:REQUIRES_SKILL {priority:'MANDATORY'|'PREFERRED', minLevel}]->(Skill)
CQs supported: CQ-02, CQ-03, CQ-04, CQ-12, CQ-15, CQ-19
Justification: A requirement has no identity or connections beyond its job and skill. One type
               keeps "all requirements of a job" a single pattern (CQ-12); priority is a filter.
               MERGE on (job, skill) guarantees one active requirement per pair (V-03).
Trade-off: Requirement versioning (stretch CQ-14) would need a :Requirement node with validity
           dates; we did not choose CQ-14 and document the migration path instead.
Example: (J01)-[:REQUIRES_SKILL {priority:'PREFERRED', minLevel:1}]->(Docker)
```

### D-5 Company
```text
Concept: Organization
Options considered: property employer on experience/job; shared node
Decision: NODE :Organization {orgId, name} -[:LOCATED_IN]-> City
CQs supported: CQ-06, CQ-04 (display), CQ-05
Justification: The same employer appears in many work histories and job ads (O02 in E02, E03,
               E06, J02, J03). A node gives one place to rename/merge and enables
               "who worked where we are hiring".
Trade-off: Company aliases (NorthStar vs. North Star Analytics) not handled yet.
Example: (E02)-[:AT_ORGANIZATION]->(O02)<-[:PUBLISHED_BY]-(J03)
```

### D-6 Work experience
```text
Concept: Employment period
Options considered: relationship (Candidate)-[:WORKED_AT {role,start,end}]->(Organization);
                    intermediate node
Decision: INTERMEDIATE NODE :WorkExperience {experienceId, roleTitle, employmentType,
          startDate: date, endDate: date|null}
          (Candidate)-[:HAS_EXPERIENCE]->(WorkExperience)-[:AT_ORGANIZATION]->(Organization)
          (WorkExperience)-[:USED_SKILL]->(Skill); (Project)-[:PART_OF]->(WorkExperience)
CQs supported: CQ-05, CQ-06, CQ-11, CQ-13, CQ-17
Justification: BR-4 needs skills attached to ONE employment period ("where and when"). With a
               relationship, USED_SKILL would have nowhere to start from. Overlapping or repeated
               jobs at the same company are separate nodes, so nothing collapses (BR-5).
Trade-off: More nodes; the "worked at" question needs two hops.
Example: (C08)-[:HAS_EXPERIENCE]->(E08 {2023-01-01..2025-06-30})-[:AT_ORGANIZATION]->(O04)
```

### D-7 City / location
```text
Concept: City
Options considered: string properties; shared node
Decision: NODE :City {cityId, name, countryCode} used by LIVES_IN, AVAILABLE_ONSITE_IN,
          BASED_IN (job), LOCATED_IN (organization)
CQs supported: CQ-02/12/15/18 (location rule), CQ-07
Justification: The location rule is a join between candidate availability and job city; a shared
               node makes it an identity test instead of a string comparison ("Casablanca" vs "Casa").
Trade-off: No geographic distance or region hierarchy (could add (:City)-[:IN_REGION]->()).
Example: (C01)-[:AVAILABLE_ONSITE_IN]->(Rabat)<-[:BASED_IN]-(J01)
```

### D-8 Remote-work preference
```text
Concept: Remote availability
Options considered: boolean property on Candidate; :WorkPreference node; relationship to a "Remote" pseudo-city
Decision: PROPERTY Candidate.remoteAvailable (true/false/null). Onsite availability is a
          RELATIONSHIP to City (many cities per candidate).
CQs supported: CQ-07, CQ-12, CQ-15, CQ-18
Justification: Remote availability carries no extra information in the requirements (no dates,
               no conditions), so it is an attribute. Onsite availability is many-to-many with
               cities, so it is a relationship.
Trade-off: If availability gains conditions (from date, days/week), it must become a node.
Example: (:Candidate {remoteAvailable:true})-[:AVAILABLE_ONSITE_IN]->(:City {name:'Fez'})
```

### D-9 Skill alias
```text
Concept: Alias / synonym
Options considered: list property Skill.aliases; :Alias node; fuzzy text index
Decision: NODE :Alias {key (unique, toLower(trim(label))), label} -[:ALIAS_OF]-> Skill,
          plus (Skill)-[:DISTINCT_FROM {reason}]->(Skill) for known look-alikes.
CQs supported: CQ-04, CQ-05, CQ-10, CQ-11
Justification: A uniqueness constraint on Alias.key makes it impossible for "ml" to point to two
               skills; exact-key lookup (no CONTAINS/STARTS WITH) prevents Java→JavaScript and
               Spark→SPARQL. DISTINCT_FROM records a human "do not merge" decision (V-05).
Trade-off: Unknown spellings ("Py") return nothing until curated; no fuzzy recall.
Example: (:Alias {key:'ml'})-[:ALIAS_OF]->(S05 Machine Learning); (S07 Java)-[:DISTINCT_FROM]->(S08 JavaScript)
```

### D-10 Application
```text
Concept: Application and its history
Options considered: relationship (Candidate)-[:APPLIED_TO {status}]->(Job); relationship per event;
                    Application node + event nodes
Decision: NODE :Application (one per candidate+job "case") with immutable :ApplicationEvent nodes
          {eventId, type, at: datetime, seq, attemptNo, decision, note},
          ordered by timestamp and chained with NEXT; recruiter actions via PERFORMED_BY.
CQs supported: CQ-08, CQ-16, A-5, A-9
Justification: A status property would be overwritten (TP §6.7 forbids it). Several events per
               pair, each with its own time and actor, make the association a first-class object.
               REAPPLIED increments attemptNo inside the same case, so funnel counts stay per person.
Trade-off: "Current status" must be derived (last event); NEXT/seq/attemptNo are derived data and
           are rebuilt on every load.
Example: (C02)-[:SUBMITTED]->(APP-C02-J01)-[:HAS_EVENT]->(AEV02 APPLIED)-[:NEXT]->(AEV03 WITHDRAWN)-[:NEXT]->(AEV04 REAPPLIED)
```

### D-11 Proof of skill
```text
Concept: Evidence
Options considered: property evidence on claim; relationship experience->skill only;
                    claim -> evidence relationship; :Evidence node
Decision: RELATIONSHIP (SkillClaim)-[:EVIDENCED_BY {evidenceType, reviewStatus, derivedBy}]->(WorkExperience|Project)
CQs supported: CQ-05, CQ-09, CQ-12b, change request (BASED_ON)
Justification: Evidence must point to a specific claim (TP Phase B). The evidence objects
               (experience, project) already exist as nodes, so a relationship is enough;
               reviewStatus = 'POTENTIAL' keeps "linked" distinct from "verified".
Trade-off: Certifications would need a :Certification node; evidence reviewed by someone at some
           time would require an :EvidenceReview node (covered by the change request's assessment).
Example: (CL-C01-S01)-[:EVIDENCED_BY {reviewStatus:'POTENTIAL'}]->(E01)
```

### D-12 Verification status
```text
Concept: Verification
Options considered: on Candidate (verified profile); on Skill; on the claim; on each evidence link
Decision: PROPERTY on the claim: SkillClaim.verificationStatus ∈ {VERIFIED, UNVERIFIED, REFUTED};
          per-evidence review state on EVIDENCED_BY.reviewStatus.
CQs supported: CQ-02, CQ-03, CQ-09, CQ-12, CQ-15
Justification: "Verified" qualifies one statement about one person and one skill (TP 6.3).
               Putting it on the candidate would verify every claim; on the skill it is meaningless.
Trade-off: Who verified and when is unknown in v1 (solved by the change request).
Example: (C05)-[:MAKES_CLAIM]->(:SkillClaim {skill:Neo4j, verificationStatus:'UNVERIFIED'})
```

### D-13 Job title (short record)
Decision: **property** `Job.title` and `WorkExperience.roleTitle`. No CQ groups jobs by role family. A `:JobRole` taxonomy (e.g. "Data Engineer" family) becomes valuable when recruiters ask "candidates who held a role similar to this job" — documented as a future extension.

---

## Discussion prompts

**When does a property become a node?** When it needs its own identity, is shared by several entities, or must carry relationships/attributes of its own. (1) The skill name: as a string it would be duplicated on 30+ claims and requirements; as a node it is shared and can carry aliases and a category. (2) The city: as text it cannot be joined reliably for the location rule; as a node it links candidates, jobs and organizations. (3) Proficiency is the counter-example: it stays a property, but of the *claim* node.

**Relationship property vs. node.** A relationship property suffices when the fact belongs only to the pair and nothing else must point at it: `REQUIRES_SKILL.minLevel`, `EVIDENCED_BY.reviewStatus`, `DISPUTES.reason`. The association becomes a node when it needs (a) its own relationships (a claim needs evidence; an experience needs skills and projects), (b) multiple occurrences for the same pair over time (applications, assessments), or (c) a stable ID referenced by other systems.

**Duplicating skill names on every job and candidate?** No. Duplication produces spelling drift ("ML", "Machine learning"), makes renames O(n) updates, and turns matching into string comparison, which is exactly how Java and JavaScript get confused. With a canonical node, matching is identity.

**Job vs. JobPosting vs. JobRole.** For the current scope they are one concept, `:Job` = a posting by one organization with its own status and requirements. JobRole (a reusable taxonomy) is out of scope (D-13). JobPosting would split from Job if the same opening were republished on several channels with different dates.

**Unknown vs. not verified vs. verified false.** Unknown = no `SkillClaim` (and `remoteAvailable = null` for availability); not verified = `UNVERIFIED`; verified false = `REFUTED`. Queries test explicit values, never `<> 'VERIFIED'` alone when the distinction matters (CQ-09 labels each case).

**Missing dates, open periods, duplicates.** Missing end date = ongoing; queries use `coalesce(endDate, $asOf)`. A missing *start* date is not allowed for experiences (V-07; existence constraint on Enterprise). Unknown assessment dates stay `null` and are excluded from "as of" queries (change request). Duplicates: `MERGE` on business IDs makes reloads idempotent; duplicate *people* with the same name are never auto-merged; duplicate skill spellings are folded through aliases only after a curation decision.
