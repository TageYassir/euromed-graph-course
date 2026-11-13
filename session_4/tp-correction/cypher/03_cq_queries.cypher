// =====================================================================
// TalentBridge LPG — 03 Competency-question queries
// Every answer is computed by traversal; no answer list is hard-coded.
// Parameters (set them in Neo4j Browser with e.g.  :param jobId => 'J01'
// or pass them with  cypher-shell --param "jobId => 'J01'" ):
//   $candidateId  default 'C01'      $jobId          default 'J01'
//   $skillTerm    default 'Python'   $requiredTerm   default 'Python'
//   $preferredTerm default 'Docker'  $minMet         default 2
//   $asOf         default date('2026-11-12')   (date used as "today")
// Shared definitions (see requirements-and-cqs.md §3):
//   MET mandatory requirement := candidate has a claim on the SAME canonical skill with
//       verificationStatus = 'VERIFIED' AND level >= requirement.minLevel.
//   LOCATION OK := REMOTE job -> candidate.remoteAvailable = true;
//                  HYBRID/ONSITE job -> candidate AVAILABLE_ONSITE_IN the job's city.
//   SUITABLE := all mandatory requirements MET AND LOCATION OK (preferred skills only explain).
// =====================================================================


// ---------------------------------------------------------------------
// CQ-01  Skills claimed by a candidate with level and verification status.
// Columns: candidateId, name, skill, category, level, levelLabel, verificationStatus
// ---------------------------------------------------------------------
MATCH (c:Candidate {candidateId: $candidateId})-[:MAKES_CLAIM]->(cl:SkillClaim)-[:ABOUT_SKILL]->(s:Skill)
OPTIONAL MATCH (s)-[:IN_CATEGORY]->(cat:SkillCategory)
RETURN c.candidateId AS candidateId, c.name AS name, s.name AS skill, cat.name AS category,
       cl.level AS level,
       CASE cl.level WHEN 1 THEN 'beginner' WHEN 2 THEN 'intermediate' WHEN 3 THEN 'advanced' END AS levelLabel,
       cl.verificationStatus AS verificationStatus
ORDER BY level DESC, skill;


// ---------------------------------------------------------------------
// CQ-02  Candidates meeting ALL mandatory skill requirements of a job (skill rule only;
//        geography reported in a separate column, never mixed into the skill verdict).
// Columns: jobId, candidateId, name, mandatoryMet, mandatoryTotal, locationOk
// ---------------------------------------------------------------------
MATCH (j:Job {jobId: $jobId})-[:REQUIRES_SKILL {priority: 'MANDATORY'}]->(ms:Skill)
WITH j, count(DISTINCT ms) AS nMand
MATCH (j)-[req:REQUIRES_SKILL {priority: 'MANDATORY'}]->(s:Skill)
      <-[:ABOUT_SKILL]-(cl:SkillClaim {verificationStatus: 'VERIFIED'})<-[:MAKES_CLAIM]-(c:Candidate)
WHERE cl.level >= req.minLevel
WITH j, nMand, c, count(DISTINCT s) AS nMet
WHERE nMet = nMand
OPTIONAL MATCH (j)-[:BASED_IN]->(jc:City)
OPTIONAL MATCH (c)-[av:AVAILABLE_ONSITE_IN]->(jc)
RETURN j.jobId AS jobId, c.candidateId AS candidateId, c.name AS name,
       nMet AS mandatoryMet, nMand AS mandatoryTotal,
       CASE WHEN j.workMode = 'REMOTE' THEN coalesce(c.remoteAvailable, false)
            ELSE av IS NOT NULL END AS locationOk
ORDER BY candidateId;


// ---------------------------------------------------------------------
// CQ-03  Candidates meeting at least $minMet mandatory requirements (default 2),
//        with the list of mandatory skills still missing and WHY.
// Columns: candidateId, name, metCount, mandatoryTotal, met, missing
// ---------------------------------------------------------------------
MATCH (j:Job {jobId: $jobId})-[req:REQUIRES_SKILL {priority: 'MANDATORY'}]->(s:Skill)
MATCH (c:Candidate)
OPTIONAL MATCH (c)-[:MAKES_CLAIM]->(cl:SkillClaim)-[:ABOUT_SKILL]->(s)
WITH j, c, s, req, cl,
     (cl IS NOT NULL AND cl.verificationStatus = 'VERIFIED' AND cl.level >= req.minLevel) AS isMet
