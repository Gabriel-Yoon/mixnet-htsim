#pragma once
#include <vector>
#include <cstdint>
#include "topology.h"
#include "eventlist.h"
#include "randomqueue.h"
#include "pipe.h"
#include "logfile.h"
#include "firstfit.h"

struct WaferConfig {
  int wafer_rows = 4;
  int wafer_cols = 4;

  // total GPUs in the simulation (must match fbuf nnode)
  int total_gpus = 0;

  // link params
  uint64_t intra_link_speed = 0;     // same unit as other topologies use (e.g., bps or pkt/s depending on repo)
  simtime_picosec intra_link_delay = 0;

  uint64_t inter_link_speed = 0;
  simtime_picosec inter_link_delay = 0;

  // Inter-wafer model:
  //   0 = per-wafer-pair gateway (legacy): one directed link of inter_link_speed between one
  //       gateway GPU of wafer A and one of wafer B; every A->B flow detours to the gateway.
  //   1 = per-reticle CPO port: every GPU has its own off-wafer egress and ingress port of
  //       inter_link_speed (Section 3.2's co-packaged-optics connectors), and an off-wafer flow
  //       goes src port -> fibre -> dst port with no intra-wafer detour. Port contention is
  //       modelled by the shared per-GPU egress/ingress queues.
  int inter_mode = 0;

  // Demand-aware wavelength allocation (non-volatile programmable ring array):
  // link_demand[s][d] = expected traffic from GPU s to GPU d (any unit). When non-empty, every
  // source keeps its total wavelength budget (num_out_links x intra_link_speed) but splits it
  // across its outgoing intra-wafer links in proportion to the traffic those links carry, with
  // a floor of alloc_floor x the uniform share per link. Empty = uniform (unchanged behaviour).
  std::vector<std::vector<double>> link_demand;
  double alloc_floor = 0.1;
  double alloc_cap = 2.0;     // max share per link, x uniform (= receiver ring over-provisioning factor)
  bool alloc_inter = false;   // also reallocate the inter-wafer gateway links

  int gpus_per_wafer() const { return wafer_rows * wafer_cols; }
  int num_wafers() const { return (total_gpus + gpus_per_wafer() - 1) / gpus_per_wafer(); }
};

class WaferRowColTopology : public Topology {
public:
  WaferRowColTopology(
      const WaferConfig& cfg,
      mem_b queuesize,
      Logfile* logfile,
      EventList* eventlist,
      FirstFit* ff);

  // Main API used by FFApp
  virtual std::vector<const Route*>* get_paths(int src, int dst) override;

  // Optional: if other code calls get_eps_paths, just alias to get_paths
  virtual std::vector<const Route*>* get_eps_paths(int src, int dst) override { return get_paths(src, dst); }

  virtual std::vector<int>* get_neighbours(int src) override;

  virtual int no_of_nodes() const override { return cfg_.total_gpus; }

  // You may need to implement other pure virtuals depending on your Topology base.
  // If compiler complains, add stubs consistent with other topology implementations.

private:
  WaferConfig cfg_;
  mem_b queuesize_;
  EventList* eventlist_;
  Logfile* logfile_;
  FirstFit* ff_;

  // We build explicit directed links for:
  // (1) intra-wafer row/col edges between every pair in same row or same col
  // (2) inter-wafer edges between wafer gateways (or between all GPUs; gateway model is cheaper)
  //
  // Inter-wafer gateway is PER-DESTINATION-WAFER, not a single fixed GPU: wafer w's link toward
  // wafer o uses local GPU (rank of o among w's other wafers) % W() as the gateway. This spreads
  // a wafer's (num_wafers-1) inter-wafer links across up to W() distinct local GPUs instead of
  // funneling ALL inter-wafer traffic through one GPU (local index 0), which was a severe
  // single-queue bottleneck under heavy all-to-all traffic (confirmed: full-scale seq4096/32-layer
  // runs failed to complete in 30min-3hr with the old fixed-gateway scheme).
  // Path: src -> gw(src wafer, dst wafer) -> gw(dst wafer, src wafer) -> dst
  //
  // Store queues/pipes for any directed pair we might use.
  std::vector<std::vector<RandomQueue*>> q_;
  std::vector<std::vector<Pipe*>> p_;
  // per-reticle CPO ports (inter_mode 1)
  std::vector<RandomQueue*> port_out_;
  std::vector<RandomQueue*> port_in_;
  std::vector<Pipe*> port_pipe_;

  inline int W() const { return cfg_.gpus_per_wafer(); }
  inline int wafer_id(int g) const { return g / W(); }
  inline int local_id(int g) const { return g % W(); }
  inline int row(int g) const { return local_id(g) / cfg_.wafer_cols; }
  inline int col(int g) const { return local_id(g) % cfg_.wafer_cols; }
  // rank of wafer `other` among wafer `w`'s (num_wafers-1) other wafers (0-based, excludes w itself)
  inline int other_wafer_rank(int w, int other) const { return other < w ? other : other - 1; }
  // gateway GPU that wafer `w` uses for its link toward wafer `other` (wraps if num_wafers-1 > W())
  inline int gateway_gpu(int w, int other) const { return w * W() + (other_wafer_rank(w, other) % W()); }
  inline bool same_wafer(int a, int b) const { return wafer_id(a) == wafer_id(b); }

  int intersection_gpu(int src, int dst) const;

  // directed (u,v) link sequence of the route get_paths() would build for src->dst
  std::vector<std::pair<int,int>> hops(int src, int dst) const;
  // per-link speeds after demand-aware allocation (Mbps); empty when uniform
  std::vector<std::vector<uint64_t>> alloc_speed_;
  void compute_allocation();

  void add_link(int u, int v, uint64_t speed, simtime_picosec delay);
};