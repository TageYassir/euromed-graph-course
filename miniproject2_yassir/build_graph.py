"""
build_graph.py
==============
Builds the Candidate / Job / Skill knowledge graph in Neo4j from the CSV files,
following the schema diagram:

  Nodes
    Candidate     {id, name, remote_available}
    Skill         {id, canonical_label, category, known_aliases: [String]}
    Job_ads       {id, title, mode, status, starting_date, deadline}
    Organization  {id, name}
    Experience    {id, role}
    city          {name}

  Relationships
    (Candidate)-[:HAS_SKILL {level, verification, learned_at}]->(Skill)
    (Candidate)-[:EXPERIENCED {start_date, end_date}]->(Experience)
    (Experience)-[:LEARNED]->(Skill)
    (Experience)-[:OFFERED_BY]->(Organization)
    (Organization)-[:POSTED]->(Job_ads)
    (Organization)-[:LOCATED_AT]->(city)
    (Job_ads)-[:REQUIRE {mandatory, minimum_level}]->(Skill)
    (Job_ads)-[:AVAILABLE_ONSITE_IN]->(city)          (as drawn in the diagram)
    (Candidate)-[:LIVES_IN]->(city)
    (Candidate)-[:AVAILABLE_ONSITE_IN]->(city)        (needed by candidates.csv/CQ-07)
    (Candidate)-[:APPLIED | :WITHDRAWN | :REAPPLIED {timestamp, event_id}]->(Job_ads)

Differences vs. the old 02_load_data.cypher (because of the schema):
  * no :Alias nodes            -> aliases are an array property Skill.known_aliases
  * no :ApplicationEvent nodes -> events are relationships APPLIED/WITHDRAWN/REAPPLIED
  * :Job   -> :Job_ads ,  :City -> :city   (change JOB_LABEL / CITY_LABEL below to revert)
  * Experience dates live on the EXPERIENCED relationship (start_date / end_date)

Usage:   python build_graph.py
"""

import os
import re
import sys

import pandas as pd
from neo4j import GraphDatabase

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
URI = "neo4j://localhost:7687"
AUTH = ("neo4j", "12345678")
DATABASE = None  # None = default database

DATA_DIR = r"D:\EIDIA 5\Knowledge\VsCode_Knowledge\euromed-graph-course\miniproject2_yassir\data"
WIPE_FIRST = True   # delete everything before loading (clean rebuild)
BATCH_SIZE = 500

# Labels / relationship names taken from the schema diagram
JOB_LABEL = "Job_ads"
CITY_LABEL = "city"
JOB_CITY_REL = "AVAILABLE_ONSITE_IN"   # drawn Job_ads -> city in the diagram (LOCATED_AT is the other option)

EVENT_REL = {            # applications.csv event_type -> relationship type
    "APPLIED": "APPLIED",
    "WITHDRAWN": "WITHDRAWN",
    "REAPPLIED": "REAPPLIED",
}


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
def read_csv(name, required=()):
    path = os.path.join(DATA_DIR, name)
    df = pd.read_csv(path, dtype=str, keep_default_na=False)
    df.columns = [c.strip() for c in df.columns]
    for col in df.columns:
        df[col] = df[col].str.strip()
    df = df.replace({"": None})
    missing = [c for c in required if c not in df.columns]
    if missing:
        sys.exit(f"[ERROR] {name} is missing columns: {missing}. Found: {list(df.columns)}")
    return df


def clean(v):
    return None if v is None or (isinstance(v, float) and pd.isna(v)) else v


def records(df):
    return [{k: clean(v) for k, v in row.items()} for row in df.to_dict("records")]


def split_list(value):
    """'a, b;c|d' -> ['a','b','c','d'] (empty/None -> [])."""
    if value is None:
        return []
    return [p.strip() for p in re.split(r"[,;|]", value) if p.strip()]


def to_bool(value):
    if value is None:
        return None
    return str(value).strip().lower() in ("true", "1", "yes", "y", "t")


def to_int(value):
    try:
        return int(float(value)) if value is not None else None
    except ValueError:
        return None


def pick(df, *names):
    """Return the first column name that exists in df (for optional columns)."""
    for n in names:
        if n in df.columns:
            return n
    return None


def run_batches(session, query, rows, label=""):
    for i in range(0, len(rows), BATCH_SIZE):
        session.run(query, rows=rows[i:i + BATCH_SIZE]).consume()
    print(f"   {label or 'loaded'}: {len(rows)} rows")


