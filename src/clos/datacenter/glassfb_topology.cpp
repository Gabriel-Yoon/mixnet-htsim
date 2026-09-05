// -*- c-basic-offset: 4; tab-width: 8; indent-tabs-mode: t -*-
#include "glassfb_topology.h"
#include <cmath>
#include <cstdlib>
#include <algorithm>
#include <vector>
#include "string.h"
#include <sstream>
#include <strstream>
#include <iostream>
#include "main.h"
#include "queue.h"
#include "switch.h"
#include "compositequeue.h"
#include "prioqueue.h"
#include "queue_lossless.h"
#include "queue_lossless_input.h"
#include "queue_lossless_output.h"
#include "ecnqueue.h"

extern uint32_t RTT;
extern uint32_t SPEED;
extern ofstream fct_util_out;

string ntoa(double n);
string itoa(uint64_t n);

//extern int N;

GlassFBTopology::GlassFBTopology(int no_of_nodes, mem_b queuesize, Logfile *lg, EventList *ev, FirstFit *fit, queue_type q)
{
  _queuesize = queuesize;
  logfile = lg;
  eventlist = ev;
  ff = fit;
  qt = q;
  failed_links = 0;

  set_params(no_of_nodes);

  init_network();
}

void GlassFBTopology::set_params(int no_of_nodes)
{
  cout << "Set params " << no_of_nodes << endl;

  _no_of_nodes = no_of_nodes;

  // tier-1: glass-FB panel size (scale-up domain). Default 16 GPUs in a 4x4 FB.
  _psize = 16;
  if (const char *e = getenv("GLASS_PANEL")) { int v = atoi(e); if (v > 0) _psize = v; }
  if (_psize > no_of_nodes || no_of_nodes % _psize != 0) _psize = no_of_nodes; // single panel
  // intra-panel grid: pcols = largest divisor of _psize <= sqrt(_psize) (4 for 16).
  int pc = (int)(sqrt((double)_psize) + 0.5);
  while (pc > 1 && _psize % pc != 0) pc--;
  if (const char *e = getenv("GLASS_PCOLS")) { int v = atoi(e); if (v > 0 && _psize % v == 0) pc = v; }
  _pcols = pc;
  _prows = _psize / _pcols;

  // tier-2: number of panels and inter-panel mode.
  _P = no_of_nodes / _psize;
  _mode = 0; // dragonfly
  if (const char *e = getenv("GLASS_INTER")) {
    if (strcmp(e, "fb2") == 0) _mode = 1;
    else if (strcmp(e, "mesh") == 0) _mode = 2; // true 4-edge mesh, see panels_conn()/gw()
  }
  // panel grid for 2-level FB: ppc = largest divisor of _P <= sqrt(_P).
  int ppc = (int)(sqrt((double)_P) + 0.5);
  while (ppc > 1 && _P % ppc != 0) ppc--;
  _ppc = ppc;
  _ppr = _P / _ppc;

  // Each inter-panel optical link consumes one egress port; a panel's port budget is
  // <= _psize (one optical port per GPU). Dragonfly needs P-1 ports; if that exceeds
  // the budget, fall back to 2-level FB (degree (ppr-1)+(ppc-1)) -- UNLESS the design
  // uses an optical circuit switch (our documented inter-panel model: FullyConnected,
  // 1 hop, cost = bandwidth not hop count). GLASS_FORCE_DFLY=1 keeps the FC/dragonfly
  // graph at any P; gateways wrap around the panel (a GPU hosts multiple fiber ports).
  bool force_dfly = false;
  if (const char *e = getenv("GLASS_FORCE_DFLY")) force_dfly = atoi(e) != 0;
  if (_mode == 0 && panel_degree() > _psize) {
    if (force_dfly) {
      cout << "GlassFB: OCS-FC forced (degree " << panel_degree() << " > panel ports "
           << _psize << "; modeling optical-circuit-switch FullyConnected, wrapped gateways)" << endl;
    } else {
      cout << "GlassFB: dragonfly infeasible (degree " << panel_degree()
           << " > panel ports " << _psize << "); falling back to 2-level FB" << endl;
      _mode = 1;
    }
  }
  if (_mode == 1 && panel_degree() > _psize)
    cout << "GlassFB: WARNING scale-out INFEASIBLE -- panel degree " << panel_degree()
         << " > optical ports " << _psize << " (needs smaller panels or 3-level)" << endl;

  // per-link bandwidth (GB/s in env -> Mbps). Default to global -speed (SPEED, Mbps)
  // so behaviour is unchanged unless overridden. 1 GB/s = 8000 Mbps.
  // distance-layered design (from ASTRA-sim FB cluster config h100_fb_4x4):
  //   adjacent (grid dist 1) = electrical RDL 1800 GB/s; far (dist>=2) = optical WG 400; inter 200.
  _elec_bw_mbps  = 1800ULL * 8000;
  _opt_bw_mbps   = 400ULL  * 8000;
  _inter_bw_mbps = 200ULL  * 8000;
  _intra_bw_mbps = _opt_bw_mbps;   // legacy alias
  if (const char *e = getenv("GLASS_ELEC_BW")) { double g=atof(e); if(g>0) _elec_bw_mbps=(uint64_t)(g*8000.0); }
  if (const char *e = getenv("GLASS_OPT_BW"))  { double g=atof(e); if(g>0) _opt_bw_mbps =(uint64_t)(g*8000.0); }
  if (const char *e = getenv("GLASS_INTER_BW")){ double g=atof(e); if(g>0) _inter_bw_mbps=(uint64_t)(g*8000.0); }
  if (const char *e = getenv("GLASS_INTRA_BW")){ double g=atof(e); if(g>0){ _elec_bw_mbps=_opt_bw_mbps=(uint64_t)(g*8000.0); } } // legacy uniform intra
  if (const char *e = getenv("GLASS_ELEC_LAT")) _elec_lat_ns=atoi(e);
  if (const char *e = getenv("GLASS_OPT_LAT"))  _opt_lat_ns =atoi(e);
  if (const char *e = getenv("GLASS_INTER_LAT"))_inter_lat_ns=atoi(e);
  if (const char *e = getenv("GLASS_EP_PLACE")) _ep_place = atoi(e) != 0;
  if (const char *e = getenv("GLASS_TP")) _tp_deg = atoi(e);
  if (const char *e = getenv("GLASS_EP")) _ep_deg = atoi(e);
  if (const char *e = getenv("GLASS_DIM_A2A")) _dim_route = atoi(e) != 0;
  if (const char *e = getenv("GLASS_ECN_K")) { int v = atoi(e); if (v > 0) _ecn_k_pkts = v; }
  if (const char *e = getenv("GLASS_GW_PARALLEL")) { int v = atoi(e); if (v > 0) _gw_parallel = v; }
  if (_mode == 2) {
    // mesh: each of the 4 edges is its OWN disjoint GPU pool (a full row/col of the
    // panel), independent of how many of the panel's other 3 edges are also active --
    // so G is capped by that single edge's pool size, not divided by neighbor count.
    int cap = std::min(_pcols, _prows);
    if (_gw_parallel > cap) {
      cout << "GLASS_GW_PARALLEL=" << _gw_parallel << " too large for mesh edge pool ("
           << cap << " GPUs/edge); clamping to " << cap << endl;
      _gw_parallel = cap;
    }
  } else { // clamp: each panel needs panel_degree() reserved blocks of _gw_parallel slots, total <= _psize
    int deg = panel_degree();
    if (deg > 0 && _gw_parallel > _psize / deg) {
      cout << "GLASS_GW_PARALLEL=" << _gw_parallel << " too large for panel_degree=" << deg
           << " and panel size=" << _psize << "; clamping to " << (_psize / deg) << endl;
      _gw_parallel = std::max(1, _psize / deg);
    }
  }

  cout << "GlassFB 2-tier: " << _P << " panels x " << _psize << " GPU"
       << " (intra " << _prows << "x" << _pcols << " FB, panel diam 2); "
       << "inter-panel = " << (_mode == 0 ? "dragonfly (all-to-all, diam 1)"
                             : _mode == 2 ? "4-edge mesh " : "2-level FB " ) ;
  if (_mode == 1 || _mode == 2) cout << _ppr << "x" << _ppc
      << (_mode == 2 ? " (N/S/E/W neighbors only, XY routed)" : " (diam 2)");
  cout << endl;
  if (_ep_place) cout << "GlassFB EP-aware placement ON (tp=" << _tp_deg << " ep=" << _ep_deg << "): EP-mates -> same panel" << endl;
  if (_dim_route) cout << "GlassFB dimension-order load-balanced (Valiant) intra-panel routing ON" << endl;
  cout << "GlassFB distance-layered BW: elec(adj) " << (_elec_bw_mbps/8000.0)
       << " / opt(far) " << (_opt_bw_mbps/8000.0) << " / inter " << (_inter_bw_mbps/8000.0)
       << " GB/s; lat " << _elec_lat_ns << "/" << _opt_lat_ns << "/" << _inter_lat_ns << " ns" << endl;

  switchs.resize(_no_of_nodes, nullptr);
  pipes.resize(_no_of_nodes, vector<Pipe *>(_no_of_nodes));
  queues.resize(_no_of_nodes, vector<Queue *>(_no_of_nodes));
}

