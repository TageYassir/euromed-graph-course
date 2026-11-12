// =====================================================================
// TalentBridge LPG — 02 Load data (baseline TP data + team extension)
// Idempotent: every node/relationship is MERGEd on a stable ID, so running
// this file twice leaves node and relationship counts unchanged (test V-09).
// Source of truth for the rows below: data/*.csv (same content).
// Rows tagged src:'EXT' are the team's synthetic extension (see data/assumptions.md).
// All people, companies and events are FICTIONAL.
// =====================================================================

// ---------- 1. Cities ----------
UNWIND [
  {id:'CITY-RABAT',      name:'Rabat',      country:'MA'},
  {id:'CITY-CASABLANCA', name:'Casablanca', country:'MA'},
  {id:'CITY-FEZ',        name:'Fez',        country:'MA'},
  {id:'CITY-MARRAKECH',  name:'Marrakech',  country:'MA'},
  {id:'CITY-TANGIER',    name:'Tangier',    country:'MA'},
  {id:'CITY-AGADIR',     name:'Agadir',     country:'MA'}
] AS r
MERGE (ci:City {cityId: r.id})
SET ci.name = r.name, ci.countryCode = r.country;

// ---------- 2. Skill categories & canonical skills ----------
UNWIND [
  {id:'S01', name:'Python',           cat:'Programming',              src:'TP'},
  {id:'S02', name:'Cypher',           cat:'Query language',           src:'TP'},
  {id:'S03', name:'Neo4j',            cat:'Graph database',           src:'TP'},
  {id:'S04', name:'Docker',           cat:'DevOps',                   src:'TP'},
  {id:'S05', name:'Machine Learning', cat:'AI',                       src:'TP'},
  {id:'S06', name:'SQL',              cat:'Query language',           src:'TP'},
  {id:'S07', name:'Java',             cat:'Programming',              src:'TP'},
  {id:'S08', name:'JavaScript',       cat:'Programming',              src:'TP'},
  {id:'S09', name:'RDF',              cat:'Knowledge representation', src:'TP'},
  {id:'S10', name:'Apache Spark',     cat:'Big data',                 src:'EXT'},
  {id:'S11', name:'SPARQL',           cat:'Query language',           src:'EXT'},
  {id:'S12', name:'TypeScript',       cat:'Programming',              src:'EXT'},
  {id:'S13', name:'Kubernetes',       cat:'DevOps',                   src:'EXT'},
  {id:'S14', name:'Pandas',           cat:'Data analysis',            src:'EXT'}
] AS r
MERGE (s:Skill {skillId: r.id})
SET s.name = r.name, s.source = r.src
MERGE (sc:SkillCategory {categoryId: 'CAT-' + toUpper(replace(r.cat, ' ', '-'))})
SET sc.name = r.cat
MERGE (s)-[:IN_CATEGORY]->(sc);

// ---------- 3. Aliases (canonical label is also registered as an alias) ----------
// key = toLower(trim(label)). Exact-key lookup only: no CONTAINS / prefix matching,
// so 'Java' can never reach 'JavaScript' and 'Spark' can never reach 'SPARQL'.
UNWIND [
  {s:'S01', label:'Python'}, {s:'S01', label:'Python 3'},
  {s:'S02', label:'Cypher'}, {s:'S02', label:'Neo4j Cypher'},
  {s:'S03', label:'Neo4j'},  {s:'S03', label:'Neo4j DB'},
  {s:'S04', label:'Docker'}, {s:'S04', label:'Docker Engine'},
  {s:'S05', label:'Machine Learning'}, {s:'S05', label:'ML'}, {s:'S05', label:'machine learning'},
  {s:'S06', label:'SQL'},    {s:'S06', label:'Structured Query Language'},
  {s:'S07', label:'Java'},   {s:'S07', label:'Java SE'},
  {s:'S08', label:'JavaScript'}, {s:'S08', label:'JS'},
  {s:'S09', label:'RDF'},    {s:'S09', label:'Resource Description Framework'},
  {s:'S10', label:'Apache Spark'}, {s:'S10', label:'Spark'},
  {s:'S11', label:'SPARQL'}, {s:'S11', label:'SPARQL 1.1'},
  {s:'S12', label:'TypeScript'}, {s:'S12', label:'TS'},
  {s:'S13', label:'Kubernetes'}, {s:'S13', label:'K8s'},
  {s:'S14', label:'Pandas'}, {s:'S14', label:'pandas library'}
] AS r
MATCH (s:Skill {skillId: r.s})
MERGE (a:Alias {key: toLower(trim(r.label))})
ON CREATE SET a.label = r.label
MERGE (a)-[:ALIAS_OF]->(s);

