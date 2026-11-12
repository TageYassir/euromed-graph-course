// =====================================================================
// TalentBridge LPG — 04 Validation: baseline assertions (TP §8.1),
// data-quality checks (TP §8.2) and query-plan inspection.
// Every statement returns ONE row: test, passed (boolean), detail.
// Expected values live HERE (tests), never inside the CQ queries.
// =====================================================================

// ---------------- Baseline assertions (TP §8.1) ----------------

// A-1  J01: C01 meets all 3 mandatory skills; C02 does not.
MATCH (j:Job {jobId: 'J01'})-[:REQUIRES_SKILL {priority: 'MANDATORY'}]->(ms:Skill)
WITH j, count(ms) AS nMand
MATCH (j)-[req:REQUIRES_SKILL {priority: 'MANDATORY'}]->(s)<-[:ABOUT_SKILL]-(cl:SkillClaim {verificationStatus: 'VERIFIED'})<-[:MAKES_CLAIM]-(c:Candidate)
WHERE cl.level >= req.minLevel
WITH nMand, c, count(DISTINCT s) AS nMet
WITH collect(CASE WHEN nMet = nMand THEN c.candidateId END) AS full
RETURN 'A-1 J01 skill match: C01 yes, C02 no' AS test,
       ('C01' IN full AND NOT 'C02' IN full) AS passed, full AS detail;

// A-2  J02: C03 meets both mandatory skills; C01 fails Machine Learning.
MATCH (j:Job {jobId: 'J02'})-[:REQUIRES_SKILL {priority: 'MANDATORY'}]->(ms:Skill)
WITH j, count(ms) AS nMand
MATCH (j)-[req:REQUIRES_SKILL {priority: 'MANDATORY'}]->(s)<-[:ABOUT_SKILL]-(cl:SkillClaim {verificationStatus: 'VERIFIED'})<-[:MAKES_CLAIM]-(c:Candidate)
WHERE cl.level >= req.minLevel
WITH nMand, c, count(DISTINCT s) AS nMet, collect(s.name) AS metSkills
WITH collect(CASE WHEN nMet = nMand THEN c.candidateId END) AS full,
     collect(CASE WHEN c.candidateId = 'C01' THEN metSkills END) AS c01met
RETURN 'A-2 J02: C03 yes, C01 lacks Machine Learning' AS test,
       ('C03' IN full AND NOT 'C01' IN full
        AND NOT 'Machine Learning' IN coalesce(c01met[0], [])) AS passed, full AS detail;

// A-3  J03: C02 and C06 meet SQL and both satisfy the Casablanca onsite rule.
MATCH (j:Job {jobId: 'J03'})-[req:REQUIRES_SKILL {priority: 'MANDATORY'}]->(s)<-[:ABOUT_SKILL]-(cl:SkillClaim {verificationStatus: 'VERIFIED'})<-[:MAKES_CLAIM]-(c:Candidate)
WHERE cl.level >= req.minLevel
MATCH (j)-[:BASED_IN]->(jc:City)
OPTIONAL MATCH (c)-[av:AVAILABLE_ONSITE_IN]->(jc)
WITH collect(CASE WHEN av IS NOT NULL THEN c.candidateId END) AS skillAndLocation
RETURN 'A-3 J03: C02 and C06 meet SQL + location' AS test,
       ('C02' IN skillAndLocation AND 'C06' IN skillAndLocation) AS passed, skillAndLocation AS detail;

// A-4  J04: C05 does NOT meet all mandatory skills (Neo4j unverified); J04 is closed.
MATCH (j:Job {jobId: 'J04'})-[:REQUIRES_SKILL {priority: 'MANDATORY'}]->(ms:Skill)
WITH j, count(ms) AS nMand
MATCH (c:Candidate {candidateId: 'C05'})
OPTIONAL MATCH (j)-[req:REQUIRES_SKILL {priority: 'MANDATORY'}]->(s)<-[:ABOUT_SKILL]-(cl:SkillClaim {verificationStatus: 'VERIFIED'})<-[:MAKES_CLAIM]-(c)
WHERE cl.level >= req.minLevel
WITH j, nMand, count(DISTINCT s) AS nMet
RETURN 'A-4 J04: C05 not fully qualified, job closed' AS test,
       (nMet < nMand AND j.status = 'CLOSED') AS passed,
       'met ' + toString(nMet) + '/' + toString(nMand) + ', status ' + j.status AS detail;

// A-5  C02/J01 history is Applied -> Withdrawn -> Reapplied in timestamp order.
MATCH (:Candidate {candidateId: 'C02'})-[:SUBMITTED]->(a:Application)-[:FOR_JOB]->(:Job {jobId: 'J01'}),
      (a)-[:HAS_EVENT]->(ev:ApplicationEvent)
WITH ev ORDER BY ev.at
WITH collect(ev.type) AS seq
RETURN 'A-5 C02/J01 history order' AS test,
       seq = ['APPLIED', 'WITHDRAWN', 'REAPPLIED'] AS passed, seq AS detail;

