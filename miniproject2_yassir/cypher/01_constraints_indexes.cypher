// 1. Unique ID Constraints (Ensures no duplicate nodes are created)
CREATE CONSTRAINT candidate_id_unique FOR (c:Candidate) REQUIRE c.id IS UNIQUE;
CREATE CONSTRAINT skill_id_unique FOR (s:Skill) REQUIRE s.id IS UNIQUE;
CREATE CONSTRAINT job_id_unique FOR (j:Job) REQUIRE j.id IS UNIQUE;
CREATE CONSTRAINT org_id_unique FOR (o:Organization) REQUIRE o.id IS UNIQUE;
CREATE CONSTRAINT exp_id_unique FOR (e:Experience) REQUIRE e.id IS UNIQUE;
CREATE CONSTRAINT event_id_unique FOR (ae:ApplicationEvent) REQUIRE ae.id IS UNIQUE;
CREATE CONSTRAINT city_name_unique FOR (ci:City) REQUIRE ci.name IS UNIQUE;

// 2. Indexes for Query Performance
// Index on Skill canonical label for fast text-based skill lookups
CREATE INDEX skill_name_idx FOR (s:Skill) ON (s.canonical_label);

// Index on Job status to quickly filter open vs. closed jobs
CREATE INDEX job_status_idx FOR (j:Job) ON (j.status);

// Index on Candidate remote availability for CQ-07 filtering
CREATE INDEX candidate_remote_idx FOR (c:Candidate) ON (c.remote_available);