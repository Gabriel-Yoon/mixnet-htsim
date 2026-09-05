# MixNet-htsim simulator

This module contains the MixNet-htsim packet-level network simulator. It models the cluster that runs MoE training job with different interconnects. The source code was extended from the TopoOpt simulator from NSDI 2023 and Opera simulator from NSDI 2020, please check the original README file [here](OPERA_README.md).

## Compilation:
To build the MixNet-htsim simulator, from the top level directory run:
```bash
cd src/clos
make
cd datacenter
make
```
We also provide convinent compile scripts [here](./mixnet_scripts/compile.sh)

## Executables

The executables are found in the `src/clos/datacenter` folder. They have the name "htsim_...". The following table provides details on each executable:

| Executable | Network Topology |
|------------|------------------|
| `htsim_tcp_fattree`       | Fat-Tree network topology, single job |
| `htsim_tcp_os_fattree`    | Oversubscribed Fat-Tree where the ToR switches are oversubscribed |
| `htsim_tcp_mixnet`        | Runtime reconfigurable optical-electrical fabric for distributed Mixture-of-Experts training |

## Brief description on source code

MixNet-htsim's major extension from the htsim simulator allows it to take a taskgraph (in FlatBuffer) generated from the FlexFlow DNN training simulator. To achieve this, `src/clos/ffapp.*` was implemented as an API to read and process these such taskgraphs. In addition, a few network topologies are added, notably the dynamic network executable that simulates SiP-ML. The mixnet topology logic can be found in `src/clos/datacenter/mixnet.*` and the regional reconfiguration logic for mixnet is implemented in `src/clos/mixnet_topomanager.*`.

Each topology's "main" function can be found in `src/clos/datacenter/main_tcp_*.cpp`, which provides detailed description on the input arguments for the executable. 

## `wafer-topology` branch additions

This branch adds a Glass-Photonic Flattened-Butterfly (Glass-FB) topology
(`src/clos/datacenter/glassfb_topology.*`, `htsim_tcp_glassfb`) and a wafer-scale
row/col comparison topology (`wafer_rowcol_topology.*`, `htsim_tcp_wafer`), plus:

- **Serving-sim bridge (protobuf task graphs)**: `htsim_tcp_glassfb`/`_fattree`/`_flat`
  accept a `.pb` flowfile (`TaskGraphProtoBuf`, `src/clos/taskgraph.proto`) as an
  alternative to the FlexFlow FlatBuffer format, for bridging real routing/profiling
  data from LLMServingSim's decode/prefill simulation into htsim.
  `src/clos/gen_decode_block.cpp` turns a small JSON
  export (`ep`, per-rank compute latency, dispatch/combine byte counts) into a `.pb`
  graph. Requires `protobuf` + `abseil` (`brew install protobuf abseil` on macOS);
  `mixnet_scripts/compile.sh` picks these up via `pkg-config` automatically.
- **`GLASS_ECN_K`** (env var, default 50 packets): ECN marking threshold for the
  `ECN` queue type, previously hardcoded.
- **`GLASS_GW_PARALLEL`** (env var, default 1 = prior behavior): spreads a panel
  pair's inter-panel traffic across `G` parallel gateway GPU pairs (hashed by
  in-panel position) instead of funneling all of it through one fixed pair, at the
  same total inter-panel bandwidth. See `glassfb_topology.h`'s `gw()`/`gw_g()`.
  Clamps to the largest feasible `G` for the current `GLASS_INTER` mode (see below).
- **`GLASS_INTER=mesh`** (in addition to the existing default dragonfly and `fb2`):
  a true 4-edge mesh -- a panel connects only to its immediate N/S/E/W neighbors in
  the `_ppr x _ppc` panel grid, each direction backed by one dedicated, disjoint
  4-GPU edge (a full row/column of the panel's own 4x4 grid; see `edge_local()`/
  `mesh_neighbor()`). `fb2`'s "connect to everyone in my row or column" graph has
  degree up to `(ppr-1)+(ppc-1)` (e.g. 10 on a 32-panel 8x4 grid) with no physical
  4-port realization; `mesh` is the physically-honest alternative, at the cost of
  needing multi-hop (XY dimension-order, `panel_path()`) routing between
  non-adjacent panels. Under `mesh`, `GLASS_GW_PARALLEL` is capped at 4 (the fixed
  edge-pool size) regardless of how many of the panel's other edges are active,
  rather than `panel_size / panel_degree()` as in the other two modes.

Build: `FF_HOME=<path with fbuf/include, or a dir symlinking flatbuffers'
include/> bash mixnet_scripts/compile.sh`. Other environment knobs for
`htsim_tcp_glassfb` (panel size, EP-aware placement, per-tier bandwidths) are
listed at the top of `glassfb_topology.cpp`'s `set_params()`.

