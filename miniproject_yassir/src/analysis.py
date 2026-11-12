# src/analysis.py
import networkx as nx
import pandas as pd
import community as community_louvain          # python-louvain
import itertools

# ---------- 3.1 structural ----------
def structural_stats(G: nx.Graph) -> dict:
    G = G.copy()
    n, m = G.number_of_nodes(), G.number_of_edges()
    comps = list(nx.connected_components(G))
    lcc = G.subgraph(max(comps, key=len)) if comps else G
    
    # Only calculate diameter and avg_path if the graph is small enough.
    # Calculating this on a 13,000-node graph takes hours.
    if lcc.number_of_nodes() < 5000:
        try:
            diameter = nx.diameter(lcc)
            avg_path = nx.average_shortest_path_length(lcc)
        except nx.NetworkXError:
            diameter, avg_path = None, None
    else:
        diameter = "Skipped (Too large)"
        avg_path = "Skipped (Too large)"

    return {
        "nodes": n,
        "edges": m,
        "density": nx.density(G),
        "components": len(comps),
        "lcc_size": lcc.number_of_nodes(),
        "avg_degree": (2 * m / n) if n else 0,
        "diameter": diameter,
        "avg_clustering": nx.average_clustering(G),
        "avg_path": avg_path,
    }

# ---------- 3.2 centrality ----------
def centrality_table(G: nx.Graph) -> pd.DataFrame:
    deg  = nx.degree_centrality(G)
    btw  = nx.betweenness_centrality(G, weight="weight", normalized=True)
    clo  = nx.closeness_centrality(G, distance="weight")
    pr   = nx.pagerank(G, weight="weight")
    df = pd.DataFrame({
        "entity": list(G.nodes),
        "type":  [G.nodes[n].get("type", "") for n in G.nodes],
        "degree_cent": [deg[n] for n in G.nodes],
        "betweenness": [btw[n] for n in G.nodes],
        "closeness":   [clo[n] for n in G.nodes],
        "pagerank":    [pr[n]  for n in G.nodes],
    }).sort_values("pagerank", ascending=False).reset_index(drop=True)
    return df

# ---------- 3.3 community detection ----------
def communities_greedy(G):
    from networkx.algorithms.community import greedy_modularity_communities
    parts = list(greedy_modularity_communities(G, weight="weight"))
    mapping = {n: i for i, part in enumerate(parts) for n in part}
    return mapping, parts

def communities_louvain(G):
    mapping = community_louvain.best_partition(G, weight="weight", random_state=0)
    parts = {}
    for n, c in mapping.items():
        parts.setdefault(c, []).append(n)
    return mapping, list(parts.values())

# ---------- 3.4 paths ----------
def top_pairs_paths(G, k=10, n_pairs=6):
    lcc = G.subgraph(max(nx.connected_components(G), key=len))
    top = sorted(lcc.degree, key=lambda x: x[1], reverse=True)[:k]
    nodes = [n for n, _ in top]
    results = []
    for a, b in itertools.combinations(nodes, 2):
        if len(results) >= n_pairs:
            break
        try:
            path = nx.shortest_path(lcc, a, b)
        except nx.NetworkXNoPath:
            continue
        results.append({"from": a, "to": b, "length": len(path) - 1, "path": path})
    return results