#include "wafer_rowcol_topology.h"
#include <cassert>
#include <algorithm>
#include <iostream>

WaferRowColTopology::WaferRowColTopology(
    const WaferConfig& cfg,
    mem_b queuesize,
    Logfile* logfile,
    EventList* eventlist,
    FirstFit* ff)
: cfg_(cfg), queuesize_(queuesize), eventlist_(eventlist), logfile_(logfile), ff_(ff)
{
  assert(cfg_.total_gpus > 0);
  int N = cfg_.total_gpus;

  q_.assign(N, std::vector<RandomQueue*>(N, nullptr));
  p_.assign(N, std::vector<Pipe*>(N, nullptr));

  if (!cfg_.link_demand.empty()) compute_allocation();
  auto speed_of = [&](int u, int v, uint64_t uniform) -> uint64_t {
    if (alloc_speed_.empty() || alloc_speed_[u][v] == 0) return uniform;
    return alloc_speed_[u][v];
  };

  // Build intra-wafer row/col links (directed).
  for (int g = 0; g < N; ++g) {
    for (int h = 0; h < N; ++h) {
      if (g == h) continue;
      if (!same_wafer(g, h)) continue;

      if (row(g) == row(h) || col(g) == col(h)) {
        add_link(g, h, speed_of(g, h, cfg_.intra_link_speed), cfg_.intra_link_delay);
      }
    }
  }

  if (cfg_.inter_mode == 1) {
    // per-reticle CPO ports: one egress and one ingress queue per GPU at the port rate
    port_out_.assign(N, nullptr); port_in_.assign(N, nullptr); port_pipe_.assign(N, nullptr);
    for (int g = 0; g < N; ++g) {
      port_out_[g] = new RandomQueue(speedFromMbps(cfg_.inter_link_speed), memFromPkt(SWITCH_BUFFER + RANDOM_BUFFER),
                                     *eventlist_, nullptr, memFromPkt(RANDOM_BUFFER));
      port_in_[g] = new RandomQueue(speedFromMbps(cfg_.inter_link_speed), memFromPkt(SWITCH_BUFFER + RANDOM_BUFFER),
                                    *eventlist_, nullptr, memFromPkt(RANDOM_BUFFER));
      port_pipe_[g] = new Pipe(cfg_.inter_link_delay, *eventlist_);
    }
    std::cout << "Inter-wafer model: per-reticle CPO port, " << cfg_.inter_link_speed / 8000
              << " GB/s egress + ingress per GPU, " << cfg_.inter_link_delay / 1000 << " ns" << std::endl;
    return;
  }
  std::cout << "Inter-wafer model: per-wafer-pair gateway, " << cfg_.inter_link_speed / 8000 << " GB/s per link" << std::endl;

  // Build inter-wafer links between gateways (directed, fully connected among wafers).
  // Per-destination-wafer gateway assignment spreads each wafer's (nw-1) inter-wafer links
  // across up to W() distinct local GPUs instead of funneling all of them through local GPU 0.
  int nw = cfg_.num_wafers();
  for (int w1 = 0; w1 < nw; ++w1) {
    for (int w2 = 0; w2 < nw; ++w2) {
      if (w1 == w2) continue;
      int g1 = gateway_gpu(w1, w2);
      int g2 = gateway_gpu(w2, w1);
      if (g1 < N && g2 < N) {
        add_link(g1, g2, cfg_.alloc_inter ? speed_of(g1, g2, cfg_.inter_link_speed) : cfg_.inter_link_speed,
                 cfg_.inter_link_delay);
      }
    }
  }

  // Also ensure every GPU can reach its gateway inside wafer (row/col should already connect,
  // but if gateway not in same row/col, intersection routing will cover.)
}

void WaferRowColTopology::add_link(int u, int v, uint64_t speed_mbps, simtime_picosec delay)
{
  if (q_[u][v] != nullptr) return;

  QueueLogger* queueLogger = nullptr;

  // flat_topology.cpp와 동일한 RandomQueue 생성 방식
  q_[u][v] = new RandomQueue(
      speedFromMbps(speed_mbps),
      memFromPkt(SWITCH_BUFFER + RANDOM_BUFFER),
      *eventlist_,
      queueLogger,
      memFromPkt(RANDOM_BUFFER)
  );

  p_[u][v] = new Pipe(delay, *eventlist_);
}

