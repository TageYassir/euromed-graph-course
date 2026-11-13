# TalentBridge — Skills–Jobs–Profiles Property Graph (team-XX)

Labeled property graph (Neo4j 5 / Cypher) for a fictional recruiting platform: candidates, verified vs. unverified skill claims, evidence, work history, jobs with mandatory/preferred requirements, geography, and append-only application history. Includes the schema evolution for proficiency-over-time assessments.

> Replace `XX` with your team number before zipping. All data is synthetic.

## Repository map

| Path | Content |
|---|---|
| `report.md` | Main report (read this first) |
| `requirements-and-cqs.md` | Requirements, CQ analysis matrix, rewritten CQs, "suitable", 3 new CQs, priorities |
| `modeling-decisions.md` | 13 decision records + answers to the discussion prompts |
| `schema-dictionary.md` | Labels, relationships, properties, IDs, constraints, time, normalisation, provenance |
| `graph-model.svg` / `.png` / `.mmd` | Physical LPG diagram (Mermaid source included) |
| `change-request-before-after.svg` / `.png` / `.mmd` | Before/after subgraph for C01 · Python |
| `data/*.csv` | Normalised source data (TP + team extension) |
| `data/assumptions.md` | Transformations, missing-value policy, tricky cases |
| `cypher/01_constraints_indexes.cypher` | 13 uniqueness constraints, 6 indexes (+ Enterprise existence constraints, commented) |
| `cypher/02_load_data.cypher` | Idempotent load (`MERGE` on stable IDs) |
| `cypher/03_cq_queries.cypher` | CQ-01…CQ-12, stretch CQ-13/15/16, team CQ-17/18/19 |
| `cypher/04_validation.cypher` | 10 baseline/edge assertions, 12 data-quality checks, EXPLAIN/PROFILE notes |
| `cypher/05_change_request.cypher` | Phase G evolution, migration, CQ-H1/H2 and test |
| `tools/run_all.py` | Optional runner: executes everything in order and prints results |

## How to run (fresh, empty Neo4j 5.x database)

**Neo4j Browser / Desktop / Aura:** enable *multi-statement query editor* in Browser settings, then paste and run the files in order `01 → 02 → 04 → 03 → 05`. Before `03`, set parameters, e.g.

```
:param candidateId => 'C01'
:param jobId => 'J01'
:param skillTerm => 'Python'
:param requiredTerm => 'Python'
:param preferredTerm => 'Docker'
:param minMet => 2
:param asOf => date('2026-11-12')
```

**cypher-shell:**
```bash
cypher-shell -u neo4j -p <pwd> -f cypher/01_constraints_indexes.cypher
cypher-shell -u neo4j -p <pwd> -f cypher/02_load_data.cypher
cypher-shell -u neo4j -p <pwd> -f cypher/04_validation.cypher
cypher-shell -u neo4j -p <pwd> -P "{candidateId:'C01', jobId:'J01', skillTerm:'Python', requiredTerm:'Python', preferredTerm:'Docker', minMet:2, asOf: date('2026-11-12')}" -f cypher/03_cq_queries.cypher
cypher-shell -u neo4j -p <pwd> -P "{candidateId:'C01', skillTerm:'Python', asOf: date('2026-11-12')}" -f cypher/05_change_request.cypher
```

**Python (one command):** `pip install neo4j && python tools/run_all.py bolt://localhost:7687 neo4j <pwd>` (wipes the target DB first, loads twice to prove idempotency, prints every result).

**Rerun check:** run `02_load_data.cypher` a second time and re-run test V-09: node/relationship counts are unchanged (149 nodes / 308 relationships before the change request).

## Expected test outcome

All 22 tests in `04_validation.cypher` return `passed = true`, and T-H1 in `05_change_request.cypher` returns `true`. See `report.md` §7 for the per-CQ expected results.
