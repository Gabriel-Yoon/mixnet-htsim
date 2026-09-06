// -*- c-basic-offset: 4; tab-width: 8; indent-tabs-mode: t -*-
#include "config.h"
#include <sstream>
#include <strstream>
#include <fstream> // need to read flows
#include <iostream>
#include <string.h>
#include <math.h>
#include <chrono>
#include <iomanip>
#include <filesystem>
#include <unistd.h>
#include "network.h"
#include "randomqueue.h"
//#include "shortflows.h"
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
//#include "connection_matrix.h"

// Choose the topology here:
// #include "test_topology.h"
#include "nvswitch_topology.h"
#include "ffapp.h"

#include <list>

// Simulation params

#define PRINT_PATHS 0

#define PERIODIC 0
#include "main.h"

uint32_t RTT = 1000; // ns
int DEFAULT_NODES = 16;

uint32_t SPEED;

// Per-node egress port cap, defined in flat_topology.cpp. Default OFF: without it
// this topology is an ideal non-blocking bound with (N-1) x link-rate injection
// per node, which is what every existing flat result row used. Pass -port-cap to
// model a switch-based crossbar, where one port is what makes injection finite.
// Packet-level NVLink domain parameters. The analytic island is forced OFF here:
// the domain is simulated, so leaving ffapp's shortcut on would model a scale-up
// domain inside a scale-up domain.
int NVS_DOMAIN = 64;        // GPUs per domain
int NVS_SWITCHES = 18;      // switch chips per domain
double NVS_LINK_GBPS = 50;  // per (GPU, chip) link, GB/s per direction
uint32_t NVS_LAT_NS = 250;  // per hop
int NVS_Q_PKTS = 136;       // NVLink port queue
int NVS_ECN_K = 68;
int NIC_FEEDER_PKTS = 540;  // scale-out egress feeder
std::ofstream fct_util_out;

FirstFit *ff = NULL;
//unsigned int subflow_count = 8; // probably not necessary ???

#define DEFAULT_PACKET_SIZE 9000 // full packet (including header), Bytes
#define DEFAULT_HEADER_SIZE 64   // header size, Bytes
#define DEFAULT_QUEUE_SIZE 100

string ntoa(double n);
string itoa(uint64_t n);

EventList eventlist;
// Logfile* lg;

void exit_error(char *progr, char *param)
{
    cerr << "Bad parameter: " << param << endl;
    cerr << "Usage " << progr << " [UNCOUPLED(DEFAULT)|COUPLED_INC|FULLY_COUPLED|COUPLED_EPSILON] [epsilon][COUPLED_SCALABLE_TCP]" << endl;
    exit(1);
}

void print_path(std::ofstream &paths, const Route *rt)
{
    for (unsigned int i = 1; i < rt->size() - 1; i += 2)
    {
        RandomQueue *q = (RandomQueue *)rt->at(i);
        if (q != NULL)
            paths << q->str() << " ";
        else
            paths << "NULL ";
    }

    paths << endl;
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
        // 处理读取错误的情况
        std::cerr << "Error reading the executable path." << std::endl;
        return "";
    }
}

