// -*- c-basic-offset: 4; tab-width: 8; indent-tabs-mode: t -*-
// Driver for WaferRowColTopology: imec-style system-on-wafer topology (NxM GPUs/wafer,
// row/col intra-wafer mesh, gateway-based inter-wafer routing). See wafer_rowcol_topology.h.
#include "config.h"
#include <sstream>
#include <strstream>
#include <fstream>
#include <iostream>
#include <string.h>
#include <math.h>
#include <cassert>
#include <chrono>
#include <iomanip>
#include <filesystem>
#include <unistd.h>
#include "network.h"
#include "randomqueue.h"
#include "pipe.h"
#include "eventlist.h"
#include "logfile.h"
#include "loggers.h"
#include "clock.h"
#include "tcp.h"
#include "mtcp.h"
#include "compositequeue.h"
#include "firstfit.h"
#include "topology.h"

#include "wafer_rowcol_topology.h"
#include "ffapp.h"

void load_weight_matrix(std::string & weight_matrix_file, std::vector<std::vector<int>> &weight_matrix);

#include <list>

#define PRINT_PATHS 0
#define PERIODIC 0
#include "main.h"

uint32_t RTT_rack = 500; // ns
uint32_t RTT_net = 500;  // ns
uint32_t RTT = 1000;     // ns (per-link)
uint32_t SPEED;
std::ofstream fct_util_out;

int DEFAULT_NODES = 128;

FirstFit *ff = NULL;

#define DEFAULT_PACKET_SIZE 1500
#define DEFAULT_HEADER_SIZE 64
#define DEFAULT_QUEUE_SIZE 200

#define DEFAULT_SPEED 40000

string ntoa(double n);
string itoa(uint64_t n);

EventList eventlist;
Logfile *lg;

void exit_error(char *progr, char *param)
{
    cerr << "Bad parameter: " << param << endl;
    cerr << "Usage " << progr << " [UNCOUPLED(DEFAULT)|COUPLED_INC|FULLY_COUPLED|COUPLED_EPSILON] [epsilon][COUPLED_SCALABLE_TCP]" << endl;
    exit(1);
}

std::string getCurrentDateTime() {
    auto now = std::chrono::system_clock::now();
    std::time_t now_time = std::chrono::system_clock::to_time_t(now);
    std::tm* now_tm = std::localtime(&now_time);

    std::ostringstream oss;
    oss << std::put_time(now_tm, "%m-%d-%H-%M-%S");
    return oss.str();
}

std::string getExecutableName() {
    char buffer[1024];
    ssize_t count = readlink("/proc/self/exe", buffer, sizeof(buffer));
    if (count != -1) {
        std::filesystem::path execPath(std::string(buffer, count));
        return execPath.filename().string();
    } else {
        std::cerr << "Error reading the executable path." << std::endl;
        return "";
    }
}

