// ============================================================================
// Phase F: Competency Questions (CQ) Implementation
// ============================================================================

// ----------------------------------------------------------------------------
// CQ-01: What skills does a given candidate claim, and what is the proficiency level of each?
// Expected columns: Candidate, Skill, Level, Verification_Status
// Expected result: For C01, returns Python (3, Verified), Neo4j (3, Verified), Cypher (2, Verified), Docker (1, Unverified).
// Explanation: Matches the Candidate node to Skill nodes via the HAS_SKILL relationship and extracts the relationship properties.
// ----------------------------------------------------------------------------
MATCH (c:Candidate {id: 'C01'})-[hs:HAS_SKILL]->(s:Skill)
RETURN c.name AS Candidate, s.canonical_label AS Skill, hs.level AS Level, hs.verification AS Verification_Status;

// ----------------------------------------------------------------------------
// CQ-02: Which candidates possess all mandatory skills for a given job?
// Expected columns: JobID, CandidateID, CandidateName
// Expected result: For J01, returns C01 (meets Python, Neo4j, Cypher requirements). C02 is NOT returned (edge test).
// Explanation: Counts the total mandatory requirements for a job, then matches candidates whose verified skills meet or exceed the minimum level, comparing the count of their matched skills to the total required.
// ----------------------------------------------------------------------------
MATCH (j:Job {id: 'J01'})-[req:REQUIRE {mandatory: true}]->(req_skill:Skill)
WITH j, count(req_skill) AS total_mandatory
MATCH (c:Candidate)-[hs:HAS_SKILL]->(s:Skill)<-[req:REQUIRE {mandatory: true}]-(j)
WHERE hs.verification = 'Verified' AND hs.level >= req.minimum_level
WITH j, total_mandatory, c, count(s) AS candidate_matches
WHERE candidate_matches = total_mandatory
RETURN j.id AS JobID, c.id AS CandidateID, c.name AS CandidateName;

// ----------------------------------------------------------------------------
// CQ-03: Which candidates satisfy at least 2 of 3 mandatory skills for a job, and which mandatory skills are missing?
// Expected columns: CandidateName, MatchedCount, TotalMandatory, MissingSkills
// Expected result: For J01, C05 has Python and Neo4j but Neo4j is Unverified, so they might miss it. C09 has Python and Neo4j, missing Cypher.
// Explanation: Collects all mandatory skills for a job. Then collects the skills the candidate successfully matches. Uses list comprehension to find the difference (missing skills).
// ----------------------------------------------------------------------------
MATCH (j:Job {id: 'J01'})-[req:REQUIRE {mandatory: true}]->(s:Skill)
WITH j, collect(s.canonical_label) AS all_mandatory, count(s) AS total_mandatory
MATCH (c:Candidate)
OPTIONAL MATCH (c)-[hs:HAS_SKILL]->(ms:Skill)<-[req2:REQUIRE {mandatory: true}]-(j)
  WHERE hs.verification = 'Verified' AND hs.level >= req2.minimum_level
WITH j, all_mandatory, total_mandatory, c, collect(ms.canonical_label) AS matched_skills
WITH c, matched_skills, total_mandatory, all_mandatory,
     [skill IN all_mandatory WHERE NOT skill IN matched_skills] AS missing_skills
WHERE size(matched_skills) >= 2 AND size(missing_skills) > 0
RETURN c.name AS CandidateName, size(matched_skills) AS MatchedCount, total_mandatory AS TotalMandatory, missing_skills AS MissingSkills;

// ----------------------------------------------------------------------------
// CQ-04: Which open jobs require Python and prefer Docker?
// Expected columns: JobID, JobTitle, Organization
// Expected result: Returns J01 (Graph Data Engineer at Atlas Data Labs).
// Explanation: Traverses from open Jobs to Skills. Uses dual MATCH clauses to ensure the job REQUIREs Python (mandatory: true) and REQUIREs Docker (mandatory: false).
// ----------------------------------------------------------------------------
MATCH (j:Job {status: 'Open'})-[req1:REQUIRE {mandatory: true}]->(s1:Skill {canonical_label: 'Python'})
MATCH (j)-[req2:REQUIRE {mandatory: false}]->(s2:Skill {canonical_label: 'Docker'})
MATCH (o:Organization)-[:POSTED]->(j)
RETURN j.id AS JobID, j.title AS JobTitle, o.name AS Organization;

// ----------------------------------------------------------------------------
// CQ-05: What work experiences support a candidate's claim of a particular skill?
// Expected columns: CandidateName, Skill, Role, Organization, StartDate, EndDate
// Expected result: For C01 and Python, returns E01 (Graph Developer at Atlas Data Labs).
// Explanation: Traverses Candidate -> EXPERIENCED -> Experience -> LEARNED -> Skill to find practical evidence of skill usage.
// ----------------------------------------------------------------------------
MATCH (c:Candidate {id: 'C01'})-[hs:HAS_SKILL]->(s:Skill {canonical_label: 'Python'})
MATCH (c)-[:EXPERIENCED]->(e:Experience)-[:LEARNED]->(s)
MATCH (e)-[:OFFERED_BY]->(o:Organization)
RETURN c.name AS CandidateName, s.canonical_label AS Skill, e.role AS Role, o.name AS Organization, e.start_date AS StartDate, e.end_date AS EndDate;

// ----------------------------------------------------------------------------
// CQ-06: Which companies has a candidate worked for, in which roles, and during what periods?
// Expected columns: Candidate, Organization, Role, StartDate, EndDate
// Expected result: For C05, returns KG Consultant at GraphWorks and Freelance KG at FinTech Hub.
// Explanation: Direct traversal from Candidate to Experience, and from Experience to the offering Organization.
// ----------------------------------------------------------------------------
MATCH (c:Candidate {id: 'C05'})-[:EXPERIENCED]->(e:Experience)-[:OFFERED_BY]->(o:Organization)
RETURN c.name AS Candidate, o.name AS Organization, e.role AS Role, e.start_date AS StartDate, e.end_date AS EndDate
ORDER BY e.start_date DESC;

