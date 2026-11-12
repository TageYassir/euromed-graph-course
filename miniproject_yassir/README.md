# AI Knowledge Graph Analysis — Wikipedia Mini-Project

<p align="center">
  <strong>From Wikipedia articles to interconnected knowledge graphs</strong><br />
  <em>Article similarity · Entity relationships · Keyword co-occurrence · Network analysis</em>
</p>

## Overview

This project explores the **Artificial Intelligence (AI) domain** by collecting Wikipedia articles and transforming their content into three complementary knowledge graphs. It applies graph-analysis techniques to identify influential entities, discover communities, measure network structure, and examine relationships between important concepts and organizations.

The workflow follows:

```text
Seed topics
    ↓
Wikipedia BFS collection
    ↓
Article corpus (JSON)
    ↓
┌─────────────────────┬──────────────────────┬─────────────────────┐
│ Article similarity  │ Entity co-occurrence  │ Keyword co-occurrence│
└─────────────────────┴──────────────────────┴─────────────────────┘
    ↓
Graph statistics · Centrality · Community detection · Shortest paths
    ↓
Static visualizations · Interactive entity graph · CSV results
```

## Project objectives

- Collect a connected corpus of Wikipedia articles around AI-related topics.
- Represent the corpus through article, entity, and keyword graphs.
- Measure graph structure, connectivity, and clustering.
- Rank important entities with network-centrality measures.
- Detect groups of strongly connected entities using two community-detection algorithms.
- Explore shortest paths between prominent entities.
- Export visualizations and analysis results for further exploration.

## Data collection

The crawler starts from five seed articles and expands the corpus using **breadth-first search (BFS)** over Wikipedia links.

| Setting | Value |
|---|---:|
| Domain | Artificial Intelligence (AI) |
| Seed articles | Artificial intelligence, Machine learning, Deep learning, Neural network, Natural language processing |
| Articles collected | 200 |
| Average article text | 824 words |
| Maximum text retained per article | 1,000 words |
| Maximum links followed per article | 18 |
| Polite crawl delay | 0.35 seconds |
| Collection behavior | Resumable using cached JSON |

The collected corpus is stored in `data/wikipedia_articles.json`. The crawler can resume from this cached corpus when the notebook is run again, allowing the collection to continue expanding rather than starting from zero.

## Graph construction

The notebook constructs three graphs from the same article corpus.

### 1. Article similarity graph

Each article is represented using **TF-IDF**. Cosine similarity is calculated between article representations, and an edge is created when the similarity is at least **0.12**.

This graph captures relationships between articles with similar textual content.

### 2. Entity co-occurrence graph

Named entities are extracted with **spaCy Named Entity Recognition (NER)**. The extraction includes the following entity categories:

- `PERSON` — people
- `ORG` — organizations
- `GPE` — geopolitical entities
- `PRODUCT` — products
- `WORK_OF_ART` — works of art
- `EVENT` — events

Entities are connected when they occur in the same sentence. The graph applies additional filtering: an entity must appear in at least **two articles**, and retained nodes must have a degree of at least **two**.

This graph is used for the centrality, community-detection, and shortest-path analyses.

### 3. Keyword co-occurrence graph

The keyword graph is built from alphabetic tokens that:

- contain at least four characters;
- are not stop words;
- co-occur within a sliding window of five tokens.

Edges are retained when their co-occurrence weight is at least **five**. This graph provides a broader view of recurring terms and their local relationships across the corpus.

## Graph statistics

The recorded graph-construction results are:

| Graph | Nodes | Edges | Density |
|---|---:|---:|---:|
| Article similarity | 200 | 847 | 0.0426 |
| Entity co-occurrence | 435 | 1,431 | 0.0152 |
| Keyword co-occurrence | 13,370 | 90,845 | 0.001016 |

Additional structural measurements from the notebook:

| Metric | Article graph | Entity graph | Keyword graph |
|---|---:|---:|---:|
| Connected components | 31 | 4 | 1 |
| Largest connected component | 168 | 428 | 13,370 |
| Average degree | 8.4700 | 6.5793 | 13.5894 |
| Diameter | 10 | 8 | Not calculated |
| Average clustering coefficient | 0.4141 | 0.5498 | 0.2067 |
| Average shortest path | 3.5757 | 3.6018 | Not calculated |

The diameter and average shortest path were skipped for the keyword graph because of its size. The graph is connected, but those metrics were not calculated in the notebook.

## Network analysis

### Centrality analysis

The entity graph is analyzed using four centrality measures:

- **PageRank:** estimates entity importance based on the structure of its connections.
- **Betweenness centrality:** measures how often an entity lies on shortest paths between other entities.
- **Degree centrality:** measures the proportion of other nodes directly connected to an entity.
- **Closeness centrality:** measures how close an entity is to the other nodes in the network.

#### Top five entities by PageRank

| Entity | Detected type | PageRank |
|---|---|---:|
| Google | ORG | 0.0321 |
| the United States | GPE | 0.0170 |
| OpenAI | GPE | 0.0148 |
| China | GPE | 0.0131 |
| U.S. | GPE | 0.0123 |

The entity-type labels above reproduce the NER output from this run. Automated NER labels can contain classification errors; for example, **OpenAI is labeled `GPE` in the recorded results**. The labels should therefore be interpreted as extracted model output rather than manually verified categories.

