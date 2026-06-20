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
  uint64_t _intra_bw_mbps = 0, _inter_bw_mbps = 0;

  int panel(int n) const { return n / _psize; }
  int loc(int n)   const { return n % _psize; }
  int lrow(int n)  const { return loc(n) / _pcols; }
  int lcol(int n)  const { return loc(n) % _pcols; }
  bool same_panel(int a, int b) const { return panel(a) == panel(b); }
  // intra-panel direct (FB) link: same panel and (same panel-row or same panel-col)
  bool intra_link(int a, int b) const {
    return same_panel(a, b) && (lrow(a) == lrow(b) || lcol(a) == lcol(b));
  }
  // intra-panel diameter-2 relay: same panel as a, a's row, b's column
  int intra_relay(int a, int b) const {
    return panel(a) * _psize + lrow(a) * _pcols + lcol(b);
  }
  int prow(int p) const { return p / _ppc; }
  int pcol(int p) const { return p % _ppc; }
  // do panels p,q carry a direct optical link?
  bool panels_conn(int p, int q) const {
    if (p == q) return false;
    return _mode == 0 ? true : (prow(p) == prow(q) || pcol(p) == pcol(q));
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
  int gw(int p, int q) const { return p * _psize + slot(p, q); }
  // optical egress ports a panel needs = its inter-panel degree
  int panel_degree() const {
    return _mode == 0 ? (_P - 1) : ((_ppr - 1) + (_ppc - 1));
  }
  // inter-panel (optical) direct link between two specific gateway nodes
  bool global_link(int a, int b) const {
    int pa = panel(a), pb = panel(b);
    if (pa == pb || !panels_conn(pa, pb)) return false;
    return a == gw(pa, pb) && b == gw(pb, pa);
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
