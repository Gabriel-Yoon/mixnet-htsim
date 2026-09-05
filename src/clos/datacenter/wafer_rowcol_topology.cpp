#include "wafer_rowcol_topology.h"
#include <cassert>

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

  // Build intra-wafer row/col links (directed).
  for (int g = 0; g < N; ++g) {
    for (int h = 0; h < N; ++h) {
      if (g == h) continue;
      if (!same_wafer(g, h)) continue;

      if (row(g) == row(h) || col(g) == col(h)) {
        add_link(g, h, cfg_.intra_link_speed, cfg_.intra_link_delay);
      }
    }
  }

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
        add_link(g1, g2, cfg_.inter_link_speed, cfg_.inter_link_delay);
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