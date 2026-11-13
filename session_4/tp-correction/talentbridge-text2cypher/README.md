# Text2Cypher on the TalentBridge graph with Ollama

A 5-notebook teaching sequence that turns natural-language questions into Cypher queries with a **local LLM (Ollama)**, runs them on the **TalentBridge Neo4j graph** from the TP, evaluates the results and builds a grounded Q&A assistant. Every code cell comes after a markdown cell that explains **what it does**, **why it matters**, and often a question to discuss with students.

## Contents

| File | Purpose | Approx. class time |
|---|---|---|
| `01_setup_and_graph_tour.ipynb` | Install, connect, load the graph, **extract the schema** for the prompt, check Ollama | 30 min |
| `02_zero_shot_text2cypher.ipynb` | Prompt anatomy (schema + business rules + output rules), calling Ollama, extracting Cypher, failure-mode taxonomy | 45 min |
| `03_robust_text2cypher.ipynb` | Read-only guard, EXPLAIN, **entity linking**, **dynamic few-shot** (embeddings), **self-correction** loop, JSON structured output | 60 min |
| `04_evaluation.ipynb` | Benchmark of 22 questions with gold Cypher, **execution accuracy**, ablation of 4 systems, error analysis, model comparison | 45 min (+ run time) |
| `05_graph_qa_assistant.ipynb` | Grounded answers, **routing to trusted queries**, follow-up questions, **prompt injection** demo, Gradio UI, LangChain comparison | 45 min |
| `t2c.py` | The finished library. Notebooks 01–03 show its functions cell by cell (same source code); 04–05 import it | – |
| `benchmark.json` | 22 test questions + hand-checked gold Cypher, tagged by difficulty | – |
| `examples.json` | 14 few-shot examples, **disjoint** from the benchmark questions | – |
| `cypher/` | TP scripts used by the loader (constraints, data, change request) | – |

## Setup

1. **Neo4j 5.x** on an empty/scratch database (notebook 01 **wipes it**), for example:
   `docker run -p7474:7474 -p7687:7687 -e NEO4J_AUTH=neo4j/password neo4j:5`
2. **Ollama** running (`ollama serve`) with:
   ```bash
   ollama pull qwen2.5-coder:7b      # default chat model (~4.7 GB)
   ollama pull nomic-embed-text      # embeddings for example selection (~270 MB, optional)
   ```
3. Python ≥ 3.10, then `pip install neo4j ollama pandas matplotlib jupyter` (the first notebook cell does it too).
4. Settings are read from environment variables (or edit the config cell): `NEO4J_URI`, `NEO4J_USER`, `NEO4J_PASSWORD`, `NEO4J_DATABASE`, `OLLAMA_HOST`, `T2C_MODEL`, `T2C_EMBED_MODEL`.
5. Start Jupyter **from this folder** (the notebooks import `t2c.py` and read the JSON files with relative paths) and run the notebooks in order.

Optional for notebook 05: `pip install gradio langchain-neo4j langchain-ollama`.

## Teaching tips

* Run notebook 04 **before class** (5–15 min on a laptop with a 7B model); the results are saved to `results_<model>.csv`.
* LLM outputs vary between models and Ollama versions. The markdown cells give the **correct answers** so you can tell students whether a generated query is right, even when your model's output differs from what is described.
* Good live demos: the alias trap (02 Step 9), the ambiguous "Amina Idrissi" (03 Step 6), forced self-correction (03 Step 13), the trusted-query router (05 Step 7) and the prompt-injection demo (05 Step 9).
* Notebook 03 Step 3 shows that Neo4j itself refuses writes in a read transaction. In production, also connect with a database user that has the `reader` role.

## What was tested

Ollama and Neo4j couldn't be downloaded in the environment where this package was built. So:
* every non-LLM component (loader, schema extraction, entity linker, guard, extractor, evaluation metrics) and all 22 gold queries plus the 14 examples were executed on the real TalentBridge data, using an openCypher-compatible engine (FalkorDB) in place of Neo4j;
* **every code cell of all five notebooks was executed** in order with that engine and a *mock* LLM, to make sure they run end to end;
* the actual model outputs, accuracy numbers and latencies depend on your model and hardware: run the notebooks once with your setup before class.