# ----------------------------------------------------------------------------
# Constraints & indexes
# ----------------------------------------------------------------------------
def create_schema(session):
    print("Creating constraints & indexes ...")
    stmts = [
        "CREATE CONSTRAINT candidate_id_unique IF NOT EXISTS FOR (c:Candidate) REQUIRE c.id IS UNIQUE",
        "CREATE CONSTRAINT skill_id_unique IF NOT EXISTS FOR (s:Skill) REQUIRE s.id IS UNIQUE",
        f"CREATE CONSTRAINT job_id_unique IF NOT EXISTS FOR (j:`{JOB_LABEL}`) REQUIRE j.id IS UNIQUE",
        "CREATE CONSTRAINT org_id_unique IF NOT EXISTS FOR (o:Organization) REQUIRE o.id IS UNIQUE",
        "CREATE CONSTRAINT exp_id_unique IF NOT EXISTS FOR (e:Experience) REQUIRE e.id IS UNIQUE",
        f"CREATE CONSTRAINT city_name_unique IF NOT EXISTS FOR (ci:`{CITY_LABEL}`) REQUIRE ci.name IS UNIQUE",
        "CREATE INDEX skill_name_idx IF NOT EXISTS FOR (s:Skill) ON (s.canonical_label)",
        f"CREATE INDEX job_status_idx IF NOT EXISTS FOR (j:`{JOB_LABEL}`) ON (j.status)",
        "CREATE INDEX candidate_remote_idx IF NOT EXISTS FOR (c:Candidate) ON (c.remote_available)",
    ]
    for s in stmts:
        session.run(s).consume()


# ----------------------------------------------------------------------------
# Loaders
# ----------------------------------------------------------------------------
def load_cities(session, candidates, orgs, jobs):
    cities = set()
    for v in candidates["home_city"].dropna():
        cities.add(v)
    if "onsite_cities" in candidates.columns:
        for v in candidates["onsite_cities"].dropna():
            cities.update(split_list(v))
    if "city" in orgs.columns:
        cities.update(orgs["city"].dropna())
    if "onsite_city" in jobs.columns:
        cities.update(jobs["onsite_city"].dropna())

    q = f"UNWIND $rows AS r MERGE (:`{CITY_LABEL}` {{name: r.name}})"
    run_batches(session, q, [{"name": c} for c in sorted(cities)], "cities")


def load_skills(session, skills):
    rows = [{
        "id": r["skill_id"],
        "canonical_label": r["canonical_label"],
        "category": r.get("category"),
        "aliases": split_list(r.get("known_aliases")),
    } for r in records(skills)]
    q = """
    UNWIND $rows AS r
    MERGE (s:Skill {id: r.id})
    SET s.canonical_label = r.canonical_label,
        s.category        = r.category,
        s.known_aliases   = r.aliases
    """
    run_batches(session, q, rows, "skills")


def load_organizations(session, orgs):
    name_col = pick(orgs, "organization_name", "name")
    rows = [{"id": r["org_id"], "name": r[name_col], "city": r.get("city")} for r in records(orgs)]
    q1 = "UNWIND $rows AS r MERGE (o:Organization {id: r.id}) SET o.name = r.name"
    run_batches(session, q1, rows, "organizations")
    q2 = f"""
    UNWIND $rows AS r
    MATCH (o:Organization {{id: r.id}})
    MATCH (c:`{CITY_LABEL}` {{name: r.city}})
    MERGE (o)-[:LOCATED_AT]->(c)
    """
    run_batches(session, q2, [r for r in rows if r["city"]], "Organization-[:LOCATED_AT]->city")


def load_candidates(session, candidates):
    rows, onsite = [], []
    for r in records(candidates):
        rows.append({
            "id": r["candidate_id"],
            "name": r.get("name"),
            "remote": to_bool(r.get("remote_available")),
            "home_city": r.get("home_city"),
        })
        for city in split_list(r.get("onsite_cities")):
            onsite.append({"id": r["candidate_id"], "city": city})

    run_batches(session, """
        UNWIND $rows AS r
        MERGE (c:Candidate {id: r.id})
        SET c.name = r.name, c.remote_available = r.remote
    """, rows, "candidates")

    run_batches(session, f"""
        UNWIND $rows AS r
        MATCH (c:Candidate {{id: r.id}})
        MATCH (ci:`{CITY_LABEL}` {{name: r.home_city}})
        MERGE (c)-[:LIVES_IN]->(ci)
    """, [r for r in rows if r["home_city"]], "Candidate-[:LIVES_IN]->city")

    run_batches(session, f"""
        UNWIND $rows AS r
        MATCH (c:Candidate {{id: r.id}})
        MATCH (ci:`{CITY_LABEL}` {{name: r.city}})
        MERGE (c)-[:AVAILABLE_ONSITE_IN]->(ci)
    """, onsite, "Candidate-[:AVAILABLE_ONSITE_IN]->city")