Queue *GlassFBTopology::alloc_src_queue(QueueLogger *queueLogger)
{
  return new PriorityQueue(speedFromMbps((uint64_t)SPEED), memFromPkt(FEEDER_BUFFER), *eventlist, queueLogger);
}

Queue *GlassFBTopology::alloc_queue(QueueLogger *queueLogger, mem_b queuesize)
{
  return alloc_queue(queueLogger, SPEED, queuesize);
}

Queue *GlassFBTopology::alloc_queue(QueueLogger *queueLogger, uint64_t speed, mem_b queuesize)
{
  if (qt == RANDOM)
    return new RandomQueue(speedFromMbps(speed), memFromPkt(SWITCH_BUFFER + RANDOM_BUFFER), *eventlist, queueLogger, memFromPkt(RANDOM_BUFFER));
  else if (qt == COMPOSITE)
    return new CompositeQueue(speedFromMbps(speed), queuesize, *eventlist, queueLogger);
  else if (qt == CTRL_PRIO)
    return new CtrlPrioQueue(speedFromMbps(speed), queuesize, *eventlist, queueLogger);
  else if (qt == ECN)
    return new ECNQueue(speedFromMbps(speed), queuesize, *eventlist, queueLogger, memFromPkt(_ecn_k_pkts));
  else if (qt == LOSSLESS)
    return new LosslessQueue(speedFromMbps(speed), memFromPkt(50), *eventlist, queueLogger, NULL);
  else if (qt == LOSSLESS_INPUT)
    return new LosslessOutputQueue(speedFromMbps(speed), memFromPkt(200), *eventlist, queueLogger);
  else if (qt == LOSSLESS_INPUT_ECN)
    return new LosslessOutputQueue(speedFromMbps(speed), memFromPkt(10000), *eventlist, queueLogger, 1, memFromPkt(16));
  assert(0);
}

