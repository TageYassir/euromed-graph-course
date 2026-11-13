// =====================================================================
// TalentBridge LPG — 01 Constraints & indexes
// Target: Neo4j 5.x (Community or Enterprise). Run on a fresh database
// BEFORE 02_load_data.cypher. Every statement is idempotent (IF NOT EXISTS).
// =====================================================================

// ---------- Identity (uniqueness) constraints — Community edition OK ----------
// Stable business IDs, never display names (two candidates are called "Amina Idrissi").
CREATE CONSTRAINT candidate_id_unique IF NOT EXISTS
FOR (c:Candidate) REQUIRE c.candidateId IS UNIQUE;

CREATE CONSTRAINT skill_id_unique IF NOT EXISTS
FOR (s:Skill) REQUIRE s.skillId IS UNIQUE;

// An alias key (normalised lower-case text) may point to ONE canonical skill only.
// This is the database-level guard against "ML" silently resolving to two skills.
CREATE CONSTRAINT alias_key_unique IF NOT EXISTS
FOR (a:Alias) REQUIRE a.key IS UNIQUE;

CREATE CONSTRAINT skill_category_id_unique IF NOT EXISTS
FOR (sc:SkillCategory) REQUIRE sc.categoryId IS UNIQUE;

CREATE CONSTRAINT claim_id_unique IF NOT EXISTS
FOR (cl:SkillClaim) REQUIRE cl.claimId IS UNIQUE;

CREATE CONSTRAINT org_id_unique IF NOT EXISTS
FOR (o:Organization) REQUIRE o.orgId IS UNIQUE;

CREATE CONSTRAINT city_id_unique IF NOT EXISTS
FOR (ci:City) REQUIRE ci.cityId IS UNIQUE;

CREATE CONSTRAINT job_id_unique IF NOT EXISTS
FOR (j:Job) REQUIRE j.jobId IS UNIQUE;

CREATE CONSTRAINT experience_id_unique IF NOT EXISTS
FOR (e:WorkExperience) REQUIRE e.experienceId IS UNIQUE;

CREATE CONSTRAINT project_id_unique IF NOT EXISTS
FOR (p:Project) REQUIRE p.projectId IS UNIQUE;

CREATE CONSTRAINT application_id_unique IF NOT EXISTS
FOR (a:Application) REQUIRE a.applicationId IS UNIQUE;

CREATE CONSTRAINT app_event_id_unique IF NOT EXISTS
FOR (ev:ApplicationEvent) REQUIRE ev.eventId IS UNIQUE;

CREATE CONSTRAINT recruiter_id_unique IF NOT EXISTS
FOR (r:Recruiter) REQUIRE r.recruiterId IS UNIQUE;

// ---------- Existence / type constraints — ENTERPRISE edition only ----------
// Uncomment on Enterprise / Aura Professional. On Community, 04_validation.cypher
// runs equivalent checks (tests V-10..V-12).
// CREATE CONSTRAINT claim_level_exists IF NOT EXISTS
// FOR (cl:SkillClaim) REQUIRE cl.level IS NOT NULL;
// CREATE CONSTRAINT claim_level_type IF NOT EXISTS
// FOR (cl:SkillClaim) REQUIRE cl.level IS :: INTEGER;
// CREATE CONSTRAINT claim_status_exists IF NOT EXISTS
// FOR (cl:SkillClaim) REQUIRE cl.verificationStatus IS NOT NULL;
// CREATE CONSTRAINT event_at_exists IF NOT EXISTS
// FOR (ev:ApplicationEvent) REQUIRE ev.at IS NOT NULL;
// CREATE CONSTRAINT experience_start_type IF NOT EXISTS
// FOR (e:WorkExperience) REQUIRE e.startDate IS :: DATE;

// ---------- Secondary indexes ----------
// IDX-1: matching filters claims on verification status (CQ-02, CQ-03, CQ-09, CQ-12, CQ-15).
CREATE INDEX claim_status_idx IF NOT EXISTS
FOR (cl:SkillClaim) ON (cl.verificationStatus);

// IDX-2: CQ-04 / CQ-07 / CQ-15 start from open jobs.
CREATE INDEX job_status_idx IF NOT EXISTS
FOR (j:Job) ON (j.status);

// IDX-3: history queries order / range-filter on event timestamps (CQ-08, CQ-16).
CREATE INDEX app_event_at_idx IF NOT EXISTS
FOR (ev:ApplicationEvent) ON (ev.at);

// IDX-4: CQ-11 filters experiences by end date (recency window).
CREATE INDEX experience_end_idx IF NOT EXISTS
FOR (e:WorkExperience) ON (e.endDate);

// IDX-5: recruiter-facing search by display name (NOT an identity key: names are not unique).
CREATE INDEX candidate_name_idx IF NOT EXISTS
FOR (c:Candidate) ON (c.name);

// Relationship property index: requirement priority (CQ-02/03/04/12/15).
CREATE INDEX requires_priority_idx IF NOT EXISTS
FOR ()-[r:REQUIRES_SKILL]-() ON (r.priority);
