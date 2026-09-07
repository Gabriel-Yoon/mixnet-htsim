// Dump the topology's OWN per-tier hop classification, without simulating traffic.
//
// WHY THIS EXISTS. tier_bytes.sh gets the split by running the whole simulation
// with GLASS_LOG_HOPS=1, which is correct and takes hours; at EP=128 that is
// slower than the rungs it would inform. The alternative on the table was to
// reimplement gw(), relay_for() and the port-map graph in Python and validate the
// reimplementation against the hop logs. This is the third option: build the same
// topology object the runner builds, ask it for the same routes, and let it emit
// its own hoplog lines. Nothing is reimplemented, so nothing can drift.
//
// It is sound because node_path() is a pure function of (src, dest) and the
// configuration. relay_for() picks its intra-panel relay from a fixed hash of
// (a, b), and gw_g() from (loc(src) + loc(dst)) % n -- no RNG, no counters, no
// dependence on traffic or on the order pairs are asked for. That is the claim
// the EP=16/32/64 diff against the real runs' hop logs is there to test.
//
// Pairs come from a flow log on stdin ("flowlog: src dst bytes"), so the dump
// covers exactly the pairs that carry traffic -- the same set the run would have
// routed, and no more.
#include "config.h"
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <set>
#include <sstream>
#include <string>
#include "network.h"
#include "eventlist.h"
#include "logfile.h"
#include "loggers.h"
#include "clock.h"
#include "compositequeue.h"
#include "firstfit.h"
#include "topology.h"
#include "glassfb_topology.h"

// Globals the linked objects expect, with main_tcp_glassfb.cpp's values.
uint32_t RTT_rack = 500;
uint32_t RTT_net = 500;
uint32_t RTT = 1000;
uint32_t SPEED = 40000;
std::ofstream fct_util_out;
FirstFit *ff = NULL;
EventList eventlist;
Logfile *lg = NULL;

// Defined in main_tcp_glassfb.cpp, which this deliberately does not link
// (see the Makefile rule); glassfb_topology.o calls it from init_network().
std::string ntoa(double n) { std::stringstream s; s << n; return s.str(); }
std::string itoa(uint64_t n) { std::stringstream s; s << n; return s.str(); }

int main(int argc, char **argv)
{
    int no_of_nodes = 128;
    int qpkts = 1064;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-nodes") && i + 1 < argc) no_of_nodes = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-q") && i + 1 < argc) qpkts = atoi(argv[++i]);
        else { std::cerr << "unknown argument " << argv[i] << std::endl; return 2; }
    }

    // The hop log is what we are here for; refuse to run silently without it
    // rather than produce an empty dump.
    if (getenv("GLASS_LOG_HOPS") == NULL) {
        std::cerr << "FATAL: GLASS_LOG_HOPS is not set -- nothing would be emitted"
                  << std::endl;
        return 2;
    }

    Packet::set_packet_size(1500);
    eventlist.setEndtime(timeFromSec(1));

    mem_b queuesize = memFromPkt(qpkts);
    GlassFBTopology *top =
        new GlassFBTopology(no_of_nodes, queuesize, NULL, &eventlist, ff, ECN);

    // Pairs from a flow log on stdin. Duplicates are cheap to skip here and the
    // topology skips them again, but doing it here keeps the work proportional
    // to distinct pairs rather than to flows -- 4.7M lines at EP=128.
    std::set<std::pair<int, int> > seen;
    std::string line;
    long lines = 0, pairs = 0, skipped = 0;
    while (std::getline(std::cin, line)) {
        std::istringstream is(line);
        std::string tag;
        int s, d;
        long long b;
        if (!(is >> tag >> s >> d >> b)) continue;
        if (tag != "flowlog:") continue;
        lines++;
        if (b == 0) { skipped++; continue; }
        if (s < 0 || d < 0 || s >= no_of_nodes || d >= no_of_nodes) {
            std::cerr << "FATAL: pair (" << s << "," << d << ") outside 0.."
                      << no_of_nodes - 1 << std::endl;
            return 2;
        }
        if (s == d) { skipped++; continue; }
        if (!seen.insert(std::make_pair(s, d)).second) continue;
        pairs++;
        top->get_paths(s, d);          // emits one hoplog line per new pair
    }
    std::cerr << "hopdump: " << lines << " flowlog line(s), " << skipped
              << " zero-byte or self, " << pairs << " distinct pair(s) routed"
              << std::endl;
    return 0;
}
