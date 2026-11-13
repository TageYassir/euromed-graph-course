# Requirements and Competency Questions (Phase A)

## 1. Requirements summary

| # | Stakeholder statement | Modeling consequence (traced in `modeling-decisions.md`) |
|---|---|---|
| BR-1 | Many candidates ↔ many skills; skills shared with jobs | One shared canonical `Skill` node (D-2) |
| BR-2 | Proficiency differs per person and skill | Level lives on the claim, not on Candidate or Skill (D-3) |
| BR-3 | Mandatory vs. preferred skills | `REQUIRES_SKILL {priority, minLevel}` (D-4) |
| BR-4 | Where and when a skill was used | `WorkExperience`/`Project` nodes with dates and `USED_SKILL` (D-6) |
| BR-5 | Multiple, overlapping, freelance employments | One node per employment period, `employmentType` (D-6) |
| BR-6 | Explain matched/missing required skills | Requirement-by-requirement traversal (CQ-12) |
| BR-7 | Aliases resolve; Java ≠ JavaScript | `Alias` nodes, exact normalised key, `DISTINCT_FROM` (D-9) |
| BR-8 | Remote vs. onsite city | `workMode`, `BASED_IN`, `AVAILABLE_ONSITE_IN`, `remoteAvailable` (D-7, D-8) |
| BR-9 | Apply / withdraw / reapply history | `Application` + immutable `ApplicationEvent` (D-10) |
| BR-10 | Claims vs. verified evidence | `SkillClaim.verificationStatus` + `EVIDENCED_BY` links (D-11, D-12) |

## 2. CQ analysis matrix

Shared vocabulary used below: **MET** = verified claim with level ≥ minLevel on the same canonical skill; **LOC-OK** = location rule of §4; **SUITABLE** = all mandatory MET ∧ LOC-OK.

| CQ | Business intent | Required graph facts | Likely traversal | Ambiguities (and our decision) | Validation test |
|---|---|---|---|---|---|
| CQ-01 | See a profile's skills at a glance | Candidate, claim, level, status, Skill | `(c)-[:MAKES_CLAIM]->(cl)-[:ABOUT_SKILL]->(s)` | Show unverified claims too? **Yes, with status column** | C01 → 4 rows incl. Docker 1 UNVERIFIED |
| CQ-02 | Shortlist candidates who pass the hard skill filter | Mandatory requirements, verified claims, levels | Count MET mandatory per candidate = total mandatory | Does geography belong here? **No** (TP: separate); reported as a column | J01 → only C01; C02 absent |
| CQ-03 | Near-misses worth a conversation | As CQ-02 + reason for each miss | All mandatory × all candidates, optional claim | "2 of 3" only works for 3-skill jobs → **rewritten** to `≥ $minMet` of N | J01 → C01 (3/3), C08 (2/3, missing Neo4j) |
| CQ-04 | Find jobs for a skill profile | Job status, requirement priority, aliases | Alias → Skill ← REQUIRES_SKILL ← open Job | "require" = mandatory, "prefer" = preferred | J01, J02; not J03 (Python preferred only) |
| CQ-05 | Justify a skill claim | Claim, EVIDENCED_BY, experience/project, org, dates | `(cl)-[:EVIDENCED_BY]->(e)` | Is evidence = verification? **No** | C01/Python → E01, P01; C01/Docker → none |
| CQ-06 | Work history | Experience, org, role, dates | `(c)-[:HAS_EXPERIENCE]->(e)-[:AT_ORGANIZATION]->(o)` | Open end → "ongoing" | C08 → E08, E09 (overlap kept) |
| CQ-07 | Remote-only talent pool per onsite job | remoteAvailable, onsite availability, job city | Open jobs with city × remote candidates not linked to that city | Remote jobs have no city → **rewritten**, see §3 | J01 → C02, C03, C07, C09; not C01, C05 |
| CQ-08 | Funnel statistics | Applications, event types | Job ← Application → events | Count events or people? **Distinct candidates** | J01 → applied 2, withdrew 1, reapplied 1 |
| CQ-09 | Data-quality / trust worklist | Status, evidence links | Claims with status ≠ VERIFIED or no EVIDENCED_BY | "Lack evidence" = no link at all | C05 Neo4j listed; C01 Python not listed |
| CQ-10 | Consistent skill vocabulary | Alias, Skill, DISTINCT_FROM | `(:Alias {key})-[:ALIAS_OF]->(s)` | Case/whitespace: normalised key; no fuzzy match | ML → S05; Java → S07 only; Py → none |
| CQ-11 | Recent hands-on experience | Experience/Project dates, USED_SKILL | `(c)-[:HAS_EXPERIENCE|WORKED_ON]->(x)-[:USED_SKILL]->(s)` | "Last 2 years" relative to what? → **rewritten**, see §3 | C01, C02, C03, C05, C08; not C09 (2022) |
| CQ-12 | Explainable match | All of CQ-02 + preferred + location | Each requirement + optional claim + outcome | What counts as a reason → NO_CLAIM / NOT_VERIFIED / LEVEL_TOO_LOW | C05/J04 → Neo4j unverified ⇒ reject |
| CQ-13* | Find graph-practitioners | Project, USED_SKILL, categories | Project → two skills of two categories | "Graph database" = category, RDF is *not* one | C01 / P01 only |
| CQ-15* | Hard-to-fill jobs | SUITABLE rule | Per job, set of SUITABLE candidates is empty | Closed jobs included but labelled | J04 (closed), J07 |
| CQ-16* | Recruiter accountability | Event, PERFORMED_BY, decision, timestamp | Recruiter ← event ← application | Review vs. decision: both are events | 4 rows, ordered by time |

