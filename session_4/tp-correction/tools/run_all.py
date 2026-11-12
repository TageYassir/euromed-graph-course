"""Run the TalentBridge scripts in order against a Neo4j 5 database and print results.

Usage:
    pip install neo4j
    python tools/run_all.py bolt://localhost:7687 neo4j <password> [database]

WARNING: step 0 wipes the target database (MATCH (n) DETACH DELETE n). Use a scratch DB.
"""
import re
import sys
from datetime import date
from pathlib import Path

from neo4j import GraphDatabase

ROOT = Path(__file__).resolve().parent.parent / "cypher"
PARAMS = {"candidateId": "C01", "jobId": "J01", "skillTerm": "Python", "requiredTerm": "Python",
          "preferredTerm": "Docker", "minMet": 2, "asOf": date(2026, 11, 12)}


def statements(path):
    """Split a .cypher file on ';' at end of line; drop comment-only chunks."""
    for chunk in re.split(r";\s*\n", path.read_text(encoding="utf-8")):
        body = "\n".join(l for l in chunk.splitlines() if not l.strip().startswith("//")).strip()
        if body:
            title = next((l.strip("/ ").strip() for l in chunk.splitlines()
                          if l.strip().startswith("//") and l.strip("/ ").strip()[:1] not in ("-", "=", "")), "")
            yield title, body


def run_file(session, name, show=False):
    print(f"\n===== {name} =====")
    for title, q in statements(ROOT / name):
        result = session.run(q, PARAMS)
        records = list(result)
        if show and records:
            print(f"\n-- {title}")
            print(" | ".join(records[0].keys()))
            for r in records:
                print(" | ".join(str(v) for v in r.values()))


def counts(session):
    n = session.run("MATCH (n) RETURN count(n) AS c").single()["c"]
    r = session.run("MATCH ()-[r]->() RETURN count(r) AS c").single()["c"]
    return n, r


def main():
    uri, user, pwd = sys.argv[1:4]
    db = sys.argv[4] if len(sys.argv) > 4 else None
    with GraphDatabase.driver(uri, auth=(user, pwd)) as driver, driver.session(database=db) as s:
        s.run("MATCH (n) DETACH DELETE n").consume()
        run_file(s, "01_constraints_indexes.cypher")
        run_file(s, "02_load_data.cypher")
        first = counts(s)
        run_file(s, "02_load_data.cypher")
        second = counts(s)
        print(f"\nRerun check (nodes, rels): {first} -> {second} :",
              "IDEMPOTENT" if first == second else "DUPLICATES CREATED")
        run_file(s, "03_cq_queries.cypher", show=True)
        run_file(s, "04_validation.cypher", show=True)
        run_file(s, "05_change_request.cypher", show=True)


if __name__ == "__main__":
    main()