WITH j, c,
     count(s) AS mandatoryTotal,
     collect(CASE WHEN isMet THEN s.name END) AS met,
     collect(CASE WHEN NOT isMet THEN s.name + ' (' +
        CASE WHEN cl IS NULL THEN 'no claim'
             WHEN cl.verificationStatus <> 'VERIFIED' THEN toLower(cl.verificationStatus)
             ELSE 'level ' + toString(cl.level) + ' < ' + toString(req.minLevel) END + ')' END) AS missing
WHERE size(met) >= $minMet
RETURN c.candidateId AS candidateId, c.name AS name, size(met) AS metCount, mandatoryTotal,
       met, missing
ORDER BY metCount DESC, candidateId;


// ---------------------------------------------------------------------
// CQ-04  OPEN jobs that require (mandatory) $requiredTerm and prefer $preferredTerm.
//        Terms are resolved through aliases ('Python 3' works; 'Py' does not).
// Columns: jobId, title, organization, workMode, required, preferred
// ---------------------------------------------------------------------
MATCH (:Alias {key: toLower(trim($requiredTerm))})-[:ALIAS_OF]->(rs:Skill)
MATCH (:Alias {key: toLower(trim($preferredTerm))})-[:ALIAS_OF]->(ps:Skill)
MATCH (o:Organization)<-[:PUBLISHED_BY]-(j:Job {status: 'OPEN'})-[r1:REQUIRES_SKILL {priority: 'MANDATORY'}]->(rs)
MATCH (j)-[r2:REQUIRES_SKILL {priority: 'PREFERRED'}]->(ps)
RETURN j.jobId AS jobId, j.title AS title, o.name AS organization, j.workMode AS workMode,
       rs.name + ' >= ' + toString(r1.minLevel) AS required,
       ps.name + ' >= ' + toString(r2.minLevel) AS preferred
ORDER BY jobId;


// ---------------------------------------------------------------------
// CQ-05  Work experiences / projects that support a candidate's claim of a skill.
//        Evidence is POTENTIAL unless reviewed; it never changes verificationStatus.
// Columns: candidateId, skill, claimLevel, verificationStatus, evidenceType, evidenceId,
//          detail, organization, startDate, endDate, reviewStatus
// ---------------------------------------------------------------------
MATCH (:Alias {key: toLower(trim($skillTerm))})-[:ALIAS_OF]->(s:Skill)
MATCH (c:Candidate {candidateId: $candidateId})-[:MAKES_CLAIM]->(cl:SkillClaim)-[:ABOUT_SKILL]->(s)
OPTIONAL MATCH (cl)-[ev:EVIDENCED_BY]->(e)
OPTIONAL MATCH (e)-[:AT_ORGANIZATION|PART_OF*1..2]->(o:Organization)
RETURN c.candidateId AS candidateId, s.name AS skill, cl.level AS claimLevel,
       cl.verificationStatus AS verificationStatus,
       ev.evidenceType AS evidenceType,
       coalesce(e.experienceId, e.projectId) AS evidenceId,
       coalesce(e.roleTitle, e.name) AS detail,
       o.name AS organization, e.startDate AS startDate, e.endDate AS endDate,
       ev.reviewStatus AS reviewStatus
ORDER BY startDate;


// ---------------------------------------------------------------------
// CQ-06  Employment history: companies, roles, periods (open-ended = ongoing).
// Columns: candidateId, experienceId, organization, role, employmentType, startDate,
//          endDate, ongoing, months (up to $asOf for ongoing roles)
// ---------------------------------------------------------------------
MATCH (c:Candidate {candidateId: $candidateId})-[:HAS_EXPERIENCE]->(e:WorkExperience)-[:AT_ORGANIZATION]->(o:Organization)
RETURN c.candidateId AS candidateId, e.experienceId AS experienceId, o.name AS organization,
       e.roleTitle AS role, e.employmentType AS employmentType,
       e.startDate AS startDate, e.endDate AS endDate, e.endDate IS NULL AS ongoing,
       duration.inMonths(e.startDate, coalesce(e.endDate, $asOf)).months AS months
