# src/graphs.py
"""All three graph builders live here."""
import re
import itertools
import numpy as np
import networkx as nx
from collections import Counter, defaultdict
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
import spacy

from . import config

# ---------- 2.1 Article similarity ----------
def build_article_graph(corpus: dict) -> nx.Graph:
    titles = list(corpus.keys())
    texts  = [corpus[t] for t in titles]

    vec = TfidfVectorizer(
        max_features=config.TFIDF_MAX_FEATURES,
        stop_words="english",
        ngram_range=(1, 2),
    )
    X = vec.fit_transform(texts)
    sim = cosine_similarity(X)

    G = nx.Graph()
    for i, t in enumerate(titles):
        G.add_node(t, words=len(texts[i].split()))

    for i, j in itertools.combinations(range(len(titles)), 2):
        s = float(sim[i, j])
        if s >= config.TFIDF_SIM_THRESHOLD:
            G.add_edge(titles[i], titles[j], weight=s)

    return G


# ---------- 2.2 Entity co-occurrence ----------
_NLP = None
def _nlp():
    global _NLP
    if _NLP is None:
        _NLP = spacy.load("en_core_web_sm", disable=["lemmatizer"])
    return _NLP

def build_entity_graph(corpus: dict) -> nx.Graph:
    nlp = _nlp()
    ent_articles = defaultdict(set)          # entity -> set of titles
    cooc         = Counter()                 # (ent_a, ent_b) -> weight
    ent_type     = {}                        # entity -> type

    for title, text in corpus.items():
        doc = nlp(text[:20_000])             # safety cap
        for sent in doc.sents:
            ents = []
            for e in sent.ents:
                if e.label_ in config.ENTITY_TYPES and len(e.text) > 2:
                    ents.append(e.text)
                    ent_articles[e.text].add(title)
                    ent_type.setdefault(e.text, e.label_)
            ents = sorted(set(ents))
            for a, b in itertools.combinations(ents, 2):
                cooc[(a, b)] += 1

    # filter: entity must appear in >= MIN_ARTICLES_PER_ENT articles
    kept = {e for e, arts in ent_articles.items()
            if len(arts) >= config.MIN_ARTICLES_PER_ENT}

    G = nx.Graph()
    for e in kept:
        G.add_node(e, type=ent_type[e], n_articles=len(ent_articles[e]))

    for (a, b), w in cooc.items():
        if a in kept and b in kept:
            G.add_edge(a, b, weight=w)

    # filter: degree >= MIN_DEGREE_ENT
    G.remove_nodes_from([n for n, d in G.degree() if d < config.MIN_DEGREE_ENT])
    return G

# ---------- 2.3 Keyword co-occurrence ----------
_TOKEN_RE = re.compile(r"[A-Za-z]{4,}")

def _keywords(text: str, stopwords: set) -> list[str]:
    return [w.lower() for w in _TOKEN_RE.findall(text)
            if w.lower() not in stopwords]

def build_keyword_graph(corpus: dict) -> nx.Graph:
    from sklearn.feature_extraction.text import ENGLISH_STOP_WORDS
    stops = set(ENGLISH_STOP_WORDS)

    pair_counts = Counter()
    for text in corpus.values():
        toks = _keywords(text, stops)
        for i in range(len(toks) - config.KW_WINDOW):
            window = toks[i:i + config.KW_WINDOW + 1]
            for a, b in itertools.combinations(sorted(set(window)), 2):
                pair_counts[(a, b)] += 1

    G = nx.Graph()
    for (a, b), w in pair_counts.items():
        if w >= config.KW_MIN_EDGE_W:
            G.add_edge(a, b, weight=w)
    return G