// 1. Load Cities
LOAD CSV WITH HEADERS FROM 'file:///candidates.csv' AS row
MERGE (c:City {name: row.home_city})
WITH row
WHERE row.onsite_cities IS NOT NULL
UNWIND split(row.onsite_cities, ',') AS onsite_city
WITH trim(onsite_city) AS city_name
MERGE (c:City {name: city_name});

// 2. Load Candidates & City Links
LOAD CSV WITH HEADERS FROM 'file:///candidates.csv' AS row
MERGE (c:Candidate {id: row.candidate_id})
SET c.name = row.name,
    c.remote_available = toBoolean(row.remote_available)
WITH c, row
MATCH (city:City {name: row.home_city})
MERGE (c)-[:LIVES_IN]->(city)
WITH c, row
WHERE row.onsite_cities IS NOT NULL
UNWIND split(row.onsite_cities, ',') AS onsite_city
MATCH (avail_city:City {name: trim(onsite_city)})
MERGE (c)-[:AVAILABLE_ONSITE_IN]->(avail_city);

// 3. Load Canonical Skills & Aliases
LOAD CSV WITH HEADERS FROM 'file:///skills.csv' AS row
MERGE (s:Skill {id: row.skill_id})
SET s.canonical_label = row.canonical_label,
    s.category = row.category
WITH s, row
WHERE row.known_aliases IS NOT NULL
UNWIND split(row.known_aliases, ',') AS alias
MERGE (a:Alias {name: trim(alias)})
MERGE (a)-[:RESOLVES_TO]->(s);

// 4. Load Organizations & Locations
LOAD CSV WITH HEADERS FROM 'file:///organizations.csv' AS row
MERGE (o:Organization {id: row.org_id})
SET o.name = row.organization_name
MERGE (c:City {name: row.city})
MERGE (o)-[:LOCATED_AT]->(c);

// 5. Load Jobs, Organization Links, & Locations
LOAD CSV WITH HEADERS FROM 'file:///jobs.csv' AS row
MERGE (j:Job {id: row.job_id})
SET j.title = row.title,
    j.mode = row.mode,
    j.status = row.status
WITH j, row
MATCH (o:Organization {id: row.org_id})
MERGE (o)-[:POSTED]->(j)
WITH j, row
WHERE row.onsite_city IS NOT NULL
MERGE (c:City {name: row.onsite_city})
MERGE (j)-[:LOCATED_AT]->(c);

// 6. Load Experiences & Used Skills
LOAD CSV WITH HEADERS FROM 'file:///experiences.csv' AS row
MERGE (e:Experience {id: row.experience_id})
SET e.role = row.role,
    e.start_date = date(row.start_date)
WITH e, row
WHERE row.end_date IS NOT NULL
SET e.end_date = date(row.end_date)
WITH e, row
MATCH (c:Candidate {id: row.candidate_id})
MATCH (o:Organization {id: row.org_id})
MERGE (c)-[:EXPERIENCED]->(e)
MERGE (e)-[:OFFERED_BY]->(o)
WITH e, row
WHERE row.skills_used IS NOT NULL
UNWIND split(row.skills_used, ',') AS skill_id
MATCH (s:Skill {id: trim(skill_id)})
MERGE (e)-[:LEARNED]->(s);

// 7. Load Skill Claims (Proficiency & Verification)
LOAD CSV WITH HEADERS FROM 'file:///skill_claims.csv' AS row
MATCH (c:Candidate {id: row.candidate_id})
MATCH (s:Skill {id: row.skill_id})
MERGE (c)-[hs:HAS_SKILL]->(s)
SET hs.level = toInteger(row.level),
    hs.verification = row.verification;

// 8. Load Job Requirements
LOAD CSV WITH HEADERS FROM 'file:///job_requirements.csv' AS row
MATCH (j:Job {id: row.job_id})
MATCH (s:Skill {id: row.skill_id})
MERGE (j)-[req:REQUIRE]->(s)
SET req.mandatory = toBoolean(row.mandatory),
    req.minimum_level = toInteger(row.minimum_level);

// 9. Load Application Events
LOAD CSV WITH HEADERS FROM 'file:///applications.csv' AS row
MERGE (ae:ApplicationEvent {id: row.event_id})
SET ae.timestamp = datetime(row.timestamp),
    ae.event_type = row.event_type
WITH ae, row
MATCH (c:Candidate {id: row.candidate_id})
MATCH (j:Job {id: row.job_id})
MERGE (c)-[:MADE_ACTION]->(ae)
MERGE (ae)-[:APPLIED_TO]->(j);