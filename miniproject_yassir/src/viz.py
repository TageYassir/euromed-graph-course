import matplotlib.pyplot as plt
import networkx as nx
import pandas as pd

COMMUNITY_CMAP = plt.cm.tab20

def dashboard(G, centrality_df, community_map, path="outputs/miniproject_dashboard.png"):
    fig, axes = plt.subplots(2, 2, figsize=(20, 16))
    
    # ==========================================
    # Panel 1: Entity Network (Top-Left)
    # ==========================================
    ax = axes[0, 0]
    # 1. Filter weak edges for visualization only (declutter)
    viz_G = G.copy()
    viz_G.remove_edges_from([(u, v, d) for u, v, d in viz_G.edges(data=True) if d.get("weight", 1) < 2])
    
    # 2. Better layout (higher k spreads nodes out)
    pos = nx.spring_layout(viz_G, seed=42, k=0.6, iterations=100)
    
    pr = centrality_df.set_index("entity")["pagerank"]
    node_colors = [COMMUNITY_CMAP(community_map.get(n, 0) % 20) for n in viz_G.nodes]
    
    # Smaller base size, scaled by PR
    node_sizes = [30 + 1500 * pr.get(n, 0) for n in viz_G.nodes]
    
    nx.draw_networkx_edges(viz_G, pos, ax=ax, alpha=0.15, width=0.5)
    nx.draw_networkx_nodes(viz_G, pos, ax=ax, node_color=node_colors, node_size=node_sizes, alpha=0.9)
    
    top15 = pr.sort_values(ascending=False).head(15).index
    # Only label if the node is in the viz graph
    labels = {n: n for n in top15 if n in viz_G.nodes}
    nx.draw_networkx_labels(viz_G, pos, labels, ax=ax, font_size=9, font_weight="bold")
    
    ax.set_title("Entity Network (Colour = Community, Size = PageRank)", fontsize=14, pad=15)
    ax.axis("off")

    # ==========================================
    # Panel 2: Degree Distribution (Top-Right)
    # ==========================================
    ax = axes[0, 1]
    degs = [d for _, d in G.degree()]
    ax.hist(degs, bins=40, color="steelblue", edgecolor="black", alpha=0.8)
    ax.set_title("Degree Distribution", fontsize=14, pad=15)
    ax.set_xlabel("Degree (Number of Connections)", fontsize=12)
    ax.set_ylabel("Frequency (Number of Entities)", fontsize=12)
    ax.grid(axis='y', alpha=0.4)

    # ==========================================
    # Panel 3: Top 15 by PageRank (Bottom-Left)
    # ==========================================
    ax = axes[1, 0]
    top15_df = centrality_df.head(15).iloc[::-1] # Reverse so highest is at top
    ax.barh(top15_df["entity"], top15_df["pagerank"], color="coral", edgecolor="black")
    ax.set_title("Top 15 Entities by PageRank", fontsize=14, pad=15)
    ax.set_xlabel("PageRank Score", fontsize=12)
    ax.set_ylabel("Entity", fontsize=12)
    ax.grid(axis='x', alpha=0.4)

    # ==========================================
    # Panel 4: Community Sizes (Bottom-Right)
    # ==========================================
    ax = axes[1, 1]
    # Count sizes using pandas for simplicity
    sizes = pd.Series(list(community_map.values())).value_counts().head(15)
    ax.bar(sizes.index.astype(str), sizes.values, color="mediumseagreen", edgecolor="black")
    ax.set_title("Top 15 Community Sizes", fontsize=14, pad=15)
    ax.set_xlabel("Community ID", fontsize=12)
    ax.set_ylabel("Number of Entities", fontsize=12)
    ax.grid(axis='y', alpha=0.4)

    plt.tight_layout()
    fig.savefig(path, dpi=160, bbox_inches='tight')
    plt.close(fig)
    print(f"✓ Dashboard saved to {path}")

def interactive_html(G, centrality_df, path="outputs/miniproject_interactive.html"):
    TYPE_COLOR = {
        "PERSON": "#e6194b", "ORG": "#3cb44b", "GPE": "#4363d8",
        "PRODUCT": "#f58231", "WORK_OF_ART": "#911eb4", "EVENT": "#42d4f4",
    }
    pr = centrality_df.set_index("entity")["pagerank"]
    pr_max = pr.max() or 1

    net = Network(height="900px", width="100%", bgcolor="#ffffff", font_color="black")
    net.barnes_hut(gravity=-4000, spring_length=120)

    for n, data in G.nodes(data=True):
        net.add_node(
            n, label=n,
            color=TYPE_COLOR.get(data.get("type"), "#888888"),
            size=10 + 40 * (pr.get(n, 0) / pr_max),
            title=f"{n}\ntype={data.get('type')}\n"
                  f"articles={data.get('n_articles')}\ndegree={G.degree(n)}\n"
                  f"pagerank={pr.get(n, 0):.4f}",
        )
    for a, b, d in G.edges(data=True):
        net.add_edge(a, b, width=min(1 + d.get("weight", 1) * 0.2, 6))

    net.write_html(path, notebook=False)