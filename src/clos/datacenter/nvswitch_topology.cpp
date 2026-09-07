#include <set>
#include "nvswitch_topology.h"
#include <vector>
#include <iostream>
#include <sstream>
#include "main.h"
#include "queue.h"
#include "switch.h"
#include "compositequeue.h"
#include "prioqueue.h"
#include "ecnqueue.h"
#include "randomqueue.h"

string ntoa(double n);   // defined in the htsim library, as in flat_topology.cpp

NVSwitchTopology::NVSwitchTopology(int no_of_nodes, Logfile *lg, EventList *ev, FirstFit *fit,
                                   queue_type q, int domain, int switches, double link_gbps,
                                   uint32_t lat_ns, mem_b nvs_queue, int nvs_ecn_k_pkts,
                                   uint32_t nic_mbps, uint32_t nic_lat_ns, mem_b nic_queue,
                                   int nic_feeder_pkts)
{
  logfile = lg; eventlist = ev; ff = fit; qt = q; failed_links = 0;
  _no_of_nodes = no_of_nodes;
  _domain = domain; _switches = switches; _link_gbps = link_gbps; _lat_ns = lat_ns;
  _nvs_queue = nvs_queue; _nvs_ecn_k_pkts = nvs_ecn_k_pkts;
  _nic_mbps = nic_mbps; _nic_lat_ns = nic_lat_ns; _nic_queue = nic_queue;
  _nic_feeder_pkts = nic_feeder_pkts;

  if (_no_of_nodes % _domain != 0) {
    cerr << "NVSwitchTopology: nodes (" << _no_of_nodes << ") must be a multiple of the domain ("
         << _domain << ")" << endl;
    exit(1);
  }

  int ndom = _no_of_nodes / _domain;
  double per_gpu = _link_gbps * _switches;
  cout << "NVSwitch model: D=" << _domain << " GPUs/domain, S=" << _switches
       << " switches x " << _link_gbps << " GB/s (= " << per_gpu
       << " GB/s/GPU/dir), hop " << _lat_ns << " ns, " << ndom << " domain(s)" << endl;
  // BDP over one NVLink port for the round trip through a switch (two hops each way)
  double bdp = _link_gbps * 1e9 * (4.0 * _lat_ns * 1e-9);
  cout << "NVSwitch queue: " << (_nvs_queue / 1500) << " pkt ("
       << (bdp > 0 ? _nvs_queue / bdp : 0.0) << "x BDP at " << (4 * _lat_ns)
       << " ns RTT), ECN K " << _nvs_ecn_k_pkts
       << " pkt, stripe=ecmp, analytic island OFF" << endl;
  cout << "Scale-out: " << (_nic_mbps / 8000.0) << " GB/s NIC per GPU, feeder "
       << _nic_feeder_pkts << " pkt, hop " << _nic_lat_ns << " ns, EGRESS ONLY" << endl;
  cout << "NVLink cost model: eff=1.0 (uncharged: no published NVSwitch measurement), "
       << "hop " << _lat_ns << " ns (uncharged: never published by NVIDIA), "
       << "uniform links per chip (uncharged: 5/5/4/4 split not in any NVIDIA source)" << endl;

  init_network();
}

Queue *NVSwitchTopology::alloc_queue(QueueLogger *ql, uint64_t speed_mbps, mem_b queuesize,
                                     int ecn_k_pkts)
{
  if (qt == ECN)
    return new ECNQueue(speedFromMbps(speed_mbps), queuesize, *eventlist, ql,
                        memFromPkt(ecn_k_pkts));
  if (qt == COMPOSITE)
    return new CompositeQueue(speedFromMbps(speed_mbps), queuesize, *eventlist, ql);
  return new Queue(speedFromMbps(speed_mbps), queuesize, *eventlist, ql);
}

void NVSwitchTopology::init_network()
{
  QueueLogger *ql = nullptr;
  const uint64_t nvl_mbps = (uint64_t)(_link_gbps * 8000.0);   // GB/s -> Mbps
  const simtime_picosec hop = timeFromNs((double)_lat_ns);

  up_q.assign(_no_of_nodes, vector<Queue *>(_switches, nullptr));
  down_q.assign(_no_of_nodes, vector<Queue *>(_switches, nullptr));
  up_p.assign(_no_of_nodes, vector<Pipe *>(_switches, nullptr));
  down_p.assign(_no_of_nodes, vector<Pipe *>(_switches, nullptr));

  for (int g = 0; g < _no_of_nodes; g++) {
    for (int s = 0; s < _switches; s++) {
      up_q[g][s] = alloc_queue(ql, nvl_mbps, _nvs_queue, _nvs_ecn_k_pkts);
      down_q[g][s] = alloc_queue(ql, nvl_mbps, _nvs_queue, _nvs_ecn_k_pkts);
      up_q[g][s]->setName("UP_G" + ntoa(g) + "_S" + ntoa(s));
      down_q[g][s]->setName("DN_S" + ntoa(s) + "_G" + ntoa(g));
      up_p[g][s] = new Pipe(hop, *eventlist);
      down_p[g][s] = new Pipe(hop, *eventlist);
      up_p[g][s]->setName("PUP_G" + ntoa(g) + "_S" + ntoa(s));
      down_p[g][s]->setName("PDN_S" + ntoa(s) + "_G" + ntoa(g));
    }
  }

  // scale-out tier: per-GPU egress feeder plus one link per cross-domain pair
  nic_feeder.assign(_no_of_nodes, nullptr);
  for (int g = 0; g < _no_of_nodes; g++) {
    nic_feeder[g] = new PriorityQueue(speedFromMbps((uint64_t)_nic_mbps),
                                      memFromPkt(_nic_feeder_pkts), *eventlist, ql);
    nic_feeder[g]->setName("NICPORT" + ntoa(g));
  }
  const simtime_picosec nhop = timeFromNs((double)_nic_lat_ns);
  for (int a = 0; a < _no_of_nodes; a++) {
    for (int b = 0; b < _no_of_nodes; b++) {
      if (a == b || domain_of(a) == domain_of(b)) continue;
      uint64_t k = key(a, b);
      nic_q[k] = alloc_queue(ql, _nic_mbps, _nic_queue, _nvs_ecn_k_pkts);
      nic_q[k]->setName("NIC_G" + ntoa(a) + "_G" + ntoa(b));
      nic_p[k] = new Pipe(nhop, *eventlist);
      nic_p[k]->setName("PNIC_G" + ntoa(a) + "_G" + ntoa(b));
    }
  }
}

// ffapp appends the sink itself (ffapp.cpp: routeout->push_back(flowSnk)), so a
// route here ends at the last pipe. Same-domain pairs return S equal-cost routes;
// ffapp's rand()%size() then gives per-flow ECMP across the switch chips with no
// change to ffapp.
vector<const Route *> *NVSwitchTopology::get_paths(int src, int dest)
{
  vector<const Route *> *paths = new vector<const Route *>();

  // Per-tier hop classification for the energy accounting, from the routes this
  // function actually builds. In-domain is GPU->switch->GPU, two NVLink hops;
  // cross-domain rides the NIC and touches no NVLink queue at all. Once per
  // (src,dest) pair; off unless GLASS_LOG_HOPS.
  static const bool log_hops = getenv("GLASS_LOG_HOPS") != NULL;
  if (log_hops) {
    static std::set<std::pair<int, int> > seen;
    if (seen.insert(std::make_pair(src, dest)).second) {
      bool same = domain_of(src) == domain_of(dest);
      cerr << "nvhoplog: " << src << " " << dest << " "
           << (same ? 2 : 0) << " " << (same ? 0 : 1) << endl;
    }
  }

  if (domain_of(src) == domain_of(dest)) {
    for (int s = 0; s < _switches; s++) {
      route_t *r = new Route();
      r->push_back(up_q[src][s]);
      r->push_back(up_p[src][s]);
      r->push_back(down_q[dest][s]);
      r->push_back(down_p[dest][s]);
      paths->push_back(r);
    }
    return paths;
  }

  uint64_t k = key(src, dest);
  route_t *r = new Route();
  r->push_back(nic_feeder[src]);
  r->push_back(nic_q[k]);
  r->push_back(nic_p[k]);
  paths->push_back(r);
  return paths;
}
