#ifndef GLASSFB_TOP
#define GLASSFB_TOP
#include "main.h"
#include "randomqueue.h"
#include "pipe.h"
#include "config.h"
#include "loggers.h"
#include "network.h"
#include "firstfit.h"
#include "topology.h"
#include "logfile.h"
#include "eventlist.h"
#include "switch.h"
#include <ostream>

#ifndef QT
#define QT
typedef enum {RANDOM, ECN, COMPOSITE, CTRL_PRIO, LOSSLESS, LOSSLESS_INPUT, LOSSLESS_INPUT_ECN} queue_type;
#endif
using namespace std;
class GlassFBTopology: public Topology {

public:

  vector<Switch*> switchs;

  vector<vector<Pipe*>> pipes;
  vector<vector<Queue*>> queues;
  
  FirstFit* ff;
  Logfile* logfile;
  EventList* eventlist;
  int failed_links;
  int _no_of_nodes;
  // Two-tier glass interconnect.
  //   tier-1 (scale-up):  glass FlattenedButterfly *panel* of _psize GPUs, laid out
  //                       as a _prows x _pcols grid; in-package waveguide links to
  //                       every node in the same panel row/column (panel diameter 2).
  //   tier-2 (scale-out): _P panels joined by optical fiber. Two designs:
  //                       mode 0 = Dragonfly  -> every panel pair directly linked
  //                                              (inter-panel diameter 1).
  //                       mode 1 = 2-level FB  -> panels arranged in a _ppr x _ppc
  //                                              panel-grid, linked by panel row/col
  //                                              (inter-panel diameter 2, relay panel).
  int _psize = 16, _pcols = 4, _prows = 4;   // intra-panel grid
  int _P = 1, _ppr = 1, _ppc = 1;            // panel grid (mode 1)
  int _mode = 0;                             // 0 = dragonfly, 1 = 2-level FB
  // per-link bandwidth (Mbps). intra-panel = in-package glass waveguide;
  // inter-panel = optical fiber gateway. The thesis lives in _inter_bw_mbps
  // (glass optical ~512 GB/s vs NVL72 IB ~50 GB/s) at fixed topology.
  uint64_t _intra_bw_mbps = 0, _inter_bw_mbps = 0;   // legacy single-intra (back-compat)
  // distance-layered design (ASTRA-sim FB config): adjacent(grid dist 1)=electrical RDL,
  // far(dist>=2)=optical WG, inter-panel=optical fiber.  defaults: 1800 / 400 / 200 GB/s.
  uint64_t _elec_bw_mbps = 0, _opt_bw_mbps = 0;     // Mbps
  uint32_t _elec_lat_ns = 100, _opt_lat_ns = 300, _inter_lat_ns = 500;
  // ECN marking threshold (packets) for the ECN queue_type; overridable via GLASS_ECN_K.
  int _ecn_k_pkts = 50;
  // Multi-gateway inter-panel spreading: instead of ONE fixed gateway pair carrying
  // ALL traffic between a given panel pair, provision _gw_parallel parallel gateway
  // pairs and load-balance flows across them by a hash of their local panel positions.
  // The per-link inter-panel bandwidth is divided by _gw_parallel so the *aggregate*
  // p<->q capacity is unchanged -- this isolates whether spreading fan-in across
  // multiple physical links (vs. one) fixes the EP>panel incast, independent of
  // adding more total bandwidth. Overridable via GLASS_GW_PARALLEL (default 1 = old
  // single-gateway behavior). Requires panel_degree() * _gw_parallel <= _psize
  // (clamped in set_params if violated).
  int _gw_parallel = 1;
  // EP-panel-aware placement: relabel logical nodes so EP-group mates land in one panel.
  bool _ep_place = false; int _tp_deg = 1, _ep_deg = 1;
  // dimension-order load-balanced (Valiant) intra-panel routing: spread each 2-hop a2a
  // flow across the two dimension-order relays (row-first vs col-first) instead of always
  // using the same corner, so skewed MoE a2a does not pile onto one relay/link.
  bool _dim_route = false;

