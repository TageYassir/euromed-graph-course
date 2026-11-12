# src/config.py
"""Central configuration. Tweak here, not in the notebook."""

DOMAIN = "AI"                      # A/B/C/D/E

SEED_ARTICLES = [
    "Artificial intelligence",
    "Machine learning",
    "Deep learning",
    "Neural network",
    "Natural language processing",
]

TARGET_ARTICLES   = 200
MIN_ARTICLES      = 150
MAX_WORDS         = 1000
LINKS_PER_ARTICLE = 18              # inside the 15–20 window
CRAWL_DELAY_SEC   = 0.35            # polite rate
RANDOM_SEED       = 42

# Article similarity graph
TFIDF_SIM_THRESHOLD = 0.12
TFIDF_MAX_FEATURES  = 5000

# Entity graph
ENTITY_TYPES         = {"PERSON", "ORG", "GPE", "PRODUCT", "WORK_OF_ART", "EVENT"}
MIN_ARTICLES_PER_ENT = 2
MIN_DEGREE_ENT       = 2

# Keyword graph
KW_MIN_LEN       = 4
KW_WINDOW        = 5
KW_MIN_EDGE_W    = 5

# Paths
DATA_DIR    = "data"
OUTPUT_DIR  = "outputs"
ARTICLES_JSON = f"{DATA_DIR}/wikipedia_articles.json"