ORDER BY startDate;


// ---------------------------------------------------------------------
// CQ-07  (rewritten) For each OPEN job that has an onsite city (HYBRID/ONSITE), which
//        candidates are remote-available but NOT available onsite in that job's city?
//        (They would only fit if the job were opened to remote work.)
// Columns: jobId, title, workMode, jobCity, candidateId, name, onsiteCities
// ---------------------------------------------------------------------
MATCH (j:Job {status: 'OPEN'})-[:BASED_IN]->(jc:City)
MATCH (c:Candidate {remoteAvailable: true})
WHERE NOT (c)-[:AVAILABLE_ONSITE_IN]->(jc)
OPTIONAL MATCH (c)-[:AVAILABLE_ONSITE_IN]->(oc:City)
RETURN j.jobId AS jobId, j.title AS title, j.workMode AS workMode, jc.name AS jobCity,
       c.candidateId AS candidateId, c.name AS name, collect(oc.name) AS onsiteCities
ORDER BY jobId, candidateId;


// ---------------------------------------------------------------------
// CQ-08  Per job: number of distinct candidates who applied, withdrew, reapplied
//        (jobs with no applications are listed with zeros).
// Columns: jobId, title, status, applied, withdrew, reapplied, currentlyActive
// ---------------------------------------------------------------------
MATCH (j:Job)
OPTIONAL MATCH (j)<-[:FOR_JOB]-(a:Application)<-[:SUBMITTED]-(c:Candidate)
OPTIONAL MATCH (a)-[:HAS_EVENT]->(ev:ApplicationEvent)
WITH j, a, c, ev ORDER BY ev.at
WITH j, a, c, collect(ev.type) AS types
WITH j,
     count(DISTINCT CASE WHEN 'APPLIED'   IN types THEN c END) AS applied,
     count(DISTINCT CASE WHEN 'WITHDRAWN' IN types THEN c END) AS withdrew,
     count(DISTINCT CASE WHEN 'REAPPLIED' IN types THEN c END) AS reapplied,
     count(DISTINCT CASE WHEN size(types) > 0 AND NOT types[size(types)-1] IN ['WITHDRAWN','REJECTED'] THEN c END) AS currentlyActive
RETURN j.jobId AS jobId, j.title AS title, j.status AS status, applied, withdrew, reapplied, currentlyActive
ORDER BY jobId;


// ---------------------------------------------------------------------
// CQ-09  Skill claims that are not VERIFIED, or that have no evidence link at all.
// Columns: candidateId, name, skill, level, verificationStatus, evidenceCount, issue
// ---------------------------------------------------------------------
MATCH (c:Candidate)-[:MAKES_CLAIM]->(cl:SkillClaim)-[:ABOUT_SKILL]->(s:Skill)
OPTIONAL MATCH (cl)-[ev:EVIDENCED_BY]->()
WITH c, cl, s, count(ev) AS evidenceCount
WHERE cl.verificationStatus <> 'VERIFIED' OR evidenceCount = 0
RETURN c.candidateId AS candidateId, c.name AS name, s.name AS skill, cl.level AS level,
       cl.verificationStatus AS verificationStatus, evidenceCount,
       CASE WHEN cl.verificationStatus = 'REFUTED' THEN 'verified FALSE'
            WHEN cl.verificationStatus <> 'VERIFIED' AND evidenceCount = 0 THEN 'unverified, no evidence'
            WHEN cl.verificationStatus <> 'VERIFIED' THEN 'unverified, evidence awaiting review'
            ELSE 'verified but no linked evidence (provenance gap)' END AS issue
ORDER BY candidateId, skill;


// ---------------------------------------------------------------------
// CQ-10a  Alias table: every canonical skill with all the surface forms that resolve to it,
//         plus look-alike skills it must NOT be merged with.
// Columns: skillId, canonical, aliases, mustNotMergeWith
// ---------------------------------------------------------------------
MATCH (s:Skill)<-[:ALIAS_OF]-(a:Alias)
OPTIONAL MATCH (s)-[:DISTINCT_FROM]-(other:Skill)
RETURN s.skillId AS skillId, s.name AS canonical,
       collect(DISTINCT a.label) AS aliases, collect(DISTINCT other.name) AS mustNotMergeWith