  // EP-aware placement: relabel so EP-group mates (same dp/tp/pp, varying ep) become contiguous
  // -> co-located in one panel when ep_deg <= psize, making the expert a2a intra-panel.
  int phys(int n) const {
    if (!_ep_place || _ep_deg <= 1) return n;
    int hi = n / (_ep_deg * _tp_deg);
    int ep = (n / _tp_deg) % _ep_deg;
    int tp = n % _tp_deg;
    return (hi * _tp_deg + tp) * _ep_deg + ep;
  }
  // inverse of phys(): physical id -> logical id (for functions that compute a physical position)
  int phys_inv(int m) const {
    if (!_ep_place || _ep_deg <= 1) return m;
    int ep = m % _ep_deg;
    int rest = m / _ep_deg;
    int tp = rest % _tp_deg;
    int hi = rest / _tp_deg;
    return (hi * _ep_deg + ep) * _tp_deg + tp;
  }
  int panel(int n) const { return phys(n) / _psize; }
  int loc(int n)   const { return phys(n) % _psize; }
  int lrow(int n)  const { return loc(n) / _pcols; }
  int lcol(int n)  const { return loc(n) % _pcols; }
  bool same_panel(int a, int b) const { return panel(a) == panel(b); }
  // intra-panel direct (FB) link: same panel and (same panel-row or same panel-col)
  bool intra_link(int a, int b) const {
    return same_panel(a, b) && (lrow(a) == lrow(b) || lcol(a) == lcol(b));
  }
  // grid distance along the shared row/col of an intra_link (1 = adjacent electrical RDL)
  int intra_dist(int a, int b) const {
    int d = 999;
    if (lrow(a) == lrow(b)) d = lcol(a) - lcol(b);
    else if (lcol(a) == lcol(b)) d = lrow(a) - lrow(b);
    return d < 0 ? -d : d;
  }
  bool adjacent_link(int a, int b) const { return intra_dist(a, b) == 1; }
  // intra-panel diameter-2 relay: same panel as a, a's row, b's column (row-first / dim-0-first)
  int intra_relay(int a, int b) const {
    return phys_inv(panel(a) * _psize + lrow(a) * _pcols + lcol(b));
  }
  // the other dimension-order relay: a's column, b's row (col-first / dim-1-first)
  int intra_relay2(int a, int b) const {
    return phys_inv(panel(a) * _psize + lrow(b) * _pcols + lcol(a));
  }
  // pick the relay for a 2-hop intra-panel hop. with dim-order load balancing on, spread
  // flows across both relays by a stable hash of (a,b) so neither corner becomes a hotspot.
  int relay_for(int a, int b) const {
    if (_dim_route) {
      unsigned h = ((unsigned)a * 2654435761u) ^ ((unsigned)b * 40503u);
      if (h & 1u) return intra_relay2(a, b);
    }
    return intra_relay(a, b);
  }
  int prow(int p) const { return p / _ppc; }
  int pcol(int p) const { return p % _ppc; }