def load_jobs(session, jobs):
    start_col = pick(jobs, "starting_date", "start_date", "starting date")
    dead_col = pick(jobs, "deadline")
    rows = [{
        "id": r["job_id"],
        "org_id": r.get("org_id"),
        "title": r.get("title"),
        "mode": r.get("mode"),
        "status": r.get("status"),
        "starting_date": r.get(start_col) if start_col else None,
        "deadline": r.get(dead_col) if dead_col else None,
        "city": r.get("onsite_city"),
    } for r in records(jobs)]

    run_batches(session, f"""
        UNWIND $rows AS r
        MERGE (j:`{JOB_LABEL}` {{id: r.id}})
        SET j.title = r.title, j.mode = r.mode, j.status = r.status,
            j.starting_date = date(r.starting_date),
            j.deadline      = date(r.deadline)
    """, rows, "jobs")

    run_batches(session, f"""
        UNWIND $rows AS r
        MATCH (o:Organization {{id: r.org_id}})
        MATCH (j:`{JOB_LABEL}` {{id: r.id}})
        MERGE (o)-[:POSTED]->(j)
    """, [r for r in rows if r["org_id"]], "Organization-[:POSTED]->job")

    run_batches(session, f"""
        UNWIND $rows AS r
        MATCH (j:`{JOB_LABEL}` {{id: r.id}})
        MATCH (c:`{CITY_LABEL}` {{name: r.city}})
        MERGE (j)-[:{JOB_CITY_REL}]->(c)
    """, [r for r in rows if r["city"]], f"job-[:{JOB_CITY_REL}]->city")


def load_experiences(session, exps):
    rows, learned = [], []
    for r in records(exps):
        rows.append({
            "id": r["experience_id"],
            "cand": r["candidate_id"],
            "org": r.get("org_id"),
            "role": r.get("role"),
            "start": r.get("start_date"),
            "end": r.get("end_date"),
        })
        for sid in split_list(r.get("skills_used")):
            learned.append({"id": r["experience_id"], "skill": sid})

    run_batches(session, """
        UNWIND $rows AS r
        MERGE (e:Experience {id: r.id})
        SET e.role = r.role
    """, rows, "experiences")

    run_batches(session, """
        UNWIND $rows AS r
        MATCH (c:Candidate {id: r.cand})
        MATCH (e:Experience {id: r.id})
        MERGE (c)-[x:EXPERIENCED]->(e)
        SET x.start_date = date(r.start),
            x.end_date   = date(r.end)
    """, rows, "Candidate-[:EXPERIENCED]->Experience")

    run_batches(session, """
        UNWIND $rows AS r
        MATCH (e:Experience {id: r.id})
        MATCH (o:Organization {id: r.org})
        MERGE (e)-[:OFFERED_BY]->(o)
    """, [r for r in rows if r["org"]], "Experience-[:OFFERED_BY]->Organization")

    run_batches(session, """
        UNWIND $rows AS r
        MATCH (e:Experience {id: r.id})
        MATCH (s:Skill {id: r.skill})
        MERGE (e)-[:LEARNED]->(s)
    """, learned, "Experience-[:LEARNED]->Skill")


def load_skill_claims(session, claims):
    learned_col = pick(claims, "learned_at", "learned_date")
    rows = [{
        "cand": r["candidate_id"],
        "skill": r["skill_id"],
        "level": to_int(r.get("level")),
        "verification": r.get("verification"),
        "learned_at": r.get(learned_col) if learned_col else None,
    } for r in records(claims)]
    run_batches(session, """
        UNWIND $rows AS r
        MATCH (c:Candidate {id: r.cand})
        MATCH (s:Skill {id: r.skill})
        MERGE (c)-[hs:HAS_SKILL]->(s)
        SET hs.level = r.level,
            hs.verification = r.verification,
            hs.learned_at = r.learned_at
    """, rows, "Candidate-[:HAS_SKILL]->Skill")