// ----------------------------------------------------------------------------
// CQ-07: Which candidates are suitable for remote jobs but not available for onsite work in the job's city?
// Expected columns: CandidateName, JobTitle, JobCity
// Expected result: C03 is remote_available but does not live in or have onsite availability in Casablanca for J03. 
// Explanation: Finds remote-eligible candidates, matches an onsite job, and uses a WHERE NOT EXISTS subquery to ensure the candidate has no LIVES_IN or AVAILABLE_ONSITE_IN links to the job's city.
// ----------------------------------------------------------------------------
MATCH (c:Candidate {remote_available: true})
MATCH (j:Job {mode: 'Onsite'})-[:LOCATED_AT]->(city:City)
WHERE NOT EXISTS {
  MATCH (c)-[:LIVES_IN|AVAILABLE_ONSITE_IN]->(city)
}
RETURN c.name AS CandidateName, j.title AS JobTitle, city.name AS JobCity;

// ----------------------------------------------------------------------------
// CQ-08: For each job, how many applicants applied, withdrew, or reapplied?
// Expected columns: JobID, JobTitle, EventType, EventCount
// Expected result: For J01, shows Applied: 3, Withdrawn: 2, Reapplied: 2.
// Explanation: Traverses ApplicationEvent to Job, groups by Job and Event Type, and counts the occurrences.
// ----------------------------------------------------------------------------
MATCH (ae:ApplicationEvent)-[:APPLIED_TO]->(j:Job)
RETURN j.id AS JobID, j.title AS JobTitle, ae.event_type AS EventType, count(ae) AS EventCount
ORDER BY j.id, EventType;

// ----------------------------------------------------------------------------
// CQ-09: Which candidate skill claims are unverified or lack evidence?
// Expected columns: Candidate, Skill, Level, Verification
// Expected result: Returns C01's Docker claim, C03's Docker claim, C05's Neo4j claim, C07's C++ claim, C10's Docker claim.
// Explanation: Simply filters the HAS_SKILL relationship property for 'Unverified'.
// ----------------------------------------------------------------------------
MATCH (c:Candidate)-[hs:HAS_SKILL]->(s:Skill)
WHERE hs.verification = 'Unverified'
RETURN c.name AS Candidate, s.canonical_label AS Skill, hs.level AS Level, hs.verification AS Verification;

// ----------------------------------------------------------------------------
// CQ-10: Which skill names/aliases resolve to one canonical skill, without confusing distinct skills?
// Expected columns: RawInput, CanonicalSkill
// Expected result: 'ML' maps to 'Machine Learning' (S05). 'Java SE' maps to 'Java' (S07), distinct from 'JavaScript' (S08).
// Explanation: Traverses from the Alias node through the RESOLVES_TO relationship to the definitive Skill node.
// ----------------------------------------------------------------------------
MATCH (a:Alias)-[:RESOLVES_TO]->(s:Skill)
RETURN a.name AS RawInput, s.canonical_label AS CanonicalSkill
ORDER BY CanonicalSkill;

// ----------------------------------------------------------------------------
// CQ-11: Which candidates have used Python in a job or project within the last 2 years?
// Expected columns: CandidateName, Role, EndDate
// Expected result: Returns candidates with experiences linked to Python where end_date > 2024-01-01 (or is null, meaning ongoing).
// Explanation: Filters the Experience start/end dates attached to the LEARNED relationship for Python.
// ----------------------------------------------------------------------------
MATCH (c:Candidate)-[:EXPERIENCED]->(e:Experience)-[:LEARNED]->(s:Skill {canonical_label: 'Python'})
WHERE e.end_date >= date('2024-01-01') OR e.end_date IS NULL
RETURN c.name AS CandidateName, e.role AS Role, coalesce(toString(e.end_date), 'Ongoing') AS EndDate;

// ----------------------------------------------------------------------------
// CQ-12: For a given candidate and job, explain the match: met mandatory requirements, unmet mandatory requirements, and matched preferred skills.
// Expected columns: Candidate, Job, MetMandatory, UnmetMandatory, MetPreferred
// Expected result: Provides arrays of skill names categorized by how C02 matches J01.
// Explanation: Complex query using pattern comprehensions and subqueries to evaluate and categorize skills dynamically for a specific Candidate/Job pair.
// ----------------------------------------------------------------------------
MATCH (c:Candidate {id: 'C02'}), (j:Job {id: 'J01'})
CALL {
    WITH c, j
    MATCH (j)-[req:REQUIRE {mandatory: true}]->(s:Skill)
    OPTIONAL MATCH (c)-[hs:HAS_SKILL]->(s) WHERE hs.verification = 'Verified' AND hs.level >= req.minimum_level
    RETURN collect(CASE WHEN hs IS NOT NULL THEN s.canonical_label END) AS met_mandatory,
           collect(CASE WHEN hs IS NULL THEN s.canonical_label END) AS unmet_mandatory
}
CALL {
    WITH c, j
    MATCH (j)-[req:REQUIRE {mandatory: false}]->(s:Skill)
    MATCH (c)-[hs:HAS_SKILL]->(s) WHERE hs.verification = 'Verified' AND hs.level >= req.minimum_level
    RETURN collect(s.canonical_label) AS met_preferred
}
RETURN c.name AS Candidate, j.title AS Job, met_mandatory AS MetMandatory, unmet_mandatory AS UnmetMandatory, met_preferred AS MetPreferred;