std::vector<std::pair<int,int>> WaferRowColTopology::hops(int src, int dst) const
{
  std::vector<std::pair<int,int>> h;
  if (src == dst) return h;
  auto intra = [&](int a, int b) {
    if (a == b) return;
    if (row(a) == row(b) || col(a) == col(b)) {
      h.emplace_back(a, b);
    } else {
      int mid = intersection_gpu(a, b);
      h.emplace_back(a, mid);
      h.emplace_back(mid, b);
    }
  };
  if (same_wafer(src, dst)) {
    intra(src, dst);
    return h;
  }
  if (cfg_.inter_mode == 1) return h;   // CPO port path uses no intra-wafer links
  int gwS = gateway_gpu(wafer_id(src), wafer_id(dst));
  int gwD = gateway_gpu(wafer_id(dst), wafer_id(src));
  intra(src, gwS);
  h.emplace_back(gwS, gwD);
  intra(gwD, dst);
  return h;
}

void WaferRowColTopology::compute_allocation()
{
  int N = cfg_.total_gpus;
  assert((int)cfg_.link_demand.size() == N);
  std::vector<std::vector<double>> load(N, std::vector<double>(N, 0.0));
  for (int s = 0; s < N; ++s)
    for (int d = 0; d < N; ++d) {
      double dem = cfg_.link_demand[s][d];
      if (dem <= 0.0) continue;
      for (auto& e : hops(s, d)) load[e.first][e.second] += dem;
    }

  alloc_speed_.assign(N, std::vector<uint64_t>(N, 0));
  double ratio_min = 1e9, ratio_max = 0.0;
  int nw = cfg_.num_wafers();
  for (int u = 0; u < N; ++u) {
    // two link classes per source: intra-wafer (row/col) and, if it is a gateway, inter-wafer
    for (int cls = 0; cls < 2; ++cls) {
      if (cls == 1 && !cfg_.alloc_inter) break;
      std::vector<int> outs;
      for (int v = 0; v < N; ++v) {
        if (v == u) continue;
        bool intra_link = same_wafer(u, v) && (row(u) == row(v) || col(u) == col(v));
        bool inter_link = false;
        if (!same_wafer(u, v)) {
          int w = wafer_id(v);
          inter_link = (gateway_gpu(wafer_id(u), w) == u) && (gateway_gpu(w, wafer_id(u)) == v) && w < nw;
        }
        if ((cls == 0 && intra_link) || (cls == 1 && inter_link)) outs.push_back(v);
      }
      if (outs.empty()) continue;
      uint64_t uniform = (cls == 0) ? cfg_.intra_link_speed : cfg_.inter_link_speed;
      double total = (double)uniform * outs.size();   // fixed wavelength budget per source
      double sum = 0.0;
      for (int v : outs) sum += load[u][v];
      if (sum <= 0.0) continue;                          // no demand information: stay uniform
      double floor_w = cfg_.alloc_floor * (sum / outs.size());
      double wsum = 0.0;
      std::vector<double> w(outs.size());
      for (size_t i = 0; i < outs.size(); ++i) { w[i] = std::max(load[u][outs[i]], floor_w); wsum += w[i]; }
      std::vector<double> sp(outs.size());
      for (size_t i = 0; i < outs.size(); ++i) sp[i] = total * w[i] / wsum;
      // cap: a receiver only has alloc_cap x the uniform ring count per source; redistribute
      // the excess of capped links to the uncapped ones (keeps the source budget constant)
      double cap = cfg_.alloc_cap * (double)uniform;
      for (int iter = 0; iter < 4; ++iter) {
        double excess = 0.0, uncapped = 0.0;
        for (size_t i = 0; i < outs.size(); ++i) {
          if (sp[i] > cap) { excess += sp[i] - cap; sp[i] = cap; } else uncapped += sp[i];
        }
        if (excess <= 0.0 || uncapped <= 0.0) break;
        for (size_t i = 0; i < outs.size(); ++i) if (sp[i] < cap) sp[i] += excess * sp[i] / uncapped;
      }
      for (size_t i = 0; i < outs.size(); ++i) {
        alloc_speed_[u][outs[i]] = (uint64_t)sp[i];
        double r = sp[i] / (double)uniform;
        ratio_min = std::min(ratio_min, r); ratio_max = std::max(ratio_max, r);
      }
    }
  }
  std::cout << "Wavelength allocation: demand-aware, per-link rate ratio to uniform in ["
            << ratio_min << ", " << ratio_max << "], floor " << cfg_.alloc_floor << ", cap " << cfg_.alloc_cap
            << (cfg_.alloc_inter ? ", inter-wafer links included" : ", intra-wafer links only") << std::endl;
}

int WaferRowColTopology::intersection_gpu(int src, int dst) const
{
  // Choose intersection at (row(src), col(dst)) within same wafer
  assert(same_wafer(src, dst));
  int w = wafer_id(src);
  int rr = row(src);
  int cc = col(dst);
  int local = rr * cfg_.wafer_cols + cc;
  return w * W() + local;
}