### Entity types detected

| Entity type | Count |
|---|---:|
| ORG | 172 |
| PERSON | 118 |
| GPE | 112 |
| WORK_OF_ART | 15 |
| PRODUCT | 11 |
| EVENT | 7 |
| **Total** | **435** |

### Community detection

Two community-detection methods are applied to the entity graph:

| Algorithm | Communities detected |
|---|---:|
| Greedy modularity | 19 |
| Louvain | 17 |

The notebook also ranks entities within the largest communities using their PageRank scores, helping identify prominent entities in each group.

### Shortest-path analysis

The project examines paths between prominent entities in the entity graph. In the recorded run, the **average shortest-path length between the selected top entities is 1.33**.

For example, the notebook identifies direct links between Google and several high-ranking entities, while other relationships are connected through intermediate nodes such as Gemini or PDF.

## Visualizations and exported results

The project produces static and interactive outputs to make the graph structure and analysis easier to explore.

| Output | Description |
|---|---|
| `outputs/miniproject_dashboard.png` | Static analysis dashboard generated by the visualization module |
| `outputs/miniproject_interactive.html` | Interactive entity graph for browser-based exploration |
| `outputs/plot_1_network.png` | Entity network, with nodes colored by Louvain community and sized by PageRank |
| `outputs/plot_2_degree_dist.png` | Degree distribution of the entity graph |
| `outputs/plot_3_top_pagerank.png` | Top 15 entities ranked by PageRank |
| `outputs/plot_4_community_sizes.png` | Largest Louvain communities by size |
| `outputs/entity_centrality_results.csv` | Entity centrality measures and detected entity types |
| `data/wikipedia_articles.json` | Cached Wikipedia article corpus |

The notebook's network visualization filters out entity-graph edges with a weight below two to reduce visual clutter. Its node sizes are based on PageRank, and node colors represent Louvain community membership.

## Technology stack

The notebook and its analysis use the following tools and libraries:

- **Python 3.9** — notebook runtime recorded in the uploaded project.
- **Jupyter Notebook** — interactive execution and analysis.
- **NetworkX** — graph construction and network analysis.
- **pandas** — tabular data handling and result export.
- **NumPy** — numerical operations.
- **scikit-learn** — TF-IDF vectorization and cosine similarity.
- **spaCy** — named-entity recognition.
- **Matplotlib** — static charts and network visualizations.
- **PyVis** — interactive graph visualization.

The crawler and the `src` modules are part of the project implementation. Use the dependency versions and spaCy model configured by the project when setting up a fresh environment.

## Project structure

The notebook expects to run from a project directory containing a `src/` folder. The following is the project layout referenced by the notebook and its generated artifacts:

```text
miniproject_yassir/
│
├── data/
│   └── wikipedia_articles.json
│
├── notebooks/
│   └── miniproject.ipynb
│
├── outputs/
│   ├── entity_centrality_results.csv
│   ├── miniproject_dashboard.png
│   ├── miniproject_interactive.html
│   ├── plot_1_network.png
│   ├── plot_2_degree_dist.png
│   ├── plot_3_top_pagerank.png
│   └── plot_4_community_sizes.png
│
├── src/
│   ├── config.py
│   ├── crawl.py
│   ├── graphs.py
│   ├── analysis.py
│   └── viz.py
│
└── README.md
```

## Running the project

### 1. Clone the repository

```bash
git clone <repository-url>
cd miniproject_yassir
```

### 2. Create and activate a virtual environment

```bash
# Create virtual environment
python -m venv .venv

# Activate (Windows)
.venv\Scripts\activate

# Install all dependencies
pip install -r requirements.txt

# Launch Jupyter
jupyter notebook
```

### 3. Install the project dependencies

Install the packages required by the project modules. The main libraries used by the notebook include:

```bash
pip install jupyter pandas numpy networkx scikit-learn spacy matplotlib pyvis
```

Also install the spaCy language model configured in the project's source code. Exact dependency and model versions should follow the repository's environment or requirements file, where available.

### 4. Run the notebook

Open the notebook from the project root:

```bash
jupyter notebook notebooks/miniproject.ipynb
```

Run the cells in order. The notebook locates the project root by searching for the `src/` directory, creates the `data/` and `outputs/` directories when needed, and imports the project modules.

The crawler uses the cached article JSON when available. After collection and graph construction, the remaining cells perform the analysis and generate the visualizations and exported files.

## Validation

The final notebook cell checks that:

- at least 150 articles have been collected;
- the entity graph is not empty;
- the centrality CSV has been saved;
- the dashboard image has been saved;
- the interactive HTML graph has been saved;
- the cached article corpus exists.

The recorded notebook run passed all six checks.

## Notes on reproducibility

Graph statistics and community membership depend on the collected corpus, source configuration, filtering thresholds, and analysis run. Re-running the crawler or changing graph-construction parameters can therefore change the results.

**Community-size consistency:** the summary supplied with this README reports the five largest Louvain communities as `[74, 54, 48, 47, 43]`, while the saved notebook output in the community-detection section reports `[56, 55, 46, 45, 37]`. The total number of Louvain communities is 17 in both records. Re-run the community-detection cell and update the reported sizes from the same execution before using those figures in a final report.

---

*AI Knowledge Graph Analysis — Wikipedia Mini-Project*
