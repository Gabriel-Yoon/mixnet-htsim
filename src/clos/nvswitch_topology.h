#ifndef NVSWITCH_TOPO
#define NVSWITCH_TOPO
#include <ostream>
#include <unordered_map>
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

#ifndef QT
#define QT
typedef enum {RANDOM, ECN, COMPOSITE, CTRL_PRIO, LOSSLESS, LOSSLESS_INPUT, LOSSLESS_INPUT_ECN} queue_type;
#endif
using namespace std;

// Packet-level NVLink domain: a single-stage Clos of S switch chips, one queued
// L GB/s link per (GPU, chip) in each direction, so per-GPU injection AND
// reception are both capped at S*L by real queues rather than by an analytic
// shortcut. Cross-domain traffic takes one NIC link per GPU pair through a
// per-GPU egress feeder, as in FlatTopology.
//
// Replaces the analytic island (ffapp's nvlink_bandwidth shortcut), which
// completed any same-domain flow instantly with no contention. Both fabrics in
// the comparison are now simulated with queues.
class NVSwitchTopology : public Topology {
public:
  // --- domain (NVLink) tier -------------------------------------------------
  // up[g][s]   : GPU g   -> switch s of g's domain
  // down[g][s] : switch s of g's domain -> GPU g
  vector<vector<Queue *>> up_q,   down_q;
  vector<vector<Pipe  *>> up_p,   down_p;

  // --- scale-out (NIC) tier -------------------------------------------------
  // Allocated only for cross-domain pairs; nic_feeder caps a GPU's total
  // scale-out egress at one NIC rate.
  vector<Queue *> nic_feeder;
  unordered_map<uint64_t, Queue *> nic_q;
  unordered_map<uint64_t, Pipe  *> nic_p;

  FirstFit *ff;
  Logfile *logfile;
  EventList *eventlist;
  int failed_links;
  int _no_of_nodes;
  queue_type qt;

  // configuration, all printed in the banner
  int _domain;          // GPUs per NVLink domain
  int _switches;        // switch chips per domain
  double _link_gbps;    // per (GPU, switch) link, GB/s per direction
  uint32_t _lat_ns;     // per hop (GPU->switch and switch->GPU)
  mem_b _nvs_queue;     // bytes, NVLink port queue
  int _nvs_ecn_k_pkts;
  uint32_t _nic_mbps;   // scale-out link, Mbps
  uint32_t _nic_lat_ns;
  mem_b _nic_queue;
  int _nic_feeder_pkts;

  NVSwitchTopology(int no_of_nodes, Logfile *lg, EventList *ev, FirstFit *fit, queue_type q,
                   int domain, int switches, double link_gbps, uint32_t lat_ns,
                   mem_b nvs_queue, int nvs_ecn_k_pkts,
                   uint32_t nic_mbps, uint32_t nic_lat_ns, mem_b nic_queue, int nic_feeder_pkts);

  void init_network();
  virtual vector<const Route *> *get_paths(int src, int dest);
  vector<int> *get_neighbours(int src) { return NULL; }
  int no_of_nodes() const { return _no_of_nodes; }
  Pipe *get_pipe(int src, int dst) { return NULL; }

  Queue *alloc_queue(QueueLogger *ql, uint64_t speed_mbps, mem_b queuesize, int ecn_k_pkts);
  int domain_of(int g) const { return g / _domain; }

private:
  uint64_t key(int a, int b) const { return (uint64_t)a * (uint64_t)_no_of_nodes + (uint64_t)b; }
};

#endif