// Explicit "do-not-merge" assertions between look-alike skills (documentation + test V-05).
UNWIND [
  {a:'S07', b:'S08', reason:'Different languages despite shared prefix (Java vs JavaScript)'},
  {a:'S10', b:'S11', reason:'Spark (compute engine) is not SPARQL (RDF query language)'}
] AS r
MATCH (x:Skill {skillId: r.a}), (y:Skill {skillId: r.b})
MERGE (x)-[d:DISTINCT_FROM]->(y)
SET d.reason = r.reason;

// ---------- 4. Organizations ----------
UNWIND [
  {id:'O01', name:'Atlas Data Labs',        city:'CITY-RABAT',      src:'TP'},
  {id:'O02', name:'NorthStar Analytics',    city:'CITY-CASABLANCA', src:'TP'},
  {id:'O03', name:'GraphWorks',             city:'CITY-MARRAKECH',  src:'TP'},
  {id:'O04', name:'Maghreb Cloud Systems',  city:'CITY-CASABLANCA', src:'EXT'},
  {id:'O05', name:'Sahara Semantics',       city:'CITY-TANGIER',    src:'EXT'}
] AS r
MATCH (ci:City {cityId: r.city})
MERGE (o:Organization {orgId: r.id})
SET o.name = r.name, o.source = r.src
MERGE (o)-[:LOCATED_IN]->(ci);

// ---------- 5. Candidates, home city, work-location availability ----------
// remoteAvailable: true / false / null (= unknown, never defaulted to false).
UNWIND [
  {id:'C01', name:'Amina Idrissi', home:'CITY-RABAT',      remote:true,  onsite:['CITY-RABAT','CITY-CASABLANCA'], src:'TP'},
  {id:'C02', name:'Youssef Karim', home:'CITY-CASABLANCA', remote:true,  onsite:['CITY-CASABLANCA'],              src:'TP'},
  {id:'C03', name:'Sara Haddad',   home:'CITY-FEZ',        remote:true,  onsite:['CITY-FEZ'],                     src:'TP'},
  {id:'C04', name:'Omar Naji',     home:'CITY-RABAT',      remote:false, onsite:['CITY-RABAT'],                   src:'TP'},
  {id:'C05', name:'Lina Faris',    home:'CITY-MARRAKECH',  remote:true,  onsite:['CITY-MARRAKECH','CITY-RABAT'],  src:'TP'},
  {id:'C06', name:'Adam Benali',   home:'CITY-CASABLANCA', remote:false, onsite:['CITY-CASABLANCA'],              src:'TP'},
  {id:'C07', name:'Amina Idrissi', home:'CITY-TANGIER',    remote:true,  onsite:['CITY-TANGIER'],                 src:'EXT'},
  {id:'C08', name:'Karim Alaoui',  home:'CITY-CASABLANCA', remote:true,  onsite:['CITY-CASABLANCA','CITY-RABAT'], src:'EXT'},
  {id:'C09', name:'Nadia Bennani', home:'CITY-AGADIR',     remote:true,  onsite:['CITY-AGADIR'],                  src:'EXT'},
  {id:'C10', name:'Hamza Tazi',    home:'CITY-RABAT',      remote:false, onsite:['CITY-RABAT','CITY-CASABLANCA'], src:'EXT'}
] AS r
MATCH (home:City {cityId: r.home})
MERGE (c:Candidate {candidateId: r.id})
SET c.name = r.name, c.remoteAvailable = r.remote, c.source = r.src
MERGE (c)-[:LIVES_IN]->(home)
WITH c, r
UNWIND r.onsite AS cityId
MATCH (ci:City {cityId: cityId})
MERGE (c)-[:AVAILABLE_ONSITE_IN]->(ci);