// A-6  'ML' resolves to Machine Learning; 'Java' resolves to Java only (never JavaScript).
OPTIONAL MATCH (:Alias {key: toLower(trim('ML'))})-[:ALIAS_OF]->(ml:Skill)
OPTIONAL MATCH (:Alias {key: toLower(trim('Java'))})-[:ALIAS_OF]->(jv:Skill)
WITH collect(DISTINCT ml.name) AS mlHits, collect(DISTINCT jv.name) AS javaHits
RETURN 'A-6 alias ML->Machine Learning; Java !-> JavaScript' AS test,
       (mlHits = ['Machine Learning'] AND javaHits = ['Java']) AS passed,
       {ml: mlHits, java: javaHits} AS detail;

// A-7 (team)  'Spark' must not resolve to SPARQL; 'spark' resolves to Apache Spark.
OPTIONAL MATCH (:Alias {key: toLower(trim('Spark'))})-[:ALIAS_OF]->(s:Skill)
WITH collect(s.name) AS hits
RETURN 'A-7 alias Spark -> Apache Spark only' AS test, hits = ['Apache Spark'] AS passed, hits AS detail;

// A-8 (team)  Unverified mandatory claim: C09 (Spark UNVERIFIED) is not skill-qualified for J05; C08 is.
MATCH (j:Job {jobId: 'J05'})-[:REQUIRES_SKILL {priority: 'MANDATORY'}]->(ms:Skill)
WITH j, count(ms) AS nMand
MATCH (j)-[req:REQUIRES_SKILL {priority: 'MANDATORY'}]->(s)<-[:ABOUT_SKILL]-(cl:SkillClaim {verificationStatus: 'VERIFIED'})<-[:MAKES_CLAIM]-(c:Candidate)
WHERE cl.level >= req.minLevel
WITH nMand, c, count(DISTINCT s) AS nMet
WITH collect(CASE WHEN nMet = nMand THEN c.candidateId END) AS full
RETURN 'A-8 J05: C08 yes, C09 no (unverified Spark)' AS test,
       ('C08' IN full AND NOT 'C09' IN full) AS passed, full AS detail;

// A-9 (team)  Status reversal kept: C10/J06 = APPLIED, REJECTED, REINSTATED (nothing overwritten).
MATCH (:Candidate {candidateId: 'C10'})-[:SUBMITTED]->(a:Application)-[:FOR_JOB]->(:Job {jobId: 'J06'}),
      (a)-[:HAS_EVENT]->(ev:ApplicationEvent)
WITH ev ORDER BY ev.at
WITH collect(ev.type) AS seq
RETURN 'A-9 C10/J06 reversal history' AS test, seq = ['APPLIED', 'REJECTED', 'REINSTATED'] AS passed, seq AS detail;

// A-10 (team)  Duplicate display name, distinct identities.
MATCH (c:Candidate {name: 'Amina Idrissi'})
WITH collect(c.candidateId) AS ids
RETURN 'A-10 two Amina Idrissi with distinct IDs' AS test, size(ids) = 2 AS passed, ids AS detail;

// ---------------- Data-quality checks (TP §8.2) ----------------

// V-01  No duplicate canonical skill IDs or canonical names.
MATCH (s:Skill)
WITH count(s) AS n, count(DISTINCT s.skillId) AS nIds, count(DISTINCT toLower(s.name)) AS nNames
RETURN 'V-01 no duplicate skill IDs / names' AS test, (n = nIds AND n = nNames) AS passed,
       toString(n) + ' skills' AS detail;

// V-02  Every alias resolves to exactly one skill.
MATCH (a:Alias)
OPTIONAL MATCH (a)-[:ALIAS_OF]->(s:Skill)
WITH a, count(s) AS k
WITH collect(CASE WHEN k <> 1 THEN a.key END) AS bad
RETURN 'V-02 each alias -> exactly 1 skill' AS test, size(bad) = 0 AS passed, bad AS detail;

// V-03  No job has two requirement relationships for the same skill.
MATCH (j:Job)-[r:REQUIRES_SKILL]->(s:Skill)
WITH j, s, count(r) AS k
WITH collect(CASE WHEN k > 1 THEN j.jobId + '/' + s.skillId END) AS bad
RETURN 'V-03 one requirement per job/skill' AS test, size(bad) = 0 AS passed, bad AS detail;

// V-04  Every application event belongs to an application that has a candidate and a job.
MATCH (ev:ApplicationEvent)
OPTIONAL MATCH (c:Candidate)-[:SUBMITTED]->(a:Application)-[:HAS_EVENT]->(ev)
OPTIONAL MATCH (a)-[:FOR_JOB]->(j:Job)
WITH collect(CASE WHEN c IS NULL OR j IS NULL THEN ev.eventId END) AS orphans
RETURN 'V-04 no orphan application events' AS test, size(orphans) = 0 AS passed, orphans AS detail;

