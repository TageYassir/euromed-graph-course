// =====================================================================
// TalentBridge LPG — 05 Change request: proficiency over time, assessor,
// assessment date, evidence, candidate disagreement. (Phase G)
// Run AFTER 01-04. Additive and idempotent: nothing is deleted or overwritten.
//
// Evolution (minimal):
//   NEW  (:SkillAssessment {assessmentId, level, assessedAt, method, outcome, origin})
//   NEW  (:Assessor {assessorId, name})           -- a Recruiter may also carry :Assessor
//   NEW  (SkillAssessment)-[:ASSESSES]->(SkillClaim)
//   NEW  (SkillAssessment)-[:ASSESSED_BY]->(Assessor)
//   NEW  (SkillAssessment)-[:BASED_ON]->(WorkExperience|Project)
//   NEW  (Candidate)-[:DISPUTES {at, reason, status}]->(SkillAssessment)
//   KEPT (Candidate)-[:MAKES_CLAIM]->(SkillClaim)-[:ABOUT_SKILL]->(Skill)
//        SkillClaim.level now means "self-declared level"; SkillClaim.verificationStatus is kept
//        as the v1 summary so every v1 query (CQ-01..CQ-19) keeps working unchanged.
// =====================================================================

CREATE CONSTRAINT assessment_id_unique IF NOT EXISTS
FOR (a:SkillAssessment) REQUIRE a.assessmentId IS UNIQUE;

CREATE CONSTRAINT assessor_id_unique IF NOT EXISTS
FOR (a:Assessor) REQUIRE a.assessorId IS UNIQUE;

CREATE INDEX assessment_date_idx IF NOT EXISTS
FOR (a:SkillAssessment) ON (a.assessedAt);

// ---------- M-1 Migration: one legacy assessment per v1 claim that had a verification outcome ----------
// Unknown assessor and date stay NULL (never invented); origin marks the provenance.
MATCH (cl:SkillClaim)
WHERE cl.verificationStatus IN ['VERIFIED', 'REFUTED']
MERGE (sa:SkillAssessment {assessmentId: 'ASM-' + cl.claimId + '-V1'})
ON CREATE SET sa.level = CASE WHEN cl.verificationStatus = 'VERIFIED' THEN cl.level ELSE null END,
              sa.outcome = cl.verificationStatus,
              sa.assessedAt = null,
              sa.method = 'UNKNOWN',
              sa.origin = 'MIGRATED_FROM_V1_CLAIM'
MERGE (sa)-[:ASSESSES]->(cl);

// ---------- M-2 Assessors (a recruiter can also be an assessor: multi-label) ----------
MERGE (a1:Assessor {assessorId: 'A01'}) SET a1.name = 'Leila Mansouri', a1.kind = 'TECHNICAL_PANEL';
MATCH (r:Recruiter {recruiterId: 'R02'}) SET r:Assessor, r.assessorId = 'A02';

// ---------- M-3 New dated assessments for C01 / Python (history 2024 -> 2026) ----------
UNWIND [
  {id:'ASM-C01-S01-2024', lvl:1, at:'2024-03-15', method:'TECHNICAL_INTERVIEW', by:'A01', basedOn:['E01']},
  {id:'ASM-C01-S01-2025', lvl:2, at:'2025-06-01', method:'TAKE_HOME_TEST',      by:'A01', basedOn:['E01']},
  {id:'ASM-C01-S01-2026', lvl:3, at:'2026-05-10', method:'CODE_REVIEW',         by:'A02', basedOn:['E01','P01']}
] AS r
MATCH (cl:SkillClaim {claimId: 'CL-C01-S01'}), (who:Assessor {assessorId: r.by})
MERGE (sa:SkillAssessment {assessmentId: r.id})
SET sa.level = r.lvl, sa.assessedAt = date(r.at), sa.method = r.method,
    sa.outcome = 'VERIFIED', sa.origin = 'ASSESSMENT_V2'
MERGE (sa)-[:ASSESSES]->(cl)
MERGE (sa)-[:ASSESSED_BY]->(who)
WITH sa, r
UNWIND r.basedOn AS eid
MATCH (x) WHERE x.experienceId = eid OR x.projectId = eid
MERGE (sa)-[:BASED_ON]->(x);