ORDER BY skillId;

// CQ-10b  Resolve a free-text term ($skillTerm) to exactly one canonical skill (or none).
// Columns: term, skillId, canonical
WITH toLower(trim($skillTerm)) AS key
OPTIONAL MATCH (:Alias {key: key})-[:ALIAS_OF]->(s:Skill)
RETURN $skillTerm AS term, s.skillId AS skillId, s.name AS canonical;


// ---------------------------------------------------------------------
// CQ-11  Candidates who USED $skillTerm (default Python) in a job or project whose period
//        overlaps the window [$asOf - 2 years, $asOf]. Usage, not verification.
// Columns: candidateId, name, context, contextId, startDate, endDate
// ---------------------------------------------------------------------
MATCH (:Alias {key: toLower(trim($skillTerm))})-[:ALIAS_OF]->(s:Skill)
MATCH (c:Candidate)-[:HAS_EXPERIENCE|WORKED_ON]->(x)-[:USED_SKILL]->(s)
WHERE x.startDate <= $asOf
  AND (x.endDate IS NULL OR x.endDate >= $asOf - duration({years: 2}))
RETURN c.candidateId AS candidateId, c.name AS name,
       CASE WHEN x.experienceId IS NOT NULL THEN 'job' ELSE 'project' END AS context,
       coalesce(x.experienceId, x.projectId) AS contextId, x.startDate AS startDate, x.endDate AS endDate
ORDER BY candidateId, startDate;


// ---------------------------------------------------------------------
// CQ-12a  Explain a candidate/job match (summary row).
// Columns: candidateId, jobId, metMandatory, unmetMandatory, matchedPreferred,
//          unmatchedPreferred, locationOk, verdict
// ---------------------------------------------------------------------
MATCH (c:Candidate {candidateId: $candidateId}), (j:Job {jobId: $jobId})
MATCH (j)-[req:REQUIRES_SKILL]->(s:Skill)
OPTIONAL MATCH (c)-[:MAKES_CLAIM]->(cl:SkillClaim)-[:ABOUT_SKILL]->(s)
WITH c, j, req, s, cl,
     CASE WHEN cl IS NULL THEN 'no claim'
          WHEN cl.verificationStatus <> 'VERIFIED' THEN toLower(cl.verificationStatus) + ' claim (level ' + toString(cl.level) + ')'
          WHEN cl.level < req.minLevel THEN 'level ' + toString(cl.level) + ' < required ' + toString(req.minLevel)
          ELSE 'MET' END AS outcome
WITH c, j,
     collect(CASE WHEN req.priority = 'MANDATORY' AND outcome = 'MET'  THEN s.name END) AS metMandatory,
     collect(CASE WHEN req.priority = 'MANDATORY' AND outcome <> 'MET' THEN s.name + ': ' + outcome END) AS unmetMandatory,
     collect(CASE WHEN req.priority = 'PREFERRED' AND outcome = 'MET'  THEN s.name END) AS matchedPreferred,
     collect(CASE WHEN req.priority = 'PREFERRED' AND outcome <> 'MET' THEN s.name + ': ' + outcome END) AS unmatchedPreferred
OPTIONAL MATCH (j)-[:BASED_IN]->(jc:City)
OPTIONAL MATCH (c)-[av:AVAILABLE_ONSITE_IN]->(jc)
WITH c, j, metMandatory, unmetMandatory, matchedPreferred, unmatchedPreferred,
     CASE WHEN j.workMode = 'REMOTE' THEN coalesce(c.remoteAvailable, false) ELSE av IS NOT NULL END AS locationOk
RETURN c.candidateId AS candidateId, j.jobId AS jobId, metMandatory, unmetMandatory,
       matchedPreferred, unmatchedPreferred, locationOk,
       CASE WHEN size(unmetMandatory) > 0 THEN 'REJECT: mandatory skill gap'
            WHEN NOT locationOk THEN 'REJECT: location'
            WHEN j.status <> 'OPEN' THEN 'SKILLS+LOCATION OK, but job is ' + j.status
            ELSE 'SUITABLE' END AS verdict;