// V-05  DISTINCT_FROM skills never share an alias.
MATCH (x:Skill)-[:DISTINCT_FROM]-(y:Skill)
OPTIONAL MATCH (x)<-[:ALIAS_OF]-(a:Alias)-[:ALIAS_OF]->(y)
WITH collect(a.key) AS shared
RETURN 'V-05 look-alike skills share no alias' AS test, size(shared) = 0 AS passed, shared AS detail;

// V-06  Closed jobs have received no new (re)applications.
MATCH (j:Job {status: 'CLOSED'})
OPTIONAL MATCH (j)<-[:FOR_JOB]-(:Application)-[:HAS_EVENT]->(ev:ApplicationEvent)
WHERE ev.type IN ['APPLIED', 'REAPPLIED']
WITH collect(ev.eventId) AS bad
RETURN 'V-06 no applications to closed jobs' AS test, size(bad) = 0 AS passed, bad AS detail;

// V-07  Employment periods are well-formed (end >= start when present).
MATCH (e:WorkExperience)
WITH collect(CASE WHEN e.endDate IS NOT NULL AND e.endDate < e.startDate THEN e.experienceId END) AS bad
RETURN 'V-07 end >= start' AS test, size(bad) = 0 AS passed, bad AS detail;

// V-08  At most one claim per candidate and skill (v1 rule; relaxed by the change request).
MATCH (c:Candidate)-[:MAKES_CLAIM]->(cl:SkillClaim)-[:ABOUT_SKILL]->(s:Skill)
WITH c, s, count(cl) AS k
WITH collect(CASE WHEN k > 1 THEN c.candidateId + '/' + s.skillId END) AS bad
RETURN 'V-08 one claim per candidate/skill' AS test, size(bad) = 0 AS passed, bad AS detail;

// V-09  Rerun safety: snapshot of counts. Run 02_load_data.cypher again, rerun this test,
//       and compare: numbers must be identical.
MATCH (n)
WITH count(n) AS nodes
MATCH ()-[r]->()
WITH nodes, count(r) AS rels
RETURN 'V-09 count snapshot (compare before/after rerun)' AS test, true AS passed,
       'nodes=' + toString(nodes) + ', relationships=' + toString(rels) AS detail;

// V-10  Required properties present (Community-edition substitute for existence constraints).
MATCH (cl:SkillClaim)
WITH collect(CASE WHEN cl.level IS NULL OR NOT cl.level IN [1, 2, 3]
                    OR NOT cl.verificationStatus IN ['VERIFIED', 'UNVERIFIED', 'REFUTED'] THEN cl.claimId END) AS bad
RETURN 'V-10 claim level/status domain' AS test, size(bad) = 0 AS passed, bad AS detail;

// V-11  Job domain values and city rule (REMOTE has no city; HYBRID/ONSITE have exactly one).
MATCH (j:Job)
OPTIONAL MATCH (j)-[:BASED_IN]->(ci:City)
WITH j, count(ci) AS k
WITH collect(CASE WHEN NOT j.status IN ['OPEN', 'CLOSED']
                    OR (j.workMode = 'REMOTE' AND k <> 0)
                    OR (j.workMode IN ['HYBRID', 'ONSITE'] AND k <> 1)
                    OR NOT j.workMode IN ['REMOTE', 'HYBRID', 'ONSITE'] THEN j.jobId END) AS bad
RETURN 'V-11 job mode/status/city consistency' AS test, size(bad) = 0 AS passed, bad AS detail;

// V-12  Every event has a timestamp and a sequence number.
MATCH (ev:ApplicationEvent)
WITH collect(CASE WHEN ev.at IS NULL OR ev.seq IS NULL THEN ev.eventId END) AS bad
RETURN 'V-12 events timestamped and sequenced' AS test, size(bad) = 0 AS passed, bad AS detail;

// ---------------- Query plans (run manually in Neo4j Browser) ----------------
// P-1  CQ-02 entry point. Expect NodeUniqueIndexSeek on Job(jobId) thanks to job_id_unique.
//      Without the constraint the plan starts with NodeByLabelScan + Filter.
// EXPLAIN
// MATCH (j:Job {jobId: 'J01'})-[req:REQUIRES_SKILL {priority: 'MANDATORY'}]->(s)<-[:ABOUT_SKILL]-(cl:SkillClaim {verificationStatus: 'VERIFIED'})<-[:MAKES_CLAIM]-(c)
// WHERE cl.level >= req.minLevel RETURN c.candidateId, count(s);
//
// P-2  CQ-09 / CQ-04. Compare the plan when starting from claim status (claim_status_idx ->
//      NodeIndexSeek) vs. MATCH (c:Candidate)-->(cl) WHERE cl.verificationStatus <> 'VERIFIED'
//      (inequality cannot use the index: label scan). Rewrite option: test status IN
//      ['UNVERIFIED','REFUTED'] so the planner can seek.
// PROFILE
// MATCH (cl:SkillClaim) WHERE cl.verificationStatus IN ['UNVERIFIED', 'REFUTED']
// MATCH (c:Candidate)-[:MAKES_CLAIM]->(cl)-[:ABOUT_SKILL]->(s) RETURN c.candidateId, s.name;