int main(int argc, char **argv)
{

    // Packet size (bytes, incl. header): overridable via -mtu so cross-topology runs can
    // be pinned to the same *byte* buffer via -q instead of silently differing (this
    // binary defaults to 9000B jumbo frames while fattree/glassfb default to 1500B --
    // the same -q value then means a ~6x different queuesize in bytes between them).
    int packet_size = DEFAULT_PACKET_SIZE;
    for (int pre_i = 1; pre_i < argc - 1; pre_i++)
        if (!strcmp(argv[pre_i], "-mtu")) { packet_size = atoi(argv[pre_i + 1]); break; }
    TcpPacket::set_packet_size(packet_size - DEFAULT_HEADER_SIZE); // MTU
    mem_b queuesize = DEFAULT_QUEUE_SIZE * packet_size;

    int algo = UNCOUPLED;
    double epsilon = 1;
    int ssthresh = 15;
    string allreduce_strategy;

    int no_of_nodes = DEFAULT_NODES;

    // Default flowfile path
    string flowfile = "../../../test/taskgraph.fbuf";       // so we can read the flows from a specified file
    string weight_matrix_file = "../../../test/num_global_tokens_per_expert.txt";
    // Default log dir = ./logs/
    string logdir = "";
    string ofile = "";

    double simtime;        // seconds
    double utiltime = .01; // seconds

    // stringstream filename(ios_base::out);
    int i = 1;
    // filename << "logout.dat";

    while (i < argc)
    {
        //   if (!strcmp(argv[i],"-o")){
        //       filename.str(std::string());
        //       filename << argv[i+1];
        //       i++;
        //   } else
        if (!strcmp(argv[i], "-nodes"))
        {
            no_of_nodes = atoi(argv[i + 1]);
            cout << "no_of_nodes " << no_of_nodes << endl;
            i++;
        }
        else if (!strcmp(argv[i], "-island_gpus") || !strcmp(argv[i], "-island_bw"))
        {
            // Accepted and ignored: the analytic island cannot be enabled in this
            // binary because the domain is simulated packet-level. Rejecting would
            // break shared runner scripts; silently honouring it would double-model.
            std::cerr << "note: " << argv[i] << " ignored (analytic island is off by construction)"
                      << std::endl;
            i++;
        }
        else if (!strcmp(argv[i], "-nvs_domain"))   { NVS_DOMAIN = atoi(argv[i + 1]); i++; }
        else if (!strcmp(argv[i], "-nvs_switches")) { NVS_SWITCHES = atoi(argv[i + 1]); i++; }
        else if (!strcmp(argv[i], "-nvs_link"))     { NVS_LINK_GBPS = atof(argv[i + 1]); i++; }
        else if (!strcmp(argv[i], "-nvs_lat"))      { NVS_LAT_NS = atoi(argv[i + 1]); i++; }
        else if (!strcmp(argv[i], "-nvs_q"))        { NVS_Q_PKTS = atoi(argv[i + 1]); i++; }
        else if (!strcmp(argv[i], "-nvs_ecn_k"))    { NVS_ECN_K = atoi(argv[i + 1]); i++; }
        else if (!strcmp(argv[i], "-port-cap-pkts")){ NIC_FEEDER_PKTS = atoi(argv[i + 1]); i++; }
        else if (!strcmp(argv[i], "-port-cap"))     { /* always on here */ }
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
        else if (!strcmp(argv[i], "-rtt"))
        {
            RTT = atoi(argv[i + 1]);
            cout << "RTT " << RTT << endl;
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
        else if (!strcmp(argv[i], "-weightmatrix"))
        {
            weight_matrix_file = argv[i + 1];
            i++;
        }
        else if (!strcmp(argv[i], "-q"))
        {
            queuesize = memFromPkt(atoi(argv[i + 1]));
            cout << "queuesize " << queuesize << endl;
            i++;
        }
        else if (!strcmp(argv[i], "-ar"))
        {
            allreduce_strategy = string(argv[i + 1]);
            cout << "allreduce_strategy " << allreduce_strategy << endl;
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

    // if log_dir not set, use default format
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
        // check if ofile is a path and obtain its basename
        std::filesystem::path filePath(ofile);
        if (filePath.has_parent_path()) {
            // 取最后一个basename作为文件名
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

    FFApplication::FFAllReduceStrategy ar_strategy = FFApplication::FF_DEFAULT_AR;
    if (allreduce_strategy == "ring") {
        ar_strategy = FFApplication::FF_RING_AR;
    }
    else if (allreduce_strategy == "ps") {
        ar_strategy = FFApplication::FF_PS_AR;
    }
    else if (allreduce_strategy == "dps") {
        ar_strategy = FFApplication::FF_DPS_AR;
    }
    else if (allreduce_strategy != "") {
        cerr << "Unrecogonized ar strategy " << allreduce_strategy << std::endl;
        assert(false);
    }

    //cout <<  "Using algo="<<algo<< " epsilon=" << epsilon << endl;

    // Logfile logfile(filename.str(), eventlist);

#if PRINT_PATHS
    filename << ".paths";
    cout << "Logging path choices to " << filename.str() << endl;
    std::ofstream paths(filename.str().c_str());
    if (!paths)
    {
        cout << "Can't open for writing paths file!" << endl;
        exit(1);
    }
#endif

    // lg = &logfile;

    // !!!!!!!!!!!!!!!!!!!!!!!
    // logfile.setStartTime(timeFromSec(10));

    // TcpSinkLoggerSampling sinkLogger = TcpSinkLoggerSampling(timeFromUs(50.), eventlist);
    // logfile.addLogger(sinkLogger);
    // TcpTrafficLogger traffic_logger = TcpTrafficLogger();
    // traffic_logger.fct_util_out = &fct_util_out;
    // logfile.addLogger(traffic_logger);

    TcpRtxTimerScanner tcpRtxScanner(timeFromMs(1), eventlist);

    //FlatTopology *top = new FlatTopology(no_of_nodes, flowfile, queuesize, nullptr /* &logfile */, &eventlist, ff, ECN);
    NVSwitchTopology *top = new NVSwitchTopology(
        no_of_nodes, nullptr /* &logfile */, &eventlist, ff, ECN,
        NVS_DOMAIN, NVS_SWITCHES, NVS_LINK_GBPS, NVS_LAT_NS,
        memFromPkt(NVS_Q_PKTS), NVS_ECN_K,
        SPEED, RTT, queuesize, NIC_FEEDER_PKTS);
    // FFApplication app = FFApplication(top, ssthresh, sinkLogger, traffic_logger, tcpRtxScanner, eventlist);
    FFApplication app = FFApplication(top, ssthresh, logdir, &fct_util_out, tcpRtxScanner, eventlist, ar_strategy);
    // The NVLink domain is simulated packet-level, so ffapp's analytic same-node
    // shortcut must not also fire -- that would model a scale-up domain inside a
    // scale-up domain and hand the incumbent its contention-free path back.
    app.disable_intra_node_shortcut = true;
    std::cerr << "Intra-node NVLink shortcut: DISABLED (domain is simulated by NVSwitchTopology)"
              << std::endl;
    if (flowfile.size() >= 3 && flowfile.compare(flowfile.size() - 3, 3, ".pb") == 0) {
        app.load_taskgraph_protobuf(flowfile, weight_matrix_file);
    } else {
        app.load_taskgraph_flatbuf(flowfile, weight_matrix_file);
    }
    app.start_init_tasks();

    // UtilMonitor* UM = new UtilMonitor(top, eventlist);
    // UM->start(timeFromSec(utiltime));

    // Record the setup
    int pktsize = Packet::data_packet_size();
    // logfile.write("# pktsize=" + ntoa(pktsize) + " bytes");
    //logfile.write("# subflows=" + ntoa(subflow_count));
    // logfile.write("# hostnicrate = " + ntoa(SPEED) + " pkt/sec");
    // logfile.write("# corelinkrate = " + ntoa(SPEED*CORE_TO_HOST) + " pkt/sec");
    //logfile.write("# buffer = " + ntoa((double) (queues_na_ni[0][1]->_maxsize) / ((double) pktsize)) + " pkt");
    //double rtt = timeAsSec(timeFromUs(RTT));
    //logfile.write("# rtt =" + ntoa(rtt));

    auto start = std::chrono::high_resolution_clock::now();
    // GO!
    while (eventlist.doNextEvent())
    {
    }

    auto end = std::chrono::high_resolution_clock::now();
    // Calculate the duration
    auto duration = std::chrono::duration_cast<std::chrono::seconds>(end - start);

    // Convert the duration to hours, minutes, and seconds
    auto hours = std::chrono::duration_cast<std::chrono::hours>(duration);
    duration -= hours;
    auto minutes = std::chrono::duration_cast<std::chrono::minutes>(duration);
    duration -= minutes;
    auto seconds = std::chrono::duration_cast<std::chrono::seconds>(duration);

    // Output the duration in hour:minute:second format
    std::cout << "Total simulation duration: ";
    std::cout << std::setw(2) << std::setfill('0') << hours.count() << "h"
              << std::setw(2) << std::setfill('0') << minutes.count() << "m"
              << std::setw(2) << std::setfill('0') << seconds.count() << "s" << std::endl;

    fct_util_out << "FinalFinish " << app.final_finish_time << std::endl;
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
