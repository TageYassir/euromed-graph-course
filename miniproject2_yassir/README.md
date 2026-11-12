# Candidate–Job–Skill Knowledge Graph (Neo4j)

A Neo4j knowledge graph that models candidates, their skills and work experience, job ads, the organizations that post them, and the full history of applications. It answers recruiting questions such as *"Which candidates meet all mandatory skills of a job?"* or *"Which skill claims are unverified?"* using Cypher.

Course project: Knowledge Graphs, EIDIA, UEMF (Euromed).
Author: Yassir Tagemouati

---

## 1. Graph schema

### Nodes

| Label | Properties |
|---|---|
| `Candidate` | `id`, `name`, `remote_available` (Boolean) |
| `Skill` | `id`, `canonical_label`, `category`, `known_aliases` (Array of String) |
| `Job_ads` | `id`, `title`, `mode`, `status`, `starting_date`, `deadline` |
| `Organization` | `id`, `name` |
| `Experience` | `id`, `role` |
| `city` | `name` |

### Relationships

| Relationship | Properties |
|---|---|
| `(Candidate)-[:HAS_SKILL]->(Skill)` | `level` (Integer), `verification` (`Verified` / `Unverified`), `learned_at` |
| `(Candidate)-[:EXPERIENCED]->(Experience)` | `start_date`, `end_date` |
| `(Experience)-[:LEARNED]->(Skill)` | none |
| `(Experience)-[:OFFERED_BY]->(Organization)` | none |
| `(Organization)-[:POSTED]->(Job_ads)` | none |
| `(Organization)-[:LOCATED_AT]->(city)` | none |
| `(Job_ads)-[:REQUIRE]->(Skill)` | `mandatory` (Boolean), `minimum_level` (Integer) |
| `(Job_ads)-[:AVAILABLE_ONSITE_IN]->(city)` | none (as drawn in the schema diagram) |
| `(Candidate)-[:LIVES_IN]->(city)` | none |
| `(Candidate)-[:AVAILABLE_ONSITE_IN]->(city)` | none |
| `(Candidate)-[:APPLIED \| :WITHDRAWN \| :REAPPLIED]->(Job_ads)` | `timestamp`, `event_id` |

### Modelling decisions

- **Skill aliases** are stored as an array on `Skill.known_aliases` (no separate alias nodes). This keeps `ML` and `Machine Learning` resolving to one canonical skill while `Java` and `JavaScript` stay distinct.
- **Application history** is modelled as three relationship types (`APPLIED`, `WITHDRAWN`, `REAPPLIED`) instead of event nodes. Ordering by `timestamp` reveals sequences such as Applied → Withdrawn → Reapplied.
- **Experience dates** live on the `EXPERIENCED` relationship.
- **Verification matters:** a skill only counts toward a job match when it is `Verified` and `level >= minimum_level`.

---

## 2. Project structure

```
project2_yassir/
├── data/
│   ├── applications.csv
│   ├── candidates.csv
│   ├── experiences.csv
│   ├── job_requirements.csv
│   ├── jobs.csv
│   ├── organizations.csv
│   ├── skill_claims.csv
│   └── skills.csv
├── cypher/                 # constraints, indexes, competency questions, assertions
├── build_graph.py          # builds the whole graph from the CSVs
├── main.ipynb              # runs the competency questions and tests
└── README.md
```

---

## 3. Input data

Column names expected by `build_graph.py`:

| File | Columns |
|---|---|
| `candidates.csv` | `candidate_id`, `name`, `home_city`, `onsite_cities` (comma-separated), `remote_available` |
| `skills.csv` | `skill_id`, `canonical_label`, `category`, `known_aliases` (comma-separated) |
| `organizations.csv` | `org_id`, `organization_name`, `city` |
| `jobs.csv` | `job_id`, `org_id`, `title`, `mode`, `status`, `onsite_city` (optional: `starting_date`, `deadline`) |
| `experiences.csv` | `experience_id`, `candidate_id`, `org_id`, `role`, `start_date`, `end_date`, `skills_used` (comma-separated skill ids) |
| `skill_claims.csv` | `candidate_id`, `skill_id`, `level`, `verification` (optional: `learned_at`) |
| `job_requirements.csv` | `job_id`, `skill_id`, `mandatory`, `minimum_level` |
| `applications.csv` | `event_id`, `candidate_id`, `job_id`, `event_type`, `timestamp` |

Dates use ISO format (`YYYY-MM-DD`). `event_type` must be `Applied`, `Withdrawn` or `Reapplied`.

---

## 4. Setup

### Requirements

- Neo4j 5.x (Desktop or Server) running locally
- Python 3.9+
- Python packages:

```bash
pip install neo4j pandas jupyter
```

### Configuration

Edit the top of `build_graph.py`:

