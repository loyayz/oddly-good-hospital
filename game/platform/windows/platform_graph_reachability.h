// Borrow the model's immutable child lists. Boost owns the DFS and its color
// transitions; visitors only collect the hospital's reachable facts/resources.
#pragma once
#include <cstddef>
#include <utility>
#include <vector>

namespace hospital_graph {
struct ChildEdge {
    int from = 0, to = 0;
    bool operator==(const ChildEdge& other) const { return from == other.from && to == other.to; }
    bool operator!=(const ChildEdge& other) const { return !(*this == other); }
};
template<class Nodes> struct ChildGraph {
    using vertex_descriptor = int;
    using edge_descriptor = ChildEdge;
    struct FromChild {
        int from = 0;
        edge_descriptor operator()(int child) const { return {from, child}; }
    };
    using ChildIterator = decltype(std::declval<const typename Nodes::value_type&>().children.cbegin());
    using out_edge_iterator = boost::transform_iterator<FromChild, ChildIterator>;
    using directed_category = boost::directed_tag;
    using edge_parallel_category = boost::allow_parallel_edge_tag;
    using traversal_category = boost::incidence_graph_tag;
    using vertices_size_type = std::size_t;
    using edges_size_type = std::size_t;
    using degree_size_type = std::size_t;
    const Nodes& nodes;
    explicit ChildGraph(const Nodes& source) : nodes(source) {}
    static vertex_descriptor null_vertex() { return -1; }
};
template<class Nodes>
std::pair<typename ChildGraph<Nodes>::out_edge_iterator, typename ChildGraph<Nodes>::out_edge_iterator>
out_edges(int vertex, const ChildGraph<Nodes>& graph) {
    const auto& children = graph.nodes[vertex].children;
    typename ChildGraph<Nodes>::FromChild transform{vertex};
    return {boost::make_transform_iterator(children.cbegin(), transform), boost::make_transform_iterator(children.cend(), transform)};
}
template<class Nodes>
std::size_t out_degree(int vertex, const ChildGraph<Nodes>& graph) { return graph.nodes[vertex].children.size(); }
template<class Nodes>
int source(const typename ChildGraph<Nodes>::edge_descriptor& edge, const ChildGraph<Nodes>&) { return edge.from; }
template<class Nodes>
int target(const typename ChildGraph<Nodes>::edge_descriptor& edge, const ChildGraph<Nodes>&) { return edge.to; }

template<class Callback> struct DiscoverVisitor : boost::default_dfs_visitor {
    Callback discover;
    explicit DiscoverVisitor(Callback callback) : discover(std::move(callback)) {}
    template<class Graph>
    void discover_vertex(int vertex, const Graph&) const { discover(vertex); }
};

template<class Nodes, class Callback> class Reachability {
    ChildGraph<Nodes> graph;
    std::vector<boost::default_color_type> colors;
    Callback discover;
public:
    Reachability(const Nodes& nodes, Callback callback)
        : graph(nodes), colors(nodes.size(), boost::white_color), discover(std::move(callback)) {}
    void from(int root) {
        if (colors[root] != boost::white_color) return;
        auto color = boost::make_iterator_property_map(colors.begin(), boost::typed_identity_property_map<int>());
        boost::depth_first_visit(graph, root, DiscoverVisitor<Callback>(discover), color);
    }
};
}