void GlassFBTopology::init_network()
{
  QueueLoggerSampling *queueLogger = nullptr;

  for (int j = 0; j < _no_of_nodes; j++)
    for (int k = 0; k < _no_of_nodes; k++)
    {
      queues[j][k] = nullptr;
      pipes[j][k] = nullptr;
    }

  //create switches if we have lossless operation
  if (qt == LOSSLESS)
    for (int j = 0; j < _no_of_nodes; j++)
    {
      switchs[j] = new Switch("Switch_LowerPod_" + ntoa(j));
    }

  for (int j = 0; j < _no_of_nodes; j++)
  {
    for (int k = 0; k < j; k++)
    {
      // A direct link exists only for intra-panel FB pairs (same panel row/col)
      // or inter-panel optical gateway pairs. Everything else multi-hops (get_paths).
      if (!connected(j, k)) continue;

      // QueueLoggerSampling* queueLoggerd = new QueueLoggerSampling(timeFromMs(1000), *eventlist);
      // QueueLoggerSampling* queueLoggeru = new QueueLoggerSampling(timeFromMs(1000), *eventlist);
      // queueLogger = NULL;
      // logfile->addLogger(*queueLoggerd);
      // logfile->addLogger(*queueLoggeru);

      // per-link bandwidth: intra-panel glass vs inter-panel optical gateway
      uint64_t link_bw; uint32_t link_lat;
      if (intra_link(j, k)) {
        bool adj = adjacent_link(j, k);
        link_bw  = adj ? _elec_bw_mbps : _opt_bw_mbps;
        link_lat = adj ? _elec_lat_ns  : _opt_lat_ns;
      } else { link_bw = _inter_bw_mbps / _gw_parallel; link_lat = _inter_lat_ns; }
      queues[j][k] = alloc_queue(queueLogger, link_bw, _queuesize);
      queues[k][j] = alloc_queue(queueLogger, link_bw, _queuesize);
      queues[j][k]->setName("L" + ntoa(j) + "->DST" + ntoa(k));
      queues[k][j]->setName("L" + ntoa(k) + "->DST" + ntoa(j));
      // logfile->writeName(*(queues[j][k]));
      // logfile->writeName(*(queues[k][j]));

      pipes[j][k] = new Pipe(timeFromNs(link_lat), *eventlist);
      pipes[k][j] = new Pipe(timeFromNs(link_lat), *eventlist);
      pipes[j][k]->setName("Pipe-LS" + ntoa(j) + "->DST" + ntoa(k));
      pipes[k][j]->setName("Pipe-LS" + ntoa(k) + "->DST" + ntoa(j));
      // logfile->writeName(*(pipes[j][k]));
      // logfile->writeName(*(pipes[k][j]));

      if (qt == LOSSLESS)
      {
        switchs[j]->addPort(queues[j][k]);
        ((LosslessQueue *)queues[j][k])->setRemoteEndpoint(queues[k][j]);
        switchs[k]->addPort(queues[k][j]);
        ((LosslessQueue *)queues[k][j])->setRemoteEndpoint(queues[j][k]);
      }
      else if (qt == LOSSLESS_INPUT || qt == LOSSLESS_INPUT_ECN)
      {
        //no virtual queue needed at server
        new LosslessInputQueue(*eventlist, queues[k][j]);
        new LosslessInputQueue(*eventlist, queues[j][k]);
      }

      if (ff)
      {
        ff->add_queue(queues[j][k]);
        ff->add_queue(queues[k][j]);
      }
    }
  }

  //init thresholds for lossless operation
  if (qt == LOSSLESS)
    for (int j = 0; j < _queuesize; j++)
    {
      switchs[j]->configureLossless();
    }
}