// ---------- M-4 Candidate disagreement (kept as a fact, assessment not deleted) ----------
MATCH (c:Candidate {candidateId: 'C01'}), (sa:SkillAssessment {assessmentId: 'ASM-C01-S01-2025'})
MERGE (c)-[d:DISPUTES]->(sa)
SET d.at = datetime('2025-06-05T10:00:00Z'),
    d.reason = 'Test environment lacked required libraries',
    d.status = 'OPEN';


// =====================================================================
// CQ-H1  What was candidate $candidateId's assessed proficiency in $skillTerm as of $asOf,
//        who assessed it, on what evidence, and is it disputed?
//        Policy: latest DATED assessment on or before $asOf; undated (migrated) assessments are
//        reported separately, never treated as "latest".
// Columns: candidateId, skill, asOf, level, assessedAt, assessor, method, evidence, disputed
// =====================================================================
MATCH (:Alias {key: toLower(trim($skillTerm))})-[:ALIAS_OF]->(s:Skill)
MATCH (c:Candidate {candidateId: $candidateId})-[:MAKES_CLAIM]->(cl:SkillClaim)-[:ABOUT_SKILL]->(s),
      (sa:SkillAssessment)-[:ASSESSES]->(cl)
WHERE sa.assessedAt IS NOT NULL AND sa.assessedAt <= $asOf
WITH c, s, sa AS latest ORDER BY sa.assessedAt DESC LIMIT 1
OPTIONAL MATCH (latest)-[:ASSESSED_BY]->(who:Assessor)
OPTIONAL MATCH (latest)-[:BASED_ON]->(x)
OPTIONAL MATCH (c)-[d:DISPUTES]->(latest)
RETURN c.candidateId AS candidateId, s.name AS skill, $asOf AS asOf, latest.level AS level,
       latest.assessedAt AS assessedAt, who.name AS assessor, latest.method AS method,
       collect(DISTINCT coalesce(x.experienceId, x.projectId)) AS evidence,
       count(d) > 0 AS disputed;

// CQ-H2  Full proficiency timeline (dated first, undated legacy last), with disputes.
// Columns: assessmentId, assessedAt, level, method, assessor, origin, disputed, disputeReason
MATCH (:Alias {key: toLower(trim($skillTerm))})-[:ALIAS_OF]->(s:Skill)
MATCH (c:Candidate {candidateId: $candidateId})-[:MAKES_CLAIM]->(cl:SkillClaim)-[:ABOUT_SKILL]->(s),
      (sa:SkillAssessment)-[:ASSESSES]->(cl)
OPTIONAL MATCH (sa)-[:ASSESSED_BY]->(who:Assessor)
OPTIONAL MATCH (c)-[d:DISPUTES]->(sa)
RETURN sa.assessmentId AS assessmentId, sa.assessedAt AS assessedAt, sa.level AS level,
       sa.method AS method, coalesce(who.name, 'unknown') AS assessor, sa.origin AS origin,
       d IS NOT NULL AS disputed, d.reason AS disputeReason
ORDER BY sa.assessedAt IS NULL, sa.assessedAt;

// T-H1  Test: as of 2025-01-01 C01's Python is level 1; as of 2026-11-12 it is level 3;
//       the 2025 assessment is disputed but still present.
MATCH (cl:SkillClaim {claimId: 'CL-C01-S01'})<-[:ASSESSES]-(sa:SkillAssessment)
WHERE sa.assessedAt IS NOT NULL
WITH sa ORDER BY sa.assessedAt
WITH collect(sa) AS hist
WITH [x IN hist WHERE x.assessedAt <= date('2025-01-01')] AS h1,
     [x IN hist WHERE x.assessedAt <= date('2026-11-12')] AS h2, hist
MATCH (:Candidate {candidateId: 'C01'})-[:DISPUTES]->(dis:SkillAssessment)
RETURN 'T-H1 historical proficiency' AS test,
       (h1[size(h1)-1].level = 1 AND h2[size(h2)-1].level = 3 AND size(hist) = 3
        AND dis.assessmentId = 'ASM-C01-S01-2025') AS passed,
       [x IN hist | toString(x.assessedAt) + ':' + toString(x.level)] AS detail;