def load_job_requirements(session, reqs):
    rows = [{
        "job": r["job_id"],
        "skill": r["skill_id"],
        "mandatory": to_bool(r.get("mandatory")),
        "min": to_int(r.get("minimum_level")),
    } for r in records(reqs)]
    run_batches(session, f"""
        UNWIND $rows AS r
        MATCH (j:`{JOB_LABEL}` {{id: r.job}})
        MATCH (s:Skill {{id: r.skill}})
        MERGE (j)-[q:REQUIRE]->(s)
        SET q.mandatory = r.mandatory, q.minimum_level = r.min
    """, rows, "Job_ads-[:REQUIRE]->Skill")


def load_applications(session, apps):
    """event_type -> relationship type (APPLIED / WITHDRAWN / REAPPLIED)."""
    by_type = {}
    for r in records(apps):
        key = re.sub(r"[^A-Z]", "", (r.get("event_type") or "").upper())
        rel = EVENT_REL.get(key)
        if rel is None:
            print(f"   [WARN] unknown event_type {r.get('event_type')!r} (event {r.get('event_id')}) skipped")
            continue
        by_type.setdefault(rel, []).append({
            "event_id": r.get("event_id"),
            "cand": r["candidate_id"],
            "job": r["job_id"],
            "ts": r.get("timestamp"),
        })

    for rel, rows in by_type.items():
        # relationship types cannot be parameterised -> one query per type
        run_batches(session, f"""
            UNWIND $rows AS r
            MATCH (c:Candidate {{id: r.cand}})
            MATCH (j:`{JOB_LABEL}` {{id: r.job}})
            MERGE (c)-[a:{rel} {{event_id: r.event_id}}]->(j)
            SET a.timestamp = datetime(r.ts)
        """, rows, f"Candidate-[:{rel}]->Job_ads")


# ----------------------------------------------------------------------------
# Verification
# ----------------------------------------------------------------------------
def verify(session):
    print("\n=== Node counts ===")
    for rec in session.run("MATCH (n) RETURN labels(n)[0] AS label, count(*) AS n ORDER BY n DESC"):
        print(f"   {rec['label']:<14} {rec['n']}")
    print("\n=== Relationship counts ===")
    for rec in session.run("MATCH ()-[r]->() RETURN type(r) AS rel, count(*) AS n ORDER BY n DESC"):
        print(f"   {rec['rel']:<22} {rec['n']}")
    print("\nIn Neo4j Browser, run:  CALL db.schema.visualization()   to see the schema graph")
    print("or:  MATCH p=()-[]->() RETURN p LIMIT 300   to see the data graph.")


# ----------------------------------------------------------------------------
# Queries adapted to the schema (only the ones that change)
# ----------------------------------------------------------------------------
def adapt_labels(cypher):
    """Old queries -> new labels (:Job -> :Job_ads, :City -> :city)."""
    cypher = re.sub(r":Job\b(?!_)", f":{JOB_LABEL}", cypher)
    cypher = re.sub(r":City\b", f":{CITY_LABEL}", cypher)
    return cypher