int main(int argc, char **argv)
{
    // Packet size (bytes, incl. header): overridable via -mtu so cross-topology runs can
    // be pinned to the same *byte* buffer via -q instead of silently differing (flat/
    // mixnet default to 9000B jumbo frames while this binary defaults to 1500B -- the
    // same -q value then means a ~6x different queuesize in bytes between them).
    int packet_size = DEFAULT_PACKET_SIZE;
    for (int pre_i = 1; pre_i < argc - 1; pre_i++)
        if (!strcmp(argv[pre_i], "-mtu")) { packet_size = atoi(argv[pre_i + 1]); break; }
    TcpPacket::set_packet_size(packet_size - DEFAULT_HEADER_SIZE); // MTU
    mem_b queuesize = DEFAULT_QUEUE_SIZE * packet_size;

    int algo = UNCOUPLED;
    double epsilon = 1;
    int ssthresh = 15;

    int no_of_nodes = DEFAULT_NODES;
    SPEED = DEFAULT_SPEED;

    string flowfile = "../../../test/taskgraph.fbuf";
    string weight_matrix_file = "../../../test/num_global_tokens_per_expert.txt";
    string logdir = "";
    string ofile = "";

    double simtime;
    double utiltime = .01;

    // WaferConfig defaults: 4x4=16 GPUs/wafer (matches the ICCAD2026 manuscript's "each wafer
    // integrates a 4x4 GPU array"); link speeds default to the project's established
    // distance-layered numbers (elec 1800 GB/s intra-node-adjacent-class RDL link, 200 GB/s
    // inter-wafer optical fiber gateway) -- override via CLI for a DSE sweep.
    int wafer_rows = 4, wafer_cols = 4;
    uint64_t intra_speed_mbps = 1800ULL * 8000; // 1800 GB/s (GB/s -> Mbit/s: x8000, matches glassfb_topology.cpp's convention)
    uint64_t inter_speed_mbps = 200ULL * 8000;  // 200 GB/s
    simtime_picosec intra_delay_ps = 78000;   // 78 ns: real link propagation delay (physical constant,
                                               // applied per-packet -- NOT the thermal tuning delay)
    simtime_picosec inter_delay_ps = 500000;  // 500 ns
    bool disable_intra_shortcut = true; // wafer topology should route through get_paths, not NVLink shortcut
    simtime_picosec thermal_delay_ps = 0;     // one-time per-all-to-all-round stall (ring-modulator
                                               // wavelength re-lock time); see -thermal-delay (ns)
    // Demand-aware wavelength allocation (see WaferConfig::link_demand). The allocation is
    // computed from an expert-to-expert token matrix (default: the -weightmatrix file, i.e. the
    // allocation matches the traffic; pass -alloc-matrix to allocate from a stale/other matrix).
    // GPU->expert mapping mirrors ffapp: expert(g) = (g / tp) % ep, EP group = block of tp*ep GPUs.
    std::string lambda_alloc = "uniform";
    std::string alloc_matrix_file = "";
    double alloc_floor = 0.1;
    double alloc_cap = 2.0;
    bool alloc_inter = false;
    int alloc_tp = 1;
    bool a2a_symmetric = false;
    std::string dump_traffic_file = "";
    std::string alloc_traffic_file = "";
    std::map<std::string, simtime_picosec> thermal_delay_map;
    int inter_mode = 0;

    int i = 1;
    while (i < argc)
    {
        if (!strcmp(argv[i], "-nodes"))
        {
            no_of_nodes = atoi(argv[i + 1]);
            cout << "no_of_nodes " << no_of_nodes << endl;
            i++;
        }
        else if (!strcmp(argv[i], "-speed"))
        {
            SPEED = atoi(argv[i + 1]);
            cout << "speed " << SPEED << endl;
            i++;
        }
        else if (!strcmp(argv[i], "-mtu"))
        {
            // already applied above, before TcpPacket::set_packet_size()/-q
            cout << "mtu " << packet_size << endl;
            i++;
        }
        else if (!strcmp(argv[i], "-wafer-rows"))
        {
            wafer_rows = atoi(argv[i + 1]);
            i++;
        }
        else if (!strcmp(argv[i], "-wafer-cols"))
        {
            wafer_cols = atoi(argv[i + 1]);
            i++;
        }
        else if (!strcmp(argv[i], "-intra-speed"))
        {
            // GB/s on the CLI (matches the default's unit); converted to Mbit/s (x8000) for speedFromMbps()
            intra_speed_mbps = (uint64_t)(atof(argv[i + 1]) * 8000.0);
            i++;
        }
        else if (!strcmp(argv[i], "-inter-speed"))
        {
            inter_speed_mbps = (uint64_t)(atof(argv[i + 1]) * 8000.0);
            i++;
        }
        else if (!strcmp(argv[i], "-intra-delay"))
        {
            // nanoseconds on the CLI (matches the recovered sweep's intra_delay_ns naming)
            intra_delay_ps = (simtime_picosec)atof(argv[i + 1]) * 1000ULL;
            i++;
        }
        else if (!strcmp(argv[i], "-inter-delay"))
        {
            inter_delay_ps = (simtime_picosec)atof(argv[i + 1]) * 1000ULL;
            i++;
        }
        else if (!strcmp(argv[i], "-thermal-delay"))
        {
            // nanoseconds on the CLI; one-time stall per all-to-all round (not a link latency)
            thermal_delay_ps = (simtime_picosec)atof(argv[i + 1]) * 1000ULL;
            i++;
        }
        else if (!strcmp(argv[i], "-enable-intra-shortcut"))
        {
            disable_intra_shortcut = false;
        }
        else if (!strcmp(argv[i], "-lambda-alloc"))
        {
            lambda_alloc = argv[i + 1];   // uniform | demand
            i++;
        }
        else if (!strcmp(argv[i], "-alloc-matrix"))
        {
            alloc_matrix_file = argv[i + 1];
            i++;
        }
        else if (!strcmp(argv[i], "-alloc-floor"))
        {
            alloc_floor = atof(argv[i + 1]);
            i++;
        }
        else if (!strcmp(argv[i], "-alloc-inter"))
        {
            alloc_inter = true;
        }
        else if (!strcmp(argv[i], "-alloc-cap"))
        {
            alloc_cap = atof(argv[i + 1]);
            i++;
        }
        else if (!strcmp(argv[i], "-inter-mode"))
        {
            // gateway (legacy: one link per wafer pair) | port (per-reticle CPO port at -inter-speed)
            inter_mode = !strcmp(argv[i + 1], "port") ? 1 : 0;
            i++;
        }
        else if (!strcmp(argv[i], "-thermal-delay-map"))
        {
            // ns, comma-separated: GROUP_BY-forward,AGGREGATE-forward,GROUP_BY-backward,AGGREGATE-backward
            std::stringstream ss(argv[i + 1]); std::string v; int k = 0;
            const char* keys[4] = {"GROUP_BY forward", "AGGREGATE forward", "GROUP_BY backward", "AGGREGATE backward"};
            while (std::getline(ss, v, ',') && k < 4) { thermal_delay_map[keys[k]] = (simtime_picosec)(atof(v.c_str()) * 1000.0); k++; }
            i++;
        }
        else if (!strcmp(argv[i], "-dump-traffic"))
        {
            dump_traffic_file = argv[i + 1];   // N x N bytes CSV written when the iteration finishes
            i++;
        }
        else if (!strcmp(argv[i], "-alloc-traffic"))
        {
            alloc_traffic_file = argv[i + 1];  // use a dumped traffic matrix as the allocation demand
            i++;
        }
        else if (!strcmp(argv[i], "-a2a-symmetric"))
        {
            // size the exporter's zero-byte GROUP_BY (dispatch) rounds like the matching
            // AGGREGATE (combine) rounds; see FFApplication::a2a_symmetric_dispatch
            a2a_symmetric = true;
        }
        else if (!strcmp(argv[i], "-alloc-tp"))
        {
            alloc_tp = atoi(argv[i + 1]);
            i++;
        }
        else if (!strcmp(argv[i], "-rttrack"))
        {
            RTT_rack = atoi(argv[i + 1]);
            cout << "RTT_rack " << RTT_rack << endl;
            i++;
        }
        else if (!strcmp(argv[i], "-rttnet"))
        {
            RTT_net = atoi(argv[i + 1]);
            cout << "rttnet " << RTT_net << endl;
            i++;
        }
        else if (!strcmp(argv[i], "-logdir"))
        {
            logdir = argv[i + 1];
            cout << "logdir " << logdir << endl;
            i++;
        }
        else if (!strcmp(argv[i], "-ofile"))
        {
            ofile = argv[i + 1];
            cout << "ofile " << argv[i + 1] << endl;
            i++;
        }
        else if (!strcmp(argv[i], "-ssthresh"))
        {
            ssthresh = atoi(argv[i + 1]);
            cout << "ssthresh " << ssthresh << endl;
            i++;
        }
        else if (!strcmp(argv[i], "-q"))
        {
            queuesize = memFromPkt(atoi(argv[i + 1]));
            cout << "queuesize " << queuesize << endl;
            i++;
        }
        else if (!strcmp(argv[i], "UNCOUPLED"))
            algo = UNCOUPLED;
        else if (!strcmp(argv[i], "COUPLED_INC"))
            algo = COUPLED_INC;
        else if (!strcmp(argv[i], "FULLY_COUPLED"))
            algo = FULLY_COUPLED;
        else if (!strcmp(argv[i], "COUPLED_TCP"))
            algo = COUPLED_TCP;
        else if (!strcmp(argv[i], "COUPLED_SCALABLE_TCP"))
            algo = COUPLED_SCALABLE_TCP;
        else if (!strcmp(argv[i], "COUPLED_EPSILON"))
        {
            algo = COUPLED_EPSILON;
            if (argc > i + 1)
            {
                epsilon = atof(argv[i + 1]);
                i++;
            }
            printf("Using epsilon %f\n", epsilon);
        }
        else if (!strcmp(argv[i], "-flowfile"))
        {
            flowfile = argv[i + 1];
            i++;
        }
        else if (!strcmp(argv[i], "-weightmatrix"))
        {
            weight_matrix_file = argv[i + 1];
            i++;
        }
        else if (!strcmp(argv[i], "-simtime"))
        {
            simtime = atof(argv[i + 1]);
            i++;
        }
        else if (!strcmp(argv[i], "-utiltime"))
        {
            utiltime = atof(argv[i + 1]);
            i++;
        }
        else
            exit_error(argv[0], argv[i]);
        i++;
    }
    srand(13);

    eventlist.setEndtime(timeFromSec(simtime));
    Clock c(timeFromSec(5 / 100.), eventlist);

    if (logdir == "")
    {
        std::string dateTime = getCurrentDateTime();
        std::string executableName = getExecutableName();
        logdir = "./logs/" + executableName + "_" + dateTime;
        std::filesystem::create_directories(logdir);
        std::cout << "Log directory created: " << logdir << std::endl;
    }
    else if (!std::filesystem::exists(logdir))
    {
        std::filesystem::create_directories(logdir);
        std::cout << "Log directory created: " << logdir << std::endl;
    }
    std::cout << "Log directory is: " << logdir << std::endl;

    string ofile_path;
    if (ofile == "") {
        ofile_path = logdir + "/fct_util_out.txt";
        fct_util_out.open(ofile_path);
    }
    else {
        std::filesystem::path filePath(ofile);
        if (filePath.has_parent_path()) {
            ofile = filePath.filename().string();
        }
        ofile_path = logdir + "/" + ofile;
        fct_util_out.open(ofile_path);
    }
    std::cout << "Output file is: " << ofile_path << std::endl;

    if (!fct_util_out.is_open()) {
        std::cerr << "Failed to open output file: " << (ofile == "" ? "fct_util_out.txt" : ofile) << std::endl;
        return 1;
    }

    std::cout << "Output file is open and ready for writing: " << (ofile == "" ? "fct_util_out.txt" : ofile) << std::endl;

    std::cerr << "Bandwidth per node: " << SPEED << std::endl;
    TcpRtxTimerScanner tcpRtxScanner(timeFromMs(1), eventlist);

    WaferConfig cfg;
    cfg.wafer_rows = wafer_rows;
    cfg.wafer_cols = wafer_cols;
    cfg.total_gpus = no_of_nodes;
    cfg.intra_link_speed = intra_speed_mbps;
    cfg.intra_link_delay = intra_delay_ps;
    cfg.inter_link_speed = inter_speed_mbps;
    cfg.inter_link_delay = inter_delay_ps;
    cfg.inter_mode = inter_mode;
    if (lambda_alloc == "demand" && !alloc_traffic_file.empty()) {
        // measured demand: N x N bytes CSV from a previous run's -dump-traffic (all flow types)
        std::ifstream tf(alloc_traffic_file);
        if (!tf) { std::cerr << "FATAL: cannot open -alloc-traffic file " << alloc_traffic_file << std::endl; return 1; }
        cfg.link_demand.assign(no_of_nodes, std::vector<double>(no_of_nodes, 0.0));
        std::string line; int r = 0; double total = 0.0;
        while (std::getline(tf, line) && r < no_of_nodes) {
            std::stringstream ss(line); std::string cell; int c = 0;
            while (std::getline(ss, cell, ',') && c < no_of_nodes) {
                cfg.link_demand[r][c] = atof(cell.c_str()); total += cfg.link_demand[r][c]; c++;
            }
            r++;
        }
        cfg.alloc_floor = alloc_floor;
        cfg.alloc_cap = alloc_cap;
        cfg.alloc_inter = alloc_inter;
        std::cout << "Wavelength allocation: demand-aware from measured traffic " << alloc_traffic_file
                  << " (" << r << " rows, " << total / 1e9 << " GB total)" << std::endl;
    } else if (lambda_alloc == "demand") {
        std::string mfile = alloc_matrix_file.empty() ? weight_matrix_file : alloc_matrix_file;
        std::vector<std::vector<int>> wm;
        load_weight_matrix(mfile, wm);
        int ep = (int)wm.size();
        int block = alloc_tp * ep;
        cfg.link_demand.assign(no_of_nodes, std::vector<double>(no_of_nodes, 0.0));
        for (int g = 0; g < no_of_nodes; ++g) {
            for (int h = 0; h < no_of_nodes; ++h) {
                if (g == h || g / block != h / block) continue;
                int eg = (g / alloc_tp) % ep, eh = (h / alloc_tp) % ep;
                // dispatch g->h ~ W[eg][eh]; combine g->h ~ W[eh][eg] (mirrors ffapp sizing)
                cfg.link_demand[g][h] = (double)wm[eg][eh] + (double)wm[eh][eg];
            }
        }
        cfg.alloc_floor = alloc_floor;
        cfg.alloc_cap = alloc_cap;
        cfg.alloc_inter = alloc_inter;
        std::cout << "Wavelength allocation: demand-aware from " << mfile << " (ep=" << ep
                  << ", tp=" << alloc_tp << ", EP block=" << block << " GPUs)" << std::endl;
    } else {
        std::cout << "Wavelength allocation: uniform" << std::endl;
    }
    std::cout << "Wafer topology: " << wafer_rows << "x" << wafer_cols << " ("
              << cfg.gpus_per_wafer() << " GPUs/wafer, " << cfg.num_wafers() << " wafers), "
              << "intra=" << intra_speed_mbps << " Mbps/" << (intra_delay_ps / 1000) << " ns, "
              << "inter=" << inter_speed_mbps << " Mbps/" << (inter_delay_ps / 1000) << " ns" << std::endl;

    WaferRowColTopology *top = new WaferRowColTopology(cfg, queuesize, nullptr /*&logfile*/, &eventlist, ff);

    FFApplication app = FFApplication(top, ssthresh, logdir, &fct_util_out, tcpRtxScanner, eventlist);
    app.disable_intra_node_shortcut = disable_intra_shortcut;
    app.thermal_tuning_delay_ps = thermal_delay_ps;
    app.thermal_delay_by_type = thermal_delay_map;
    if (!thermal_delay_map.empty()) {
        std::cout << "Thermal stall per round type (ns):";
        for (auto & kv : thermal_delay_map) std::cout << " [" << kv.first << "]=" << kv.second / 1000;
        std::cout << std::endl;
    }
    app.a2a_symmetric_dispatch = a2a_symmetric;
    app.dump_traffic_file = dump_traffic_file;
    std::cout << "All-to-all dispatch sizing: " << (a2a_symmetric ? "symmetric to combine (-a2a-symmetric)" : "as exported (GROUP_BY xfersize from fbuf)") << std::endl;
    app.load_taskgraph_flatbuf(flowfile, weight_matrix_file);
    app.start_init_tasks();

    int pktsize = Packet::data_packet_size();

    auto start = std::chrono::high_resolution_clock::now();
    int counter = 0;
    while (eventlist.doNextEvent())
    {
        counter++;
    }

    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::seconds>(end - start);
    auto hours = std::chrono::duration_cast<std::chrono::hours>(duration);
    duration -= hours;
    auto minutes = std::chrono::duration_cast<std::chrono::minutes>(duration);
    duration -= minutes;
    auto seconds = std::chrono::duration_cast<std::chrono::seconds>(duration);

    std::cout << "Total simulation duration: ";
    std::cout << std::setw(2) << std::setfill('0') << hours.count() << "h"
              << std::setw(2) << std::setfill('0') << minutes.count() << "m"
              << std::setw(2) << std::setfill('0') << seconds.count() << "s" << std::endl;

    fct_util_out << "FinalFinish " << app.final_finish_time << std::endl;
    fct_util_out.close();
}

string ntoa(double n)
{
    stringstream s;
    s << n;
    return s.str();
}

string itoa(uint64_t n)
{
    stringstream s;
    s << n;
    return s.str();
}