```python
URI      = "neo4j://localhost:7687"
AUTH     = ("neo4j", "<your-password>")
DATA_DIR = r"<path-to>/project2_yassir/data"
WIPE_FIRST = True      # deletes the whole database before loading
```

Optional switches:

- `JOB_LABEL` / `CITY_LABEL`: node labels (`Job_ads` and `city` by default, matching the schema diagram)
- `JOB_CITY_REL`: relationship between a job and its city (`AVAILABLE_ONSITE_IN` by default; `LOCATED_AT` is a reasonable alternative)

---

## 5. Build the graph

```bash
python build_graph.py
```

The script:

1. Creates uniqueness constraints and indexes (`Candidate`, `Skill`, `Job_ads`, `Organization`, `Experience`, `city`; indexes on `Skill.canonical_label`, `Job_ads.status`, `Candidate.remote_available`)
2. Loads cities, skills, organizations, candidates, jobs, experiences, skill claims, job requirements and application events in batches
3. Prints node and relationship counts to confirm the load

`WIPE_FIRST = True` makes the build repeatable: you can re-run it at any time to get a clean graph.

### Quick check in Neo4j Browser

```cypher
CALL db.schema.visualization();

MATCH ()-[r]->() RETURN type(r) AS rel, count(*) AS n ORDER BY n DESC;

MATCH p=()-[]->() RETURN p LIMIT 300;
```

---

## 6. Competency questions

| ID | Question |
|---|---|
| CQ-01 | What skills does a candidate claim, and at what level? |
| CQ-02 | Which candidates have all mandatory skills for a job? |
| CQ-03 | Which candidates meet at least 2 of 3 mandatory skills, and which are missing? |
| CQ-04 | Which open jobs require Python and prefer Docker? |
| CQ-05 | Which work experiences support a candidate's skill claim? |
| CQ-06 | Which organizations has a candidate worked for, in which roles and periods? |
| CQ-07 | Which remote-capable candidates cannot work onsite in a job's city? |
| CQ-08 | How many applied / withdrawn / reapplied events does each job have? |
| CQ-09 | Which skill claims are unverified? |
| CQ-10 | Which aliases resolve to which canonical skill? |
| CQ-11 | Who used Python in the last 2 years? |
| CQ-12 | For a candidate and a job: met, unmet and preferred skills |

`build_graph.py` contains an `ADAPTED_QUERIES` dictionary with the versions of the queries that depend on the schema (CQ-05, 06, 07, 08, 10, 11 and assertions 3, 5, 6a). For the remaining queries, apply `adapt_labels()` to rename `:Job` to `:Job_ads` and `:City` to `:city`.

### Example: candidates with all mandatory skills for a job (CQ-02)

```cypher
MATCH (j:Job_ads {id: 'J01'})-[:REQUIRE {mandatory: true}]->(s:Skill)
WITH j, count(s) AS total_mandatory
MATCH (c:Candidate)-[hs:HAS_SKILL]->(s:Skill)<-[req:REQUIRE {mandatory: true}]-(j)
WHERE hs.verification = 'Verified' AND hs.level >= req.minimum_level
WITH j, total_mandatory, c, count(s) AS candidate_matches
WHERE candidate_matches = total_mandatory
RETURN j.id AS JobID, c.id AS CandidateID, c.name AS CandidateName;
```

---

## 7. Validation assertions

| # | Rule | Expected |
|---|---|---|
| 1 | For J01, C01 meets Python, Neo4j and Cypher; C02 does not | C01: 1 row, C02: 0 rows |
| 2 | For J02, C03 meets both mandatory skills; C01 misses Machine Learning | C03: 1 row, C01: 0 rows |
| 3 | For J03, C02 and C06 meet the SQL requirement and the location rule | both returned |
| 4 | For J04, C05's Neo4j claim is unverified, so C05 must not qualify | 0 rows |
| 5 | C02 / J01 history is Applied → Withdrawn → Reapplied in timestamp order | ordered events |
| 6 | `ML` resolves to Machine Learning; `Java` does not match `JavaScript` | verified |

Extra checks: no duplicate skill ids, and an `EXPLAIN` of CQ-04 to confirm index usage.

---

## 8. Troubleshooting

- **Nodes appear but no edges in Neo4j Explore:** the perspective only displays relationship types it knows about. Create a new perspective after loading, or enable all relationship types in the Relationships tab.
- **Old nodes (`ApplicationEvent`, `Alias`, `Job`) still present:** an earlier version of the model was loaded. Re-run `build_graph.py` with `WIPE_FIRST = True`.
- **`[WARN] unknown event_type`:** a row in `applications.csv` has an event type other than Applied, Withdrawn or Reapplied; it is skipped.
- **`missing columns` error:** the CSV header differs from the table in section 3. Rename the column or adjust the script.