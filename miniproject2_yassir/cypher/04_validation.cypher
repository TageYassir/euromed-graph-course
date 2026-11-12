// ============================================================================
// Phase F: Validation & Quality Assertions
// ============================================================================

// ----------------------------------------------------------------------------
// Assertion 1: For J01, C01 meets its three mandatory skill requirements (Python, Neo4j, Cypher); C02 does not.
// ----------------------------------------------------------------------------
// Test C01 -> Should return 1 row
MATCH (j:Job {id: 'J01'})-[req:REQUIRE {mandatory: true}]->(s:Skill)
WITH j, count(s) AS total_mandatory
MATCH (c:Candidate {id: 'C01'})-[hs:HAS_SKILL]->(s:Skill)<-[req:REQUIRE {mandatory: true}]-(j)
WHERE hs.verification = 'Verified' AND hs.level >= req.minimum_level
WITH j, total_mandatory, c, count(s) AS candidate_matches
WHERE candidate_matches = total_mandatory
RETURN "Assertion 1a: C01 meets J01" AS TestResult, c.id AS CandidateID;

// Test C02 -> Should return 0 rows
MATCH (j:Job {id: 'J01'})-[req:REQUIRE {mandatory: true}]->(s:Skill)
WITH j, count(s) AS total_mandatory
MATCH (c:Candidate {id: 'C02'})-[hs:HAS_SKILL]->(s:Skill)<-[req:REQUIRE {mandatory: true}]-(j)
WHERE hs.verification = 'Verified' AND hs.level >= req.minimum_level
WITH j, total_mandatory, c, count(s) AS candidate_matches
WHERE candidate_matches = total_mandatory
RETURN "Assertion 1b: C02 meets J01" AS TestResult, c.id AS CandidateID;

// ----------------------------------------------------------------------------
// Assertion 2: For J02, C03 meets both mandatory skill requirements. C01 does not meet the Machine Learning requirement.
// ----------------------------------------------------------------------------
// Test C03 -> Should return 1 row
MATCH (j:Job {id: 'J02'})-[req:REQUIRE {mandatory: true}]->(s:Skill)
WITH j, count(s) AS total_mandatory
MATCH (c:Candidate {id: 'C03'})-[hs:HAS_SKILL]->(s:Skill)<-[req:REQUIRE {mandatory: true}]-(j)
WHERE hs.verification = 'Verified' AND hs.level >= req.minimum_level
WITH j, total_mandatory, c, count(s) AS candidate_matches
WHERE candidate_matches = total_mandatory
RETURN "Assertion 2a: C03 meets J02" AS TestResult, c.id AS CandidateID;

// Test C01 -> Should return 0 rows
MATCH (j:Job {id: 'J02'})-[req:REQUIRE {mandatory: true}]->(s:Skill)
WITH j, count(s) AS total_mandatory
MATCH (c:Candidate {id: 'C01'})-[hs:HAS_SKILL]->(s:Skill)<-[req:REQUIRE {mandatory: true}]-(j)
WHERE hs.verification = 'Verified' AND hs.level >= req.minimum_level
WITH j, total_mandatory, c, count(s) AS candidate_matches
WHERE candidate_matches = total_mandatory
RETURN "Assertion 2b: C01 meets J02" AS TestResult, c.id AS CandidateID;

// ----------------------------------------------------------------------------
// Assertion 3: For J03, C02 and C06 meet the mandatory SQL skill requirement AND satisfy the location criterion.
// ----------------------------------------------------------------------------
MATCH (j:Job {id: 'J03'})-[req:REQUIRE {mandatory: true}]->(s:Skill)
WITH j, count(s) AS total_mandatory
MATCH (c:Candidate)-[hs:HAS_SKILL]->(s:Skill)<-[req:REQUIRE {mandatory: true}]-(j)
WHERE c.id IN ['C02', 'C06'] AND hs.verification = 'Verified' AND hs.level >= req.minimum_level
WITH j, total_mandatory, c, count(s) AS candidate_matches
WHERE candidate_matches = total_mandatory
MATCH (j)-[:LOCATED_AT]->(city:City)
MATCH (c)-[:LIVES_IN|AVAILABLE_ONSITE_IN]->(city) // Check location constraint
RETURN "Assertion 3: C02 and C06 meet J03 skills and location" AS TestResult, c.id AS CandidateID, city.name AS JobCity;

// ----------------------------------------------------------------------------
// Assertion 4: For J04, C05's RDF claim is verified but Neo4j is unverified, so must NOT qualify.
// ----------------------------------------------------------------------------
// Test C05 -> Should return 0 rows
MATCH (j:Job {id: 'J04'})-[req:REQUIRE {mandatory: true}]->(s:Skill)
WITH j, count(s) AS total_mandatory
MATCH (c:Candidate {id: 'C05'})-[hs:HAS_SKILL]->(s:Skill)<-[req:REQUIRE {mandatory: true}]-(j)
WHERE hs.verification = 'Verified' AND hs.level >= req.minimum_level
WITH j, total_mandatory, c, count(s) AS candidate_matches
WHERE candidate_matches = total_mandatory
RETURN "Assertion 4: C05 meets J04" AS TestResult, c.id AS CandidateID;

// ----------------------------------------------------------------------------
// Assertion 5: For C02/J01, application history reveals Applied -> Withdrawn -> Reapplied in timestamp order.
// ----------------------------------------------------------------------------
MATCH (c:Candidate {id: 'C02'})-[:MADE_ACTION]->(ae:ApplicationEvent)-[:APPLIED_TO]->(j:Job {id: 'J01'})
RETURN c.name AS Candidate, j.id AS JobID, ae.event_type AS Event, ae.timestamp AS Timestamp
ORDER BY ae.timestamp ASC;

// ----------------------------------------------------------------------------
// Assertion 6: Search for canonical ML must handle alias ML; Java must not match JavaScript.
// ----------------------------------------------------------------------------
MATCH (a:Alias {name: 'ML'})-[:RESOLVES_TO]->(s:Skill)
RETURN "Assertion 6a: ML Alias Resolves to:" AS TestResult, s.canonical_label AS CanonicalSkill;

MATCH (s:Skill)
WHERE s.canonical_label CONTAINS 'Java'
RETURN "Assertion 6b: Java search separates Java and JavaScript" AS TestResult, s.id AS SkillID, s.canonical_label AS SkillLabel
ORDER BY s.canonical_label;

// ----------------------------------------------------------------------------
// Quality Check: Ensure no canonical skills have accidental duplicate IDs
// ----------------------------------------------------------------------------
MATCH (s:Skill)
WITH s.id AS ID, collect(s) AS nodes
WHERE size(nodes) > 1
RETURN "Warning: Duplicate Skill IDs found!" AS Status, ID, size(nodes) AS Count;

// ----------------------------------------------------------------------------
// Performance Check: Use EXPLAIN for CQ-04 to show Index usage
// ----------------------------------------------------------------------------
EXPLAIN MATCH (j:Job {status: 'Open'})-[req1:REQUIRE {mandatory: true}]->(s1:Skill {canonical_label: 'Python'})
MATCH (j)-[req2:REQUIRE {mandatory: false}]->(s2:Skill {canonical_label: 'Docker'})
MATCH (o:Organization)-[:POSTED]->(j)
RETURN j.id, j.title, o.name;