// CQ-12b  Same explanation, one row per requirement (for the recruiter UI / report).
MATCH (c:Candidate {candidateId: $candidateId}), (j:Job {jobId: $jobId})-[req:REQUIRES_SKILL]->(s:Skill)
OPTIONAL MATCH (c)-[:MAKES_CLAIM]->(cl:SkillClaim)-[:ABOUT_SKILL]->(s)
OPTIONAL MATCH (cl)-[ev:EVIDENCED_BY]->(e)
WITH c, j, req, s, cl, collect(coalesce(e.experienceId, e.projectId)) AS evidence
RETURN req.priority AS priority, s.name AS skill, req.minLevel AS minLevel,
       cl.level AS claimedLevel, cl.verificationStatus AS verification, evidence,
       CASE WHEN cl IS NULL THEN 'NO_CLAIM'
            WHEN cl.verificationStatus <> 'VERIFIED' THEN 'NOT_VERIFIED'
            WHEN cl.level < req.minLevel THEN 'LEVEL_TOO_LOW'
            ELSE 'MET' END AS outcome
ORDER BY priority, skill;


// =====================================================================
// STRETCH CQs (CQ-13, CQ-15, CQ-16)
// =====================================================================

// CQ-13  Candidates who used a Programming language AND a Graph database in the SAME project.
// Columns: candidateId, name, projectId, project, languages, graphDatabases
MATCH (c:Candidate)-[:WORKED_ON]->(p:Project)-[:USED_SKILL]->(lang:Skill)-[:IN_CATEGORY]->(:SkillCategory {name: 'Programming'})
MATCH (p)-[:USED_SKILL]->(gdb:Skill)-[:IN_CATEGORY]->(:SkillCategory {name: 'Graph database'})
RETURN c.candidateId AS candidateId, c.name AS name, p.projectId AS projectId, p.name AS project,
       collect(DISTINCT lang.name) AS languages, collect(DISTINCT gdb.name) AS graphDatabases
ORDER BY candidateId;

// CQ-15  Jobs with NO suitable candidate under the SUITABLE rule (skills + location).
// Columns: jobId, title, status, mandatorySkills, skillOnlyMatches
MATCH (j:Job)-[:REQUIRES_SKILL {priority: 'MANDATORY'}]->(ms:Skill)
WITH j, count(DISTINCT ms) AS nMand, collect(ms.name) AS mandatorySkills
OPTIONAL MATCH (j)-[req:REQUIRES_SKILL {priority: 'MANDATORY'}]->(s:Skill)
      <-[:ABOUT_SKILL]-(cl:SkillClaim {verificationStatus: 'VERIFIED'})<-[:MAKES_CLAIM]-(c:Candidate)
WHERE cl.level >= req.minLevel
WITH j, nMand, mandatorySkills, c, count(DISTINCT s) AS nMet
WITH j, mandatorySkills, collect(CASE WHEN nMet = nMand THEN c END) AS skillOk
UNWIND (CASE WHEN size(skillOk) = 0 THEN [null] ELSE skillOk END) AS c
OPTIONAL MATCH (j)-[:BASED_IN]->(jc:City)
OPTIONAL MATCH (c)-[av:AVAILABLE_ONSITE_IN]->(jc)
WITH j, mandatorySkills, skillOk, c,
     CASE WHEN c IS NULL THEN false
          WHEN j.workMode = 'REMOTE' THEN coalesce(c.remoteAvailable, false)
          ELSE av IS NOT NULL END AS ok
WITH j, mandatorySkills, size(skillOk) AS skillOnlyMatches, collect(CASE WHEN ok THEN c.candidateId END) AS suitable
WHERE size(suitable) = 0
RETURN j.jobId AS jobId, j.title AS title, j.status AS status, mandatorySkills, skillOnlyMatches
ORDER BY jobId;

// CQ-16  Recruiter actions on applications, with decisions and timestamps.
// Columns: recruiterId, recruiter, applicationId, candidateId, jobId, eventType, decision, at, note
MATCH (r:Recruiter)<-[:PERFORMED_BY]-(ev:ApplicationEvent)<-[:HAS_EVENT]-(a:Application)-[:FOR_JOB]->(j:Job),
      (c:Candidate)-[:SUBMITTED]->(a)