(*) stretch CQs chosen: **CQ-13, CQ-15, CQ-16** (one more than required).

## 3. Rewritten ambiguous CQs

**CQ-07 (original):** "Which candidates are suitable for remote jobs but not available for onsite work in the job's city?" — A remote job has no city, so the question is self-contradictory.
**CQ-07 (rewritten):** *For every OPEN job whose work mode is HYBRID or ONSITE, list the candidates whose `remoteAvailable = true` and who have **no** `AVAILABLE_ONSITE_IN` link to that job's city. Output job, city, candidate and the cities where the candidate is available.* (Interpretation: the remote-only pool the employer would gain by opening the job to remote work.)

**CQ-11 (original):** "Which candidates have used Python in a job or project within the last 2 years?" — undefined reference date, and "within" can mean *started*, *ended*, or *overlapped*.
**CQ-11 (rewritten):** *Given a reference date `$asOf` (default 2026-11-12), list candidates having at least one WorkExperience or Project linked by `USED_SKILL` to the canonical skill resolved from `$skillTerm`, whose period overlaps `[asOf − 2 years, asOf]` (i.e. `start ≤ asOf` and `end is null or end ≥ asOf − 2y`). Verification status is not considered (this is usage, not proficiency).*

**CQ-03 (bonus rewrite):** *For job `$jobId` with N mandatory requirements, list candidates who MET at least `$minMet` (default 2) of them, with the met list and, for each missing one, the reason (no claim / unverified / refuted / level below minimum).*

## 4. Definition of "suitable"

A candidate is **SUITABLE** for a job iff both hard conditions hold:

1. **Skill rule (hard):** for *every* `MANDATORY` requirement of the job, the candidate has a `SkillClaim` on the same canonical skill with `verificationStatus = 'VERIFIED'` and `level ≥ minLevel`. Unverified, refuted, missing, or too-low claims fail.
2. **Location rule (hard, evaluated separately):** REMOTE job ⇒ `remoteAvailable = true`; HYBRID or ONSITE job ⇒ `(candidate)-[:AVAILABLE_ONSITE_IN]->(job city)`.

**Soft preferences** (`PREFERRED` requirements) never exclude anyone; they are reported as matched/unmatched for ranking and explanation. **Job status** is not part of suitability; a closed job is reported as "suitable but closed" and cannot receive applications.
Critique of the given rule: a hybrid job could reasonably accept a remote-available candidate who can travel occasionally; that would need a `maxOnsiteDaysPerWeek` attribute we do not have, so we apply the simplified TP rule consistently.

## 5. Three new competency questions

| ID | Question | Value for TalentBridge | Priority |
|---|---|---|---|
| CQ-17 | Which candidates have **overlapping employment periods**, and of what type (full-time vs. freelance)? | Separates legitimate parallel work from data-entry errors before a recruiter relies on the history | Should |
| CQ-18 | For a given candidate, **which open jobs are they SUITABLE for**? (reverse search) | Candidate-side recommendations and talent re-engagement; reuses the same rule as CQ-02 in the opposite direction | Must |
| CQ-19 | Which skills are **mandatory in open jobs but held (verified) by the fewest candidates**? | Sourcing priorities and verification backlog planning | Could |

## 6. Prioritisation

**Must:** CQ-01, 02, 03, 04, 05, 06, 09, 10, 12, 18 — **Should:** CQ-07, 08, 11, 16, 17 — **Could:** CQ-13, 15, 19.
The *Must* group is the core promise of the platform: find candidates by skills and explain *why*, which is impossible without trustworthy skill identity (CQ-10), the claim/evidence distinction (CQ-05, CQ-09) and the mandatory/preferred split (CQ-02/03/12). If any of these is wrong, a recruiter either excludes good candidates or shortlists unverified ones, which is both a quality and a fairness problem. Geography (CQ-07), funnel statistics (CQ-08) and recency (CQ-11) refine a search that already works, so they are *Should*. The stretch questions add analytics on top of the same patterns and do not drive any structural decision except `Project` (CQ-13) and `Recruiter` events (CQ-16).
