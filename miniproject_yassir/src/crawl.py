# src/crawl.py
"""
BFS Wikipedia crawler.
- Starts from config.SEED_ARTICLES
- Follows up to LINKS_PER_ARTICLE links per article
- Stores first MAX_WORDS words per article
- Resumable: merges into existing JSON
"""
import json, os, time, random
from collections import deque
import wikipediaapi
from tqdm import tqdm

from . import config

def _get_wiki():
    return wikipediaapi.Wikipedia(
        user_agent="MiniProjectTopicGraph/1.0 (educational)",
        language="en",
    )

def _first_n_words(text: str, n: int) -> str:
    return " ".join(text.split()[:n])

def crawl(save=True):
    wiki = _get_wiki()
    os.makedirs(config.DATA_DIR, exist_ok=True)

    # resume from previous run if any (tolerant of empty/corrupt files)
    corpus = _load_corpus_safe(config.ARTICLES_JSON)
    if corpus:
        print(f"[resume] {len(corpus)} articles already cached")

    queue = deque(config.SEED_ARTICLES)
    seen  = set(corpus.keys()) | set(queue)

    pbar = tqdm(total=config.TARGET_ARTICLES, desc="articles")
    pbar.update(len(corpus))

    while queue and len(corpus) < config.TARGET_ARTICLES:
        title = queue.popleft()
        if title in corpus:
            continue

        page = wiki.page(title)
        if not page.exists():
            continue

        text = _first_n_words(page.text, config.MAX_WORDS)
        if len(text.split()) < 50:           # skip stubs
            continue
        corpus[title] = text
        pbar.update(1)

        # BFS expansion: take a random sample of links
        links = list(page.links.keys())
        random.seed(config.RANDOM_SEED)
        random.shuffle(links)
        for link in links[:config.LINKS_PER_ARTICLE]:
            if link not in seen:
                seen.add(link)
                queue.append(link)

        time.sleep(config.CRAWL_DELAY_SEC)

    pbar.close()

    if save:
        tmp = config.ARTICLES_JSON + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(corpus, f, indent=2, ensure_ascii=False)
        os.replace(tmp, config.ARTICLES_JSON)  
        print(f"saved {len(corpus)} articles → {config.ARTICLES_JSON}")

    return corpus

def _load_corpus_safe(path: str) -> dict:
    """Load the cached corpus, or start fresh if missing/empty/corrupt."""
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read().strip()
    except OSError as e:
        print(f"[warn] cannot read {path}: {e} — starting fresh")
        return {}
    if not text:
        print(f"[warn] {path} is empty — starting fresh")
        return {}
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        backup = path + ".corrupt"
        os.replace(path, backup)
        print(f"[warn] {path} is corrupt ({e}) — moved to {backup}, starting fresh")
        return {}

if __name__ == "__main__":
    crawl()