// ???
void check_non_null(Route *rt)
{
  int fail = 0;
  for (unsigned int i = 1; i < rt->size() - 1; i += 2)
    if (rt->at(i) == NULL)
    {
      fail = 1;
      break;
    }

  if (fail)
  {
    //    cout <<"Null queue in route"<<endl;
    for (unsigned int i = 1; i < rt->size() - 1; i += 2)
      printf("%p ", rt->at(i));

    cout << endl;
    assert(0);
  }
}

// The topology is defined here in `get_paths`:
// since we only have 1 switch, the paths are pretty simple:

// Build the full hop-by-hop node sequence. Consecutive nodes are always directly
// linked (either an intra-panel FB link or an inter-panel optical link).
vector<int> GlassFBTopology::node_path(int src, int dest) const
{
  // waypoints: src, optional gateways, dest. Same-panel segments expand via
  // intra_relay; cross-panel transitions ride an optical gateway link.
  vector<int> wp;
  int p = panel(src), q = panel(dest);
  // which of the _gw_parallel parallel inter-panel links this flow uses -- spreads
  // the panel-pair's full a2a fan-in across multiple physical fibers instead of one.
  int g = gw_g(src, dest);
  if (p == q) {
    wp = {src, dest};
  } else if (_mode == 0 || panels_conn(p, q)) {
    // dragonfly, or (2-level FB / mesh) with directly-connected/adjacent panels: one hop
    wp = {src, gw(p, q, g), gw(q, p, g), dest};
  } else if (_mode == 2) {
    // mesh, non-adjacent panels: multi-hop XY dimension-order routing through however
    // many intermediate panels the grid distance requires. Each hop rides its own
    // dedicated edge (disjoint GPU pool -- see gw()/edge_local()), and any intra-panel
    // hop-to-hop turn within a pass-through panel is handled by the relay insertion
    // below exactly as for the existing single-relay cases.
    vector<int> pp = panel_path(p, q);
    wp.push_back(src);
    for (size_t i = 0; i + 1 < pp.size(); i++)
      wp.insert(wp.end(), {gw(pp[i], pp[i + 1], g), gw(pp[i + 1], pp[i], g)});
    wp.push_back(dest);
  } else {
    // 2-level FB, unconnected panels: relay through panel pm = (p's panel-row, q's panel-col)
    int pm = prow(p) * _ppc + pcol(q);
    wp = {src, gw(p, pm, g), gw(pm, p, g), gw(pm, q, g), gw(q, pm, g), dest};
  }

  vector<int> path;
  path.push_back(wp[0]);
  for (size_t i = 1; i < wp.size(); i++) {
    int a = path.back(), b = wp[i];
    if (a == b) continue;
    if (same_panel(a, b) && !intra_link(a, b))
      path.push_back(relay_for(a, b)); // 2-hop intra-panel FB (dim-order balanced if enabled)
    path.push_back(b);
  }
  return path;
}