  // mode 2 = true 4-edge mesh: a panel has AT MOST 4 physical neighbors (N/S/E/W in
  // the panel grid), each reachable only via that one dedicated physical edge -- unlike
  // mode 0/1, GPUs are NOT a free-floating pool; each of the panel's 4 sides is a fixed,
  // disjoint set of _pcols (N/S) or _prows (E/W) GPUs (a full row/column of the intra-
  // panel grid), and only THAT side's GPUs can host a fiber facing THAT direction.
  enum { DIR_N = 0, DIR_S = 1, DIR_E = 2, DIR_W = 3 };
  int edge_pool_size(int dir) const { return (dir == DIR_N || dir == DIR_S) ? _pcols : _prows; }
  // local index (within the panel) of gateway slot g on the edge facing `dir`.
  int edge_local(int dir, int g) const {
    int sz = edge_pool_size(dir);
    g = ((g % sz) + sz) % sz;
    switch (dir) {
      case DIR_N: return g;                          // row 0 (top edge)
      case DIR_S: return (_prows - 1) * _pcols + g;   // last row (bottom edge)
      case DIR_E: return g * _pcols + (_pcols - 1);   // last col (right edge)
      default:    return g * _pcols;                  // col 0 (left edge)
    }
  }
  // which physical direction, from panel p, does immediate neighbor q sit in? false if
  // q is not an immediate (mesh-adjacent) panel-grid neighbor of p.
  bool mesh_neighbor(int p, int q, int &dir) const {
    int dr = prow(q) - prow(p), dc = pcol(q) - pcol(p);
    if (dr == 0 && dc == 1)  { dir = DIR_E; return true; }
    if (dr == 0 && dc == -1) { dir = DIR_W; return true; }
    if (dc == 0 && dr == 1)  { dir = DIR_S; return true; }
    if (dc == 0 && dr == -1) { dir = DIR_N; return true; }
    return false;
  }
  // panel-level XY (dimension-order) route from panel p to panel q: match column
  // first (E/W steps), then row (N/S steps). Each step is one mesh_neighbor() hop.
  vector<int> panel_path(int p, int q) const {
    vector<int> path; path.push_back(p);
    int cp = p;
    while (pcol(cp) != pcol(q)) {
      int step = pcol(q) > pcol(cp) ? 1 : -1;
      cp = prow(cp) * _ppc + (pcol(cp) + step);
      path.push_back(cp);
    }
    while (prow(cp) != prow(q)) {
      int step = prow(q) > prow(cp) ? 1 : -1;
      cp = (prow(cp) + step) * _ppc + pcol(cp);
      path.push_back(cp);
    }
    return path;
  }
  // do panels p,q carry a direct optical link?
  bool panels_conn(int p, int q) const {
    if (p == q) return false;
    if (_mode == 0) return true;
    if (_mode == 2) { int d; return mesh_neighbor(p, q, d); }
    return prow(p) == prow(q) || pcol(p) == pcol(q);
  }
  // local gateway index in panel p for the optical link toward panel q: the rank of
  // q among p's connected panels (compacted, so it is bounded by the panel degree).
  int slot(int p, int q) const {
    int r = 0;
    for (int x = 0; x < _P; x++) {
      if (x == p || !panels_conn(p, x)) continue;
      if (x == q) break;
      r++;
    }
    return r;
  }
  // gateway GPU hosting the fiber toward panel q, sub-link g in [0,_gw_parallel).
  // Each destination panel is reserved a block of _gw_parallel consecutive local
  // slots (slot(p,q)*_gw_parallel .. +g); wraps if that exceeds _psize (OCS-FC /
  // forced dragonfly at large P, or _gw_parallel too large for panel_degree()).
  int gw(int p, int q, int g = 0) const {
    if (_mode == 2) {
      int dir;
      if (!mesh_neighbor(p, q, dir)) return p * _psize; // not adjacent; caller error
      return phys_inv(p * _psize + edge_local(dir, g));
    }
    int base = slot(p, q) * _gw_parallel;
    int gg = _gw_parallel > 1 ? (g % _gw_parallel) : 0;
    return phys_inv(p * _psize + (base + gg) % _psize);
  }
  // which of the _gw_parallel gateway pairs a given (src,dst) flow uses -- a
  // symmetric hash of their in-panel local positions so both directions of the
  // same physical flow (and its ACKs) pick the same gateway pair.
  int gw_g(int src, int dst) const {
    return _gw_parallel > 1 ? (loc(src) + loc(dst)) % _gw_parallel : 0;
  }
  // optical egress ports a panel needs = its inter-panel degree
  int panel_degree() const {
    if (_mode == 2) return 4; // ceiling; corner/edge panel-grid positions have fewer
    return _mode == 0 ? (_P - 1) : ((_ppr - 1) + (_ppc - 1));
  }
  // inter-panel (optical) direct link between two specific gateway nodes (any of
  // the _gw_parallel sub-links between their panels)
  bool global_link(int a, int b) const {
    int pa = panel(a), pb = panel(b);
    if (pa == pb || !panels_conn(pa, pb)) return false;
    for (int g = 0; g < _gw_parallel; g++)
      if (a == gw(pa, pb, g) && b == gw(pb, pa, g)) return true;
    return false;
  }
  bool connected(int a, int b) const { return intra_link(a, b) || global_link(a, b); }
  queue_type qt;

  GlassFBTopology(int no_of_nodes, mem_b queuesize, Logfile* log,EventList* ev,FirstFit* f, queue_type q);

  void init_network();
  virtual vector<const Route*>* get_paths(int src, int dest);

  Pipe * get_pipe(int src, int dst) { return pipes[src][dst]; };
  Queue* alloc_src_queue(QueueLogger* q);
  Queue* alloc_queue(QueueLogger* q, mem_b queuesize);
  Queue* alloc_queue(QueueLogger* q, uint64_t speed, mem_b queuesize);

  void count_queue(Queue*);
  void print_path(std::ofstream& paths,int src,const Route* route);
  vector<int>* get_neighbours(int src) { return NULL;};
  int no_of_nodes() const {return _no_of_nodes;}
  int find_lp_switch(Queue* queue);
private:
  map<Queue*,int> _link_usage;

  int find_destination(Queue* queue);
  void set_params(int no_of_nodes);
  // full hop-by-hop node sequence from src to dst (consecutive nodes are directly linked)
  vector<int> node_path(int src, int dest) const;
  mem_b _queuesize;
};

// class UtilMonitor : public EventSource {
//  public:

//     UtilMonitor(GlassFBTopology* top, EventList &eventlist);

//     void start(simtime_picosec period);
//     void doNextEvent();
//     void printAggUtil();

//     GlassFBTopology* _top;
//     simtime_picosec _period; // picoseconds between utilization reports
//     int64_t _max_agg_Bps; // delivered to endhosts, across the whole network
//     int64_t _max_B_in_period;
//     int _H; // number of hosts

// };



#endif