// ---------- 6. Skill claims (reified: Candidate -> SkillClaim -> Skill) ----------
// level: 1 beginner, 2 intermediate, 3 advanced (DECLARED level).
// verificationStatus: VERIFIED | UNVERIFIED | REFUTED (verified false). No claim = unknown.
// Verification is copied from the source table; it is NEVER derived from employment.
UNWIND [
  {c:'C01', s:'S01', lvl:3, st:'VERIFIED',   src:'TP'},
  {c:'C01', s:'S03', lvl:3, st:'VERIFIED',   src:'TP'},
  {c:'C01', s:'S02', lvl:2, st:'VERIFIED',   src:'TP'},
  {c:'C01', s:'S04', lvl:1, st:'UNVERIFIED', src:'TP'},
  {c:'C02', s:'S01', lvl:2, st:'VERIFIED',   src:'TP'},
  {c:'C02', s:'S06', lvl:3, st:'VERIFIED',   src:'TP'},
  {c:'C02', s:'S04', lvl:3, st:'VERIFIED',   src:'TP'},
  {c:'C03', s:'S01', lvl:3, st:'VERIFIED',   src:'TP'},
  {c:'C03', s:'S05', lvl:3, st:'VERIFIED',   src:'TP'},
  {c:'C03', s:'S04', lvl:2, st:'UNVERIFIED', src:'TP'},
  {c:'C04', s:'S07', lvl:3, st:'VERIFIED',   src:'TP'},
  {c:'C04', s:'S08', lvl:2, st:'VERIFIED',   src:'TP'},
  {c:'C05', s:'S01', lvl:3, st:'VERIFIED',   src:'TP'},
  {c:'C05', s:'S09', lvl:3, st:'VERIFIED',   src:'TP'},
  {c:'C05', s:'S03', lvl:2, st:'UNVERIFIED', src:'TP'},
  {c:'C06', s:'S06', lvl:3, st:'VERIFIED',   src:'TP'},
  {c:'C06', s:'S08', lvl:3, st:'VERIFIED',   src:'TP'},
  {c:'C07', s:'S11', lvl:2, st:'VERIFIED',   src:'EXT'},
  {c:'C07', s:'S09', lvl:1, st:'VERIFIED',   src:'EXT'},
  {c:'C07', s:'S12', lvl:2, st:'UNVERIFIED', src:'EXT'},
  {c:'C08', s:'S01', lvl:2, st:'VERIFIED',   src:'EXT'},
  {c:'C08', s:'S10', lvl:3, st:'VERIFIED',   src:'EXT'},
  {c:'C08', s:'S14', lvl:3, st:'VERIFIED',   src:'EXT'},
  {c:'C08', s:'S06', lvl:2, st:'VERIFIED',   src:'EXT'},
  {c:'C08', s:'S02', lvl:2, st:'VERIFIED',   src:'EXT'},
  {c:'C08', s:'S13', lvl:1, st:'UNVERIFIED', src:'EXT'},
  {c:'C09', s:'S10', lvl:3, st:'UNVERIFIED', src:'EXT'},
  {c:'C09', s:'S01', lvl:3, st:'VERIFIED',   src:'EXT'},
  {c:'C09', s:'S06', lvl:2, st:'VERIFIED',   src:'EXT'},
  {c:'C09', s:'S08', lvl:2, st:'REFUTED',    src:'EXT'},
  {c:'C10', s:'S07', lvl:3, st:'VERIFIED',   src:'EXT'},
  {c:'C10', s:'S13', lvl:2, st:'VERIFIED',   src:'EXT'},
  {c:'C10', s:'S04', lvl:3, st:'VERIFIED',   src:'EXT'}
] AS r
MATCH (c:Candidate {candidateId: r.c}), (s:Skill {skillId: r.s})
MERGE (cl:SkillClaim {claimId: 'CL-' + r.c + '-' + r.s})
SET cl.level = r.lvl,
    cl.verificationStatus = r.st,
    cl.source = CASE r.src WHEN 'TP' THEN 'TalentBridge claims sheet (TP 6.3)' ELSE 'Team extension dataset' END
MERGE (c)-[:MAKES_CLAIM]->(cl)
MERGE (cl)-[:ABOUT_SKILL]->(s);