RETURN r.recruiterId AS recruiterId, r.name AS recruiter, a.applicationId AS applicationId,
       c.candidateId AS candidateId, j.jobId AS jobId, ev.type AS eventType, ev.decision AS decision,
       ev.at AS at, ev.note AS note
ORDER BY at;


// =====================================================================
// TEAM CQs (CQ-17 .. CQ-19)
// =====================================================================

// CQ-17  Candidates with overlapping employment periods (legit freelance vs. data error).
// Columns: candidateId, name, expA, typeA, expB, typeB, overlapStart, overlapEnd
MATCH (c:Candidate)-[:HAS_EXPERIENCE]->(a:WorkExperience),
      (c)-[:HAS_EXPERIENCE]->(b:WorkExperience)
WHERE a.experienceId < b.experienceId
  AND a.startDate <= coalesce(b.endDate, $asOf)
  AND b.startDate <= coalesce(a.endDate, $asOf)
RETURN c.candidateId AS candidateId, c.name AS name,
       a.experienceId AS expA, a.employmentType AS typeA, b.experienceId AS expB, b.employmentType AS typeB,
       CASE WHEN a.startDate > b.startDate THEN a.startDate ELSE b.startDate END AS overlapStart,
       CASE WHEN coalesce(a.endDate, $asOf) < coalesce(b.endDate, $asOf)
            THEN coalesce(a.endDate, $asOf) ELSE coalesce(b.endDate, $asOf) END AS overlapEnd;

// CQ-18  Reverse search: OPEN jobs for which candidate $candidateId is SUITABLE.
// Columns: jobId, title, workMode, mandatoryMet
MATCH (j:Job {status: 'OPEN'})-[:REQUIRES_SKILL {priority: 'MANDATORY'}]->(ms:Skill)
WITH j, count(DISTINCT ms) AS nMand
MATCH (c:Candidate {candidateId: $candidateId})-[:MAKES_CLAIM]->(cl:SkillClaim {verificationStatus: 'VERIFIED'})
      -[:ABOUT_SKILL]->(s:Skill)<-[req:REQUIRES_SKILL {priority: 'MANDATORY'}]-(j)
WHERE cl.level >= req.minLevel
WITH j, nMand, c, count(DISTINCT s) AS nMet
WHERE nMet = nMand
OPTIONAL MATCH (j)-[:BASED_IN]->(jc:City)
OPTIONAL MATCH (c)-[av:AVAILABLE_ONSITE_IN]->(jc)
WITH j, nMet, CASE WHEN j.workMode = 'REMOTE' THEN coalesce(c.remoteAvailable, false) ELSE av IS NOT NULL END AS ok
WHERE ok
RETURN j.jobId AS jobId, j.title AS title, j.workMode AS workMode, nMet AS mandatoryMet
ORDER BY jobId;

// CQ-19  Skill gap: skills mandatory in OPEN jobs vs. number of candidates holding a
//        VERIFIED claim at any level (low supply = sourcing priority).
// Columns: skill, openJobsRequiring, verifiedHolders
MATCH (j:Job {status: 'OPEN'})-[:REQUIRES_SKILL {priority: 'MANDATORY'}]->(s:Skill)
WITH s, count(DISTINCT j) AS openJobsRequiring
OPTIONAL MATCH (s)<-[:ABOUT_SKILL]-(:SkillClaim {verificationStatus: 'VERIFIED'})<-[:MAKES_CLAIM]-(c:Candidate)
RETURN s.name AS skill, openJobsRequiring, count(DISTINCT c) AS verifiedHolders
ORDER BY verifiedHolders ASC, openJobsRequiring DESC, skill;


// =====================================================================
// Application history helper (used by baseline assertion C02/J01)
// Columns: applicationId, seq, attemptNo, type, at, recruiter
// =====================================================================
MATCH (c:Candidate {candidateId: $candidateId})-[:SUBMITTED]->(a:Application)-[:FOR_JOB]->(j:Job {jobId: $jobId}),
      (a)-[:HAS_EVENT]->(ev:ApplicationEvent)
OPTIONAL MATCH (ev)-[:PERFORMED_BY]->(r:Recruiter)
RETURN a.applicationId AS applicationId, ev.seq AS seq, ev.attemptNo AS attemptNo,
       ev.type AS type, ev.at AS at, r.name AS recruiter
ORDER BY ev.at;