std::vector<int>* WaferRowColTopology::get_neighbours(int src)
{
  auto* nbrs = new std::vector<int>();
  int N = cfg_.total_gpus;
  if (src < 0 || src >= N) return nbrs;

  // 같은 wafer 내에서 같은 row/col로 직접 연결된 노드들
  for (int dst = 0; dst < N; ++dst) {
    if (dst == src) continue;

    if (same_wafer(src, dst) && (row(src) == row(dst) || col(src) == col(dst))) {
      nbrs->push_back(dst);
    }
  }

  if (cfg_.inter_mode == 1) {
    for (int dst = 0; dst < N; ++dst) if (!same_wafer(src, dst)) nbrs->push_back(dst);
    return nbrs;
  }
  // inter-wafer: src may be the per-destination gateway for one or more other wafers now
  // (gateway assignment is spread across local GPUs, not a single fixed GPU per wafer).
  int wsrc = wafer_id(src);
  int nw = cfg_.num_wafers();
  for (int w = 0; w < nw; ++w) {
    if (w == wsrc) continue;
    if (gateway_gpu(wsrc, w) != src) continue; // src isn't the gateway toward wafer w
    int gdst = gateway_gpu(w, wsrc);
    if (gdst >= 0 && gdst < N) nbrs->push_back(gdst);
  }

  return nbrs;
}

std::vector<const Route*>* WaferRowColTopology::get_paths(int src, int dst)
{
  auto* paths = new std::vector<const Route*>();
  if (src == dst) {
    // empty path is okay in some implementations, but safer to return a 0-hop route:
    Route* r = new Route();
    paths->push_back(r);
    return paths;
  }

  int N = cfg_.total_gpus;
  assert(src >= 0 && src < N && dst >= 0 && dst < N);

  Route* route = new Route();

  // Case 1: same wafer
  if (same_wafer(src, dst)) {
    // 1-hop if same row or col
    if (row(src) == row(dst) || col(src) == col(dst)) {
      assert(q_[src][dst] && p_[src][dst]);
      route->push_back(q_[src][dst]);
      route->push_back(p_[src][dst]);
    } else {
      // 2-hop via intersection
      int mid = intersection_gpu(src, dst);

      // src -> mid must exist (same row)
      assert(q_[src][mid] && p_[src][mid]);
      route->push_back(q_[src][mid]);
      route->push_back(p_[src][mid]);

      // mid -> dst must exist (same col)
      assert(q_[mid][dst] && p_[mid][dst]);
      route->push_back(q_[mid][dst]);
      route->push_back(p_[mid][dst]);
    }

    paths->push_back(route);
    return paths;
  }

  // Case 2: different wafers
  if (cfg_.inter_mode == 1) {
    // src CPO egress port -> fibre -> dst CPO ingress port (no intra-wafer detour)
    route->push_back(port_out_[src]);
    route->push_back(port_pipe_[src]);
    route->push_back(port_in_[dst]);
    route->push_back(port_pipe_[dst]);
    paths->push_back(route);
    return paths;
  }
  // Route via gateways: src -> gwS (intra), gwS -> gwD (inter), gwD -> dst (intra)
  int gwS = gateway_gpu(wafer_id(src), wafer_id(dst));
  int gwD = gateway_gpu(wafer_id(dst), wafer_id(src));

  // src -> gwS inside wafer (1 or 2 hops)
  if (src != gwS) {
    if (row(src) == row(gwS) || col(src) == col(gwS)) {
      assert(q_[src][gwS] && p_[src][gwS]);
      route->push_back(q_[src][gwS]);
      route->push_back(p_[src][gwS]);
    } else {
      int mid = intersection_gpu(src, gwS);
      assert(q_[src][mid] && p_[src][mid]);
      route->push_back(q_[src][mid]);
      route->push_back(p_[src][mid]);
      assert(q_[mid][gwS] && p_[mid][gwS]);
      route->push_back(q_[mid][gwS]);
      route->push_back(p_[mid][gwS]);
    }
  }

  // gwS -> gwD inter-wafer
  assert(q_[gwS][gwD] && p_[gwS][gwD]);
  route->push_back(q_[gwS][gwD]);
  route->push_back(p_[gwS][gwD]);

  // gwD -> dst inside wafer (1 or 2 hops)
  if (gwD != dst) {
    if (row(gwD) == row(dst) || col(gwD) == col(dst)) {
      assert(q_[gwD][dst] && p_[gwD][dst]);
      route->push_back(q_[gwD][dst]);
      route->push_back(p_[gwD][dst]);
    } else {
      int mid = intersection_gpu(gwD, dst);
      assert(q_[gwD][mid] && p_[gwD][mid]);
      route->push_back(q_[gwD][mid]);
      route->push_back(p_[gwD][mid]);
      assert(q_[mid][dst] && p_[mid][dst]);
      route->push_back(q_[mid][dst]);
      route->push_back(p_[mid][dst]);
    }
  }

  paths->push_back(route);
  return paths;
}