// ---------- 7. Work experiences (one node per employment period) ----------
// endDate null = ongoing (open-ended). employmentType documents overlap legitimacy.
UNWIND [
  {id:'E01', c:'C01', o:'O01', role:'Graph Developer',           type:'FULL_TIME', start:'2024-01-01', end:'2025-12-31', skills:['S01','S03','S02'], src:'TP'},
  {id:'E02', c:'C02', o:'O02', role:'Data Engineer',             type:'FULL_TIME', start:'2023-03-01', end:null,         skills:['S01','S06','S04'], src:'TP'},
  {id:'E03', c:'C03', o:'O02', role:'ML Intern',                 type:'INTERNSHIP',start:'2025-01-01', end:'2025-10-31', skills:['S01','S05'],       src:'TP'},
  {id:'E04', c:'C04', o:'O01', role:'Backend Developer',         type:'FULL_TIME', start:'2022-02-01', end:'2024-09-30', skills:['S07','S08'],       src:'TP'},
  {id:'E05', c:'C05', o:'O03', role:'KG Consultant',             type:'CONTRACT',  start:'2025-06-01', end:null,         skills:['S01','S09'],       src:'TP'},
  {id:'E06', c:'C06', o:'O02', role:'BI Analyst',                type:'FULL_TIME', start:'2024-06-01', end:null,         skills:['S06','S08'],       src:'TP'},
  {id:'E07', c:'C07', o:'O05', role:'Ontology Engineer',         type:'FULL_TIME', start:'2024-09-01', end:null,         skills:['S11','S09'],       src:'EXT'},
  {id:'E08', c:'C08', o:'O04', role:'Data Engineer',             type:'FULL_TIME', start:'2023-01-01', end:'2025-06-30', skills:['S10','S01','S06'], src:'EXT'},
  {id:'E09', c:'C08', o:'O05', role:'Freelance Data Consultant', type:'FREELANCE', start:'2024-03-01', end:'2024-12-31', skills:['S14','S01'],       src:'EXT'},
  {id:'E10', c:'C09', o:'O04', role:'Data Intern',               type:'INTERNSHIP',start:'2022-07-01', end:'2022-12-31', skills:['S01','S06'],       src:'EXT'},
  {id:'E11', c:'C10', o:'O01', role:'DevOps Engineer',           type:'FULL_TIME', start:'2023-05-01', end:null,         skills:['S04','S13','S07'], src:'EXT'}
] AS r
MATCH (c:Candidate {candidateId: r.c}), (o:Organization {orgId: r.o})
MERGE (e:WorkExperience {experienceId: r.id})
SET e.roleTitle = r.role,
    e.employmentType = r.type,
    e.startDate = date(r.start),
    e.endDate = CASE WHEN r.end IS NULL THEN null ELSE date(r.end) END,
    e.source = r.src
MERGE (c)-[:HAS_EXPERIENCE]->(e)
MERGE (e)-[:AT_ORGANIZATION]->(o)
WITH e, r
UNWIND r.skills AS sid
MATCH (s:Skill {skillId: sid})
MERGE (e)-[:USED_SKILL]->(s);

// ---------- 8. Projects inside experiences (for CQ-13 and finer evidence) ----------
UNWIND [
  {id:'P01', name:'Skills graph prototype',     exp:'E01', start:'2024-06-01', end:'2024-12-15', skills:['S01','S03','S02']},
  {id:'P02', name:'Clickstream batch pipeline', exp:'E08', start:'2023-04-01', end:'2023-12-31', skills:['S10','S01']},
  {id:'P03', name:'Ontology alignment toolkit', exp:'E07', start:'2025-02-01', end:'2025-08-31', skills:['S11','S09']}
] AS r
MATCH (c:Candidate)-[:HAS_EXPERIENCE]->(e:WorkExperience {experienceId: r.exp})
MERGE (p:Project {projectId: r.id})
SET p.name = r.name, p.startDate = date(r.start), p.endDate = date(r.end)
MERGE (p)-[:PART_OF]->(e)
MERGE (c)-[:WORKED_ON]->(p)
WITH p, r
UNWIND r.skills AS sid
MATCH (s:Skill {skillId: sid})
MERGE (p)-[:USED_SKILL]->(s);

// ---------- 9. Evidence links: claim -> experience/project (POTENTIAL evidence) ----------
// Rule: same candidate + same canonical skill. Creates a link, does NOT change
// verificationStatus (business rule 10: verification is never inferred from employment).
MATCH (c:Candidate)-[:MAKES_CLAIM]->(cl:SkillClaim)-[:ABOUT_SKILL]->(s:Skill),
      (c)-[:HAS_EXPERIENCE]->(e:WorkExperience)-[:USED_SKILL]->(s)
MERGE (cl)-[ev:EVIDENCED_BY]->(e)
SET ev.evidenceType = 'WORK_EXPERIENCE', ev.reviewStatus = 'POTENTIAL',
    ev.derivedBy = 'rule:same-candidate-experience-used-skill';

MATCH (c:Candidate)-[:MAKES_CLAIM]->(cl:SkillClaim)-[:ABOUT_SKILL]->(s:Skill),
      (c)-[:WORKED_ON]->(p:Project)-[:USED_SKILL]->(s)
MERGE (cl)-[ev:EVIDENCED_BY]->(p)
SET ev.evidenceType = 'PROJECT', ev.reviewStatus = 'POTENTIAL',
    ev.derivedBy = 'rule:same-candidate-project-used-skill';

// ---------- 10. Jobs ----------
// workMode: REMOTE | HYBRID | ONSITE. HYBRID and ONSITE have a BASED_IN city.
UNWIND [
  {id:'J01', title:'Graph Data Engineer',        o:'O01', mode:'HYBRID', city:'CITY-RABAT',      status:'OPEN',   src:'TP'},
  {id:'J02', title:'ML Engineer',                o:'O02', mode:'REMOTE', city:null,              status:'OPEN',   src:'TP'},
  {id:'J03', title:'Data Analyst',               o:'O02', mode:'ONSITE', city:'CITY-CASABLANCA', status:'OPEN',   src:'TP'},
  {id:'J04', title:'Knowledge Graph Specialist', o:'O03', mode:'REMOTE', city:null,              status:'CLOSED', src:'TP'},
  {id:'J05', title:'Big Data Engineer',          o:'O04', mode:'HYBRID', city:'CITY-CASABLANCA', status:'OPEN',   src:'EXT'},
  {id:'J06', title:'Platform Engineer',          o:'O04', mode:'ONSITE', city:'CITY-RABAT',      status:'OPEN',   src:'EXT'},
  {id:'J07', title:'Semantic Web Engineer',      o:'O05', mode:'REMOTE', city:null,              status:'OPEN',   src:'EXT'}
] AS r
MATCH (o:Organization {orgId: r.o})
MERGE (j:Job {jobId: r.id})
SET j.title = r.title, j.workMode = r.mode, j.status = r.status, j.source = r.src
MERGE (j)-[:PUBLISHED_BY]->(o)
WITH j, r WHERE r.city IS NOT NULL
MATCH (ci:City {cityId: r.city})
MERGE (j)-[:BASED_IN]->(ci);

// ---------- 11. Job requirements (relationship with properties) ----------
// MERGE on (job, skill) only => at most ONE active requirement per job/skill (test V-03).
UNWIND [
  {j:'J01', s:'S01', p:'MANDATORY', min:2}, {j:'J01', s:'S03', p:'MANDATORY', min:2},
  {j:'J01', s:'S02', p:'MANDATORY', min:2}, {j:'J01', s:'S04', p:'PREFERRED', min:1},
  {j:'J02', s:'S01', p:'MANDATORY', min:3}, {j:'J02', s:'S05', p:'MANDATORY', min:2},
  {j:'J02', s:'S04', p:'PREFERRED', min:2},
  {j:'J03', s:'S06', p:'MANDATORY', min:3}, {j:'J03', s:'S01', p:'PREFERRED', min:2},
  {j:'J04', s:'S09', p:'MANDATORY', min:2}, {j:'J04', s:'S03', p:'MANDATORY', min:2},
  {j:'J05', s:'S10', p:'MANDATORY', min:2}, {j:'J05', s:'S01', p:'MANDATORY', min:2},
  {j:'J05', s:'S06', p:'PREFERRED', min:2}, {j:'J05', s:'S13', p:'PREFERRED', min:1},
  {j:'J06', s:'S04', p:'MANDATORY', min:2}, {j:'J06', s:'S13', p:'MANDATORY', min:2},
  {j:'J06', s:'S07', p:'PREFERRED', min:2},
  {j:'J07', s:'S11', p:'MANDATORY', min:2}, {j:'J07', s:'S09', p:'MANDATORY', min:2},
  {j:'J07', s:'S12', p:'PREFERRED', min:1}
] AS r
MATCH (j:Job {jobId: r.j}), (s:Skill {skillId: r.s})
MERGE (j)-[req:REQUIRES_SKILL]->(s)
SET req.priority = r.p, req.minLevel = r.min;

// ---------- 12. Recruiters ----------
UNWIND [
  {id:'R01', name:'Meriem Lahlou', o:'O04'},
  {id:'R02', name:'Yassine Amrani', o:'O01'}
] AS r
MATCH (o:Organization {orgId: r.o})
MERGE (rc:Recruiter {recruiterId: r.id})
SET rc.name = r.name
MERGE (rc)-[:WORKS_FOR]->(o);

