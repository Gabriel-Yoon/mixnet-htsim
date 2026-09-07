// Turns one decode_epN.json (written by LLMServingSim's
// scripts/export_decode_ep_sweep.py) into a TaskGraphProtoBuf .pb graph:
//   dispatch ALLTOALL (fan-out) -> N parallel per-rank expert FORWARD computes
//   -> combine ALLTOALL (fan-in), using the counter-based dependency scheme
//   load_taskgraph_protobuf() already understands.
//
// The per-expert-pair traffic SKEW is deliberately left to htsim's existing
// Zipf weight-matrix mechanism (-weightmatrix wm_epN.txt) at simulation time,
// exactly like the ASPDAC/DATE paper's training-side evaluation already does
// (Sec 5.1: "per-expert skew is a synthetic Zipf weight-matrix") -- this tool
// only carries the REAL aggregate volumes and REAL per-rank compute latency
// LLMServingSim computed from its GateRouter + profiled H100 MoE latency data.
//
// Usage: gen_decode_block <decode_epN.json> <out.pb>
#include "taskgraph.pb.h"
#include "json.hpp"
#include <fstream>
#include <iostream>
#include <sstream>

using json = nlohmann::json;

int main(int argc, char **argv) {
    if (argc != 3) {
        std::cerr << "usage: " << argv[0] << " <decode_epN.json> <out.pb>\n";
        return 1;
    }
    std::ifstream jf(argv[1]);
    if (!jf) { std::cerr << "cannot open " << argv[1] << "\n"; return 1; }
    json j; jf >> j;

    const int ep = j.at("ep").get<int>();
    const uint64_t total_dispatch_bytes = j.at("total_dispatch_bytes").get<uint64_t>();
    const uint64_t total_combine_bytes = j.at("total_combine_bytes").get<uint64_t>();
    const auto rank_latency_ns = j.at("rank_latency_ns").get<std::vector<double>>();
    if ((int)rank_latency_ns.size() != ep) {
        std::cerr << "rank_latency_ns size (" << rank_latency_ns.size()
                  << ") != ep (" << ep << ")\n";
        return 1;
    }

    TaskGraphProtoBuf::TaskGraph g;
    g.set_ngpupernode(ep);
    g.set_nnode(ep);                 // total device count (see load_taskgraph_protobuf)
    g.set_intergpubw(400.0f);
    g.set_drambw(0.0f);
    g.set_netbw(400.0f);
    g.set_dp_degree(1);
    g.set_tp_degree(1);
    g.set_pp_degree(1);
    g.set_ep_degree(ep);

    for (int i = 0; i < ep; i++) {
        auto *d = g.add_devices();
        d->set_type(TaskGraphProtoBuf::Device_DeviceType_DEVICE_GPU);
        d->set_deviceid(i);
        d->set_nodeid(i);
        d->set_gpuid(i);
    }

    // taskid layout: 1 = dispatch, 2..(ep+1) = per-rank expert compute, ep+2 = combine.
    const uint64_t DISPATCH_ID = 1;
    const uint64_t COMBINE_ID = (uint64_t)ep + 2;
    const bool emit_combine = (total_combine_bytes > 0);
    if (!emit_combine)
        std::cerr << "combine omitted (0 bytes): a floored one-MSS combine would be "
                     "17% of payload at M=8kB\n";

    // load_taskgraph_protobuf() reconstructs total_xfer_size = xfersize() * ep_degree,
    // then applies the -weightmatrix skew on top; xfersize is therefore the
    // ep-normalised (i.e. divided-by-ep) base value.
    auto *dispatch = g.add_tasks();
    dispatch->set_type(TaskGraphProtoBuf::Task_SimTaskType_TASK_ALLTOALL);
    dispatch->set_taskid(DISPATCH_ID);
    dispatch->set_deviceid(0);
    dispatch->set_opid(1);
    dispatch->set_runtime(0.0f);
    dispatch->set_xfersize(total_dispatch_bytes / (uint64_t)ep);
    dispatch->set_info("GROUP_BY forward"); // matches load_taskgraph_protobuf's dispatch-direction check
    dispatch->set_counter(0);               // ready immediately
    dispatch->set_name("decode_dispatch");
    for (int i = 0; i < ep; i++) { dispatch->add_from_node_ids(i); dispatch->add_to_node_ids(i); }
    for (int i = 0; i < ep; i++) dispatch->add_nexttasks(2 + i);

    for (int i = 0; i < ep; i++) {
        auto *c = g.add_tasks();
        c->set_type(TaskGraphProtoBuf::Task_SimTaskType_TASK_FORWARD);
        uint64_t tid = 2 + i;
        c->set_taskid(tid);
        c->set_deviceid(i);
        c->set_opid(tid);
        // FFTask::FFTask does run_time_ps = runtime * 1e9, and run_time is
        // simtime_picosec (ps); since 1ms = 1e9 ps, the "runtime" parameter's
        // expected unit is MILLISECONDS, not seconds (despite FlexFlow's own
        // dot-graph labelling its analogous field "secs" -- that label refers
        // to the *source* measurement, not this constructor's input unit).
        c->set_runtime((float)(rank_latency_ns[i] / 1.0e6)); // ns -> ms
        c->set_xfersize(0);
        c->set_info("expert");
        c->set_counter(1); // one predecessor: the dispatch task
        c->set_name("decode_expert_rank" + std::to_string(i));
        // A zero-byte combine is not free: every one of its flows is floored to one
        // MSS, which is 17% of the payload at M = 8 kB and would corrupt exactly the
        // small-message cells the calibration compares against hardware. When it has
        // no bytes it is not emitted, and the computes have no successor.
        if (emit_combine) c->add_nexttasks(COMBINE_ID);
    }

    if (emit_combine) {
    auto *combine = g.add_tasks();
    combine->set_type(TaskGraphProtoBuf::Task_SimTaskType_TASK_ALLTOALL);
    combine->set_taskid(COMBINE_ID);
    combine->set_deviceid(0);
    combine->set_opid(COMBINE_ID);
    combine->set_runtime(0.0f);
    combine->set_xfersize(total_combine_bytes / (uint64_t)ep);
    combine->set_info("AGGREGATE backward"); // matches load_taskgraph_protobuf's combine-direction check
    combine->set_counter(ep);                // waits on all ep expert-compute tasks
    combine->set_name("decode_combine");
    for (int i = 0; i < ep; i++) { combine->add_from_node_ids(i); combine->add_to_node_ids(i); }
    }

    std::string out;
    if (!g.SerializeToString(&out)) { std::cerr << "serialize failed\n"; return 1; }
    std::ofstream of(argv[2], std::ios::binary);
    of.write(out.data(), out.size());
    of.close();
    std::cerr << "wrote " << out.size() << " bytes -> " << argv[2]
              << " (ep=" << ep << ", " << g.tasks_size() << " tasks)\n";
    return 0;
}