ADAPTED_QUERIES = {
    "CQ-05": f"""
        MATCH (c:Candidate {{id: 'C01'}})-[:HAS_SKILL]->(s:Skill {{canonical_label: 'Python'}})
        MATCH (c)-[x:EXPERIENCED]->(e:Experience)-[:LEARNED]->(s)
        MATCH (e)-[:OFFERED_BY]->(o:Organization)
        RETURN c.name AS CandidateName, s.canonical_label AS Skill, e.role AS Role,
               o.name AS Organization, x.start_date AS StartDate, x.end_date AS EndDate""",
    "CQ-06": """
        MATCH (c:Candidate {id: 'C05'})-[x:EXPERIENCED]->(e:Experience)-[:OFFERED_BY]->(o:Organization)
        RETURN c.name AS Candidate, o.name AS Organization, e.role AS Role,
               x.start_date AS StartDate, x.end_date AS EndDate
        ORDER BY x.start_date DESC""",
    "CQ-07": f"""
        MATCH (c:Candidate {{remote_available: true}})
        MATCH (j:`{JOB_LABEL}` {{mode: 'Onsite'}})-[:{JOB_CITY_REL}]->(city:`{CITY_LABEL}`)
        WHERE NOT EXISTS {{ MATCH (c)-[:LIVES_IN|AVAILABLE_ONSITE_IN]->(city) }}
        RETURN c.name AS CandidateName, j.title AS JobTitle, city.name AS JobCity""",
    "CQ-08": f"""
        MATCH (c:Candidate)-[a:APPLIED|WITHDRAWN|REAPPLIED]->(j:`{JOB_LABEL}`)
        RETURN j.id AS JobID, j.title AS JobTitle, type(a) AS EventType, count(a) AS EventCount
        ORDER BY j.id, EventType""",
    "CQ-10": """
        MATCH (s:Skill)
        UNWIND s.known_aliases AS alias
        RETURN alias AS RawInput, s.canonical_label AS CanonicalSkill
        ORDER BY CanonicalSkill""",
    "CQ-11": """
        MATCH (c:Candidate)-[x:EXPERIENCED]->(e:Experience)-[:LEARNED]->(s:Skill {canonical_label: 'Python'})
        WHERE x.end_date >= date('2024-01-01') OR x.end_date IS NULL
        RETURN c.name AS CandidateName, e.role AS Role,
               coalesce(toString(x.end_date), 'Ongoing') AS EndDate""",
    "ASSERT-3": f"""
        MATCH (j:`{JOB_LABEL}` {{id: 'J03'}})-[req:REQUIRE {{mandatory: true}}]->(s:Skill)
        WITH j, count(s) AS total_mandatory
        MATCH (c:Candidate)-[hs:HAS_SKILL]->(s:Skill)<-[req:REQUIRE {{mandatory: true}}]-(j)
        WHERE c.id IN ['C02', 'C06'] AND hs.verification = 'Verified' AND hs.level >= req.minimum_level
        WITH j, total_mandatory, c, count(s) AS candidate_matches
        WHERE candidate_matches = total_mandatory
        MATCH (j)-[:{JOB_CITY_REL}]->(city:`{CITY_LABEL}`)
        MATCH (c)-[:LIVES_IN|AVAILABLE_ONSITE_IN]->(city)
        RETURN c.id AS CandidateID, city.name AS JobCity""",
    "ASSERT-5": f"""
        MATCH (c:Candidate {{id: 'C02'}})-[a:APPLIED|WITHDRAWN|REAPPLIED]->(j:`{JOB_LABEL}` {{id: 'J01'}})
        RETURN c.name AS Candidate, j.id AS JobID, type(a) AS Event, a.timestamp AS Timestamp
        ORDER BY a.timestamp ASC""",
    "ASSERT-6a": """
        MATCH (s:Skill) WHERE 'ML' IN s.known_aliases
        RETURN s.canonical_label AS CanonicalSkill""",
}
# CQ-01, 02, 03, 04, 09, 12 and assertions 1, 2, 4, 6b only need the label rename:
#   adapt_labels(old_query)


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
def main():
    print("Reading CSV files ...")
    candidates = read_csv("candidates.csv", ["candidate_id", "home_city"])
    skills = read_csv("skills.csv", ["skill_id", "canonical_label"])
    orgs = read_csv("organizations.csv", ["org_id"])
    jobs = read_csv("jobs.csv", ["job_id"])
    exps = read_csv("experiences.csv", ["experience_id", "candidate_id"])
    claims = read_csv("skill_claims.csv", ["candidate_id", "skill_id"])
    reqs = read_csv("job_requirements.csv", ["job_id", "skill_id"])
    apps = read_csv("applications.csv", ["candidate_id", "job_id", "event_type", "timestamp"])

    driver = GraphDatabase.driver(URI, auth=AUTH)
    driver.verify_connectivity()
    print("Connected to Neo4j.")

    with driver.session(database=DATABASE) as session:
        if WIPE_FIRST:
            session.run("MATCH (n) DETACH DELETE n").consume()
            print("Database wiped.")
        create_schema(session)

        print("Loading data ...")
        load_cities(session, candidates, orgs, jobs)
        load_skills(session, skills)
        load_organizations(session, orgs)
        load_candidates(session, candidates)
        load_jobs(session, jobs)
        load_experiences(session, exps)
        load_skill_claims(session, claims)
        load_job_requirements(session, reqs)
        load_applications(session, apps)

        verify(session)

    driver.close()
    print("\nDone.")


if __name__ == "__main__":
    main()