// ---------- 13. Applications (one case per candidate+job) and immutable events ----------
// type: APPLIED | WITHDRAWN | REAPPLIED | REVIEWED | REJECTED | REINSTATED
UNWIND [
  {id:'AEV01', c:'C01', j:'J01', at:'2026-09-01T09:00:00Z', type:'APPLIED',    by:null,  decision:null,        note:null},
  {id:'AEV02', c:'C02', j:'J01', at:'2026-09-02T10:30:00Z', type:'APPLIED',    by:null,  decision:null,        note:null},
  {id:'AEV03', c:'C02', j:'J01', at:'2026-09-04T11:00:00Z', type:'WITHDRAWN',  by:null,  decision:null,        note:null},
  {id:'AEV04', c:'C02', j:'J01', at:'2026-09-06T08:00:00Z', type:'REAPPLIED',  by:null,  decision:null,        note:null},
  {id:'AEV05', c:'C03', j:'J02', at:'2026-09-07T09:00:00Z', type:'APPLIED',    by:null,  decision:null,        note:null},
  {id:'AEV06', c:'C06', j:'J03', at:'2026-09-07T13:00:00Z', type:'APPLIED',    by:null,  decision:null,        note:null},
  {id:'AEV07', c:'C09', j:'J05', at:'2026-09-10T09:00:00Z', type:'APPLIED',    by:null,  decision:null,        note:null},
  {id:'AEV08', c:'C09', j:'J05', at:'2026-09-12T15:00:00Z', type:'WITHDRAWN',  by:null,  decision:null,        note:null},
  {id:'AEV09', c:'C09', j:'J05', at:'2026-09-20T10:00:00Z', type:'REAPPLIED',  by:null,  decision:null,        note:null},
  {id:'AEV10', c:'C10', j:'J06', at:'2026-09-11T09:00:00Z', type:'APPLIED',    by:null,  decision:null,        note:null},
  {id:'AEV11', c:'C10', j:'J06', at:'2026-09-15T14:00:00Z', type:'REJECTED',   by:'R01', decision:'REJECT',    note:'Kubernetes evidence unclear'},
  {id:'AEV12', c:'C10', j:'J06', at:'2026-09-18T11:00:00Z', type:'REINSTATED', by:'R02', decision:'REINSTATE', note:'Verified K8s claim found on E11'},
  {id:'AEV13', c:'C08', j:'J05', at:'2026-09-13T08:30:00Z', type:'APPLIED',    by:null,  decision:null,        note:null},
  {id:'AEV14', c:'C08', j:'J05', at:'2026-09-16T10:00:00Z', type:'REVIEWED',   by:'R01', decision:'SHORTLIST', note:null},
  {id:'AEV15', c:'C01', j:'J01', at:'2026-09-03T16:00:00Z', type:'REVIEWED',   by:'R02', decision:'SHORTLIST', note:null}
] AS r
MATCH (c:Candidate {candidateId: r.c}), (j:Job {jobId: r.j})
MERGE (a:Application {applicationId: 'APP-' + r.c + '-' + r.j})
MERGE (c)-[:SUBMITTED]->(a)
MERGE (a)-[:FOR_JOB]->(j)
MERGE (ev:ApplicationEvent {eventId: r.id})
SET ev.type = r.type, ev.at = datetime(r.at), ev.decision = r.decision, ev.note = r.note
MERGE (a)-[:HAS_EVENT]->(ev)
WITH ev, r WHERE r.by IS NOT NULL
MATCH (rc:Recruiter {recruiterId: r.by})
MERGE (ev)-[:PERFORMED_BY]->(rc);

// ---------- 14. Derived ordering: seq, attemptNo, NEXT chain (rebuilt on every run) ----------
// attemptNo = 1 + number of REAPPLIED events up to and including this one.
MATCH ()-[n:NEXT]->() DELETE n;

MATCH (a:Application)-[:HAS_EVENT]->(ev:ApplicationEvent)
WITH a, ev ORDER BY ev.at
WITH a, collect(ev) AS evs
UNWIND range(0, size(evs) - 1) AS i
WITH evs, i, evs[i] AS ev
SET ev.seq = i + 1,
    ev.attemptNo = 1 + size([x IN evs[0..i+1] WHERE x.type = 'REAPPLIED']);

MATCH (a:Application)-[:HAS_EVENT]->(ev:ApplicationEvent)
WITH a, ev ORDER BY ev.at
WITH a, collect(ev) AS evs
WHERE size(evs) > 1
UNWIND range(0, size(evs) - 2) AS i
WITH evs[i] AS e1, evs[i+1] AS e2
MERGE (e1)-[:NEXT]->(e2);