vector<const Route *> *GlassFBTopology::get_paths(int src, int dest)
{
  vector<const Route *> *paths = new vector<const Route *>();
  route_t *routeout = new Route();
  route_t *routeback = new Route();

  vector<int> path = node_path(src, dest);
  // forward: hop by hop along the node sequence
  for (size_t i = 0; i + 1 < path.size(); i++) {
    int a = path[i], b = path[i + 1];
    routeout->push_back(queues[a][b]);
    routeout->push_back(pipes[a][b]);
    if (qt == LOSSLESS_INPUT || qt == LOSSLESS_INPUT_ECN)
      routeout->push_back(queues[a][b]->getRemoteEndpoint());
  }
  // reverse: walk the sequence backwards
  for (size_t i = path.size() - 1; i > 0; i--) {
    int a = path[i], b = path[i - 1];
    routeback->push_back(queues[a][b]);
    routeback->push_back(pipes[a][b]);
    if (qt == LOSSLESS_INPUT || qt == LOSSLESS_INPUT_ECN)
      routeback->push_back(queues[a][b]->getRemoteEndpoint());
  }

  routeout->set_reverse(routeback);
  routeback->set_reverse(routeout);
  paths->push_back(routeout);
  check_non_null(routeout);
  return paths;
}

void GlassFBTopology::count_queue(Queue *queue)
{
  if (_link_usage.find(queue) == _link_usage.end())
  {
    _link_usage[queue] = 0;
  }

  _link_usage[queue] = _link_usage[queue] + 1;
}

// Find lower pod switch:
int GlassFBTopology::find_lp_switch(Queue *queue)
{
  //first check ns_nlp
  for (int i = 0; i < _no_of_nodes; i++)
    for (int j = 0; j < _no_of_nodes; j++)
      if (queues[i][j] == queue)
        return j;

  //only count nup to nlp
  count_queue(queue);

  return -1;
}

int GlassFBTopology::find_destination(Queue *queue)
{
  //first check nlp_ns
  for (int i = 0; i < _no_of_nodes; i++)
    for (int j = 0; j < _no_of_nodes; j++)
      if (queues[i][j] == queue)
        return j;

  return -1;
}

void GlassFBTopology::print_path(std::ofstream &paths, int src, const Route *route)
{
  paths << "SRC_" << src << " ";

  if (route->size() / 2 == 2)
  {
    paths << "LS_" << find_lp_switch((Queue *)route->at(1)) << " ";
    paths << "DST_" << find_destination((Queue *)route->at(3)) << " ";
  }
  else
  {
    paths << "Wrong hop count " << ntoa(route->size() / 2);
  }

  paths << endl;
}

// UtilMonitor::UtilMonitor(GlassFBTopology* top, EventList &eventlist)
//   : EventSource(eventlist,"utilmonitor"), _top(top)
// {
//     _H = _top->no_of_nodes(); // number of hosts
//     uint64_t rate = 10000000000 / 8; // bytes / second
//     rate = rate * _H * _H;

//     _max_agg_Bps = rate;

//     // debug:
//     //cout << "max packets per second = " << rate << endl;

// }

// void UtilMonitor::start(simtime_picosec period) {
//     _period = period;
//     _max_B_in_period = _max_agg_Bps * timeAsSec(_period);

//     // debug:
//     //cout << "_max_pkts_in_period = " << _max_pkts_in_period << endl;

//     eventlist().sourceIsPending(*this, _period);
// }

// void UtilMonitor::doNextEvent() {
//     printAggUtil();
// }

// void UtilMonitor::printAggUtil() {

//     uint64_t B_sum = 0;

//     // int host = 0;
//     // for (int tor = 0; tor < _N; tor++) {
//     //     for (int downlink = 0; downlink < _hpr; downlink++) {
//     //         Pipe* pipe = _top->get_downlink(tor, host);
//     //         B_sum = B_sum + pipe->reportBytes();
//     //         host++;
//     //     }
//     // }
//     for (int i = 0; i < _H; i++) {
//       for (int j = 0; j < _H; j++) {
//         Pipe * pipe = _top->get_pipe(i, j);
//         if (pipe != nullptr) {
//           B_sum = B_sum + pipe->reportBytes();
//         }
//       }
//     }

//     // debug:
//     //cout << "Bsum = " << B_sum << endl;
//     //cout << "_max_B_in_period = " << _max_B_in_period << endl;

//     double util = (double)B_sum / (double)_max_B_in_period;

//     fct_util_out << "Util " << fixed << util << " " << timeAsMs(eventlist().now()) << endl;

//     //if (eventlist().now() + _period < eventlist().getEndtime())
//     eventlist().sourceIsPendingRel(*this, _period);

// }
