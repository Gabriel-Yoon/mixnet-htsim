CC=g++
CXX=g++
CFLAGS=-Wall -std=c++17 -O3
FF_HOME?=$(PWD)/../../../../FlexFlow
#GUROBI_DIR?=$(HOME)/gurobi912/linux64
#GUROBI_DIR=/usr/wkspace/3dparty/gurobi_server912/linux64
GUROBI_DIR=/usr/wkspace/3dparty/gurobi1000/linux64/linux64
#USE_GUROBI = 1
CRT=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
# Protobuf (revived TaskGraphProtoBuf path; see ../taskgraph.proto). Override
# PROTOBUF_PREFIX/ABSEIL_PREFIX per-machine if not Homebrew-on-macOS.
PROTOBUF_PREFIX?=$(shell brew --prefix protobuf 2>/dev/null)
ABSEIL_PREFIX?=$(shell brew --prefix abseil 2>/dev/null)
PBFLAGS?=$(shell PKG_CONFIG_PATH="$(PROTOBUF_PREFIX)/lib/pkgconfig:$(ABSEIL_PREFIX)/lib/pkgconfig" pkg-config --cflags protobuf 2>/dev/null)
PBLIBS?=$(shell PKG_CONFIG_PATH="$(PROTOBUF_PREFIX)/lib/pkgconfig:$(ABSEIL_PREFIX)/lib/pkgconfig" pkg-config --libs protobuf 2>/dev/null)
INCLUDE= -I$(CRT)/.. -I$(CRT) -I$(FF_HOME)/fbuf/include $(PBFLAGS) #-I/usr/local/Cellar/flatbuffers/2.0.0/include/
#-I$(CRT)/ksp -I$(CRT)/ksp/boost
LIB=-L.. $(PBLIBS)
# ifeq ($(USE_GUROBI), 1)
# 	INCLUDE+= -I$(GUROBI_DIR)/include/ 
# 	LIB+= -L$(GUROBI_DIR)/lib -lgurobi_c++ -lgurobi91 # -L$(FF_HOME)/protobuf/src/.libs -lprotobuf
# 	CFLAGS+= -DHAVE_GUROBI
# endif
ifeq ($(USE_GUROBI), 1)
	INC+= -I$(GUROBI_DIR)/include/ #-I/usr/local/Cellar/flatbuffers/2.0.0/include/
	CFLAGS+= -L$(GUROBI_DIR)/lib  -DHAVE_GUROBI #-O3  #-L$(FF_HOME)/protobuf/src/.libs -lprotobuf 
endif
#-Lksp
OBJS=../eventlist.o ../tcppacket.o ../pipe.o ../queue.o ../queue_lossless.o ../queue_lossless_input.o ../queue_lossless_output.o ../ecnqueue.o ../tcp.o ../dctcp.o ../mtcp.o ../loggers.o ../logfile.o ../clock.o ../config.o ../network.o ../qcn.o ../exoqueue.o ../randomqueue.o ../cbr.o ../cbrpacket.o ../sent_packets.o ../ndp.o ../ndppacket.o ../eth_pause_packet.o ../compositequeue.o ../prioqueue.o ../cpqueue.o ../compositeprioqueue.o ../switch.o ../fairpullqueue.o ../route.o ../ffapp.o ../dyn_net_sch.o ../mixnet_topomanager.o#../taskgraph.pb.o

all: htsim_tcp_nvswitch htsim_tcp_glassfb htsim_tcp_wafer htsim_tcp_fc htsim_tcp_fattree htsim_tcp_os_fattree htsim_tcp_flat htsim_tcp_aggosft htsim_tcp_dyn_flat htsim_tcp_fattree_multijob htsim_tcp_aggos_fattree_multijob htsim_tcp_mixnet

htsim_tcp_fattree_multijob: main_tcp_multijob_fattree.o firstfit.o fat_tree_topology.o
	$(CC) $(CFLAGS) $(INCLUDE) firstfit.o main_tcp_multijob_fattree.o fat_tree_topology.o glassfb_topology.o $(OBJS) $(LIB) -lhtsim -o htsim_tcp_fattree_multijob

htsim_tcp_aggos_fattree_multijob: main_tcp_multijob_aggos_fattree.o firstfit.o agg_os_fattree.o
	$(CC) $(CFLAGS) $(INCLUDE) firstfit.o main_tcp_multijob_aggos_fattree.o agg_os_fattree.o glassfb_topology.o $(OBJS) $(LIB) -lhtsim -o htsim_tcp_aggos_fattree_multijob

htsim_tcp_dyn_flat: main_tcp_dyn_flat.o firstfit.o flat_topology.o
	$(CC) $(CFLAGS) $(INCLUDE) firstfit.o main_tcp_dyn_flat.o flat_topology.o glassfb_topology.o $(OBJS) $(LIB) -lhtsim -o htsim_tcp_dyn_flat


htsim_tcp_mixnet: main_tcp_mixnet.o firstfit.o fat_tree_topology.o mixnet.o
	$(CC) $(CFLAGS) $(INCLUDE) firstfit.o main_tcp_mixnet.o fat_tree_topology.o mixnet.o glassfb_topology.o $(OBJS) $(LIB) -lhtsim -o htsim_tcp_mixnet

htsim_tcp_fc: main_tcp_fc.o firstfit.o  fc_topology.o
	$(CC) $(CFLAGS) $(INCLUDE) firstfit.o main_tcp_fc.o fc_topology.o glassfb_topology.o $(OBJS) $(LIB) -lhtsim -o htsim_tcp_fc

htsim_tcp_fattree: main_tcp_fattree.o firstfit.o fat_tree_topology.o
	$(CC) $(CFLAGS) $(INCLUDE) firstfit.o main_tcp_fattree.o fat_tree_topology.o glassfb_topology.o $(OBJS) $(LIB) -lhtsim -o htsim_tcp_fattree

htsim_tcp_os_fattree: main_tcp_os_fattree.o firstfit.o os_fattree.o
	$(CC) $(CFLAGS) $(INCLUDE) firstfit.o main_tcp_os_fattree.o os_fattree.o glassfb_topology.o $(OBJS) $(LIB) -lhtsim -o htsim_tcp_os_fattree

htsim_tcp_nvswitch: main_tcp_nvswitch.o firstfit.o nvswitch_topology.o
	$(CC) $(CFLAGS) $(INCLUDE) firstfit.o main_tcp_nvswitch.o nvswitch_topology.o glassfb_topology.o $(OBJS) $(LIB) -lhtsim -o htsim_tcp_nvswitch

# Carries GLASS_LOG_HOPS (in-domain vs NIC hop classification from the topology)
# and GLASS_LOG_FLOWS. Separate output name so htsim_tcp_nvswitch stays untouched
# while jobs are running it.
htsim_tcp_nvswitch_hop: main_tcp_nvswitch.o firstfit.o nvswitch_topology.o
	$(CC) $(CFLAGS) $(INCLUDE) firstfit.o main_tcp_nvswitch.o nvswitch_topology.o glassfb_topology.o $(OBJS) $(LIB) -lhtsim -o htsim_tcp_nvswitch_hop

htsim_tcp_flat: main_tcp_flat.o firstfit.o flat_topology.o
	$(CC) $(CFLAGS) $(INCLUDE) firstfit.o main_tcp_flat.o flat_topology.o glassfb_topology.o $(OBJS) $(LIB) -lhtsim -o htsim_tcp_flat

# Same as htsim_tcp_flat plus the ECN drop counter reported at exit. Separate
# output name so the running island jobs keep using the untouched binary.
htsim_tcp_flat_drop: main_tcp_flat.o firstfit.o flat_topology.o
	$(CC) $(CFLAGS) $(INCLUDE) firstfit.o main_tcp_flat.o flat_topology.o glassfb_topology.o $(OBJS) $(LIB) -lhtsim -o htsim_tcp_flat_drop

htsim_tcp_aggosft: main_tcp_aggosft.o firstfit.o agg_os_fattree.o
	$(CC) $(CFLAGS) $(INCLUDE) firstfit.o main_tcp_aggosft.o agg_os_fattree.o glassfb_topology.o $(OBJS) $(LIB) -lhtsim -o htsim_tcp_aggosft



main_tcp_dyn_flat.o: main_tcp_dyn_flat.cpp
	$(CC) $(INCLUDE) $(CFLAGS) -c  main_tcp_dyn_flat.cpp

main_tcp_mixnet.o: main_tcp_mixnet.cpp
	@echo "Compiling main_tcp_mixnet.cpp"
	$(CC) $(INCLUDE) $(CFLAGS) -c  main_tcp_mixnet.cpp
	
main_tcp_fc.o: main_tcp_fc.cpp 
	$(CC) $(INCLUDE) $(CFLAGS) -c  main_tcp_fc.cpp

main_tcp_fattree.o: main_tcp_fattree.cpp 
	$(CC) $(INCLUDE) $(CFLAGS) -c  main_tcp_fattree.cpp

main_tcp_multijob_fattree.o: main_tcp_multijob_fattree.cpp 
	$(CC) $(INCLUDE) $(CFLAGS) -c  main_tcp_multijob_fattree.cpp

main_tcp_multijob_aggos_fattree.o: main_tcp_multijob_aggos_fattree.cpp 
	$(CC) $(INCLUDE) $(CFLAGS) -c  main_tcp_multijob_aggos_fattree.cpp

main_tcp_os_fattree.o: main_tcp_os_fattree.cpp 
	$(CC) $(INCLUDE) $(CFLAGS) -c  main_tcp_os_fattree.cpp

main_tcp_aggosft.o: main_tcp_aggosft.cpp 
	$(CC) $(INCLUDE) $(CFLAGS) -c  main_tcp_aggosft.cpp

main_tcp_nvswitch.o: main_tcp_nvswitch.cpp ../nvswitch_topology.h
	$(CC) $(INCLUDE) $(CFLAGS) -c  main_tcp_nvswitch.cpp

nvswitch_topology.o: nvswitch_topology.cpp ../nvswitch_topology.h topology.h
	$(CC) $(INCLUDE) $(CFLAGS) -c nvswitch_topology.cpp

main_tcp_flat.o: main_tcp_flat.cpp 
	$(CC) $(INCLUDE) $(CFLAGS) -c  main_tcp_flat.cpp

firstfit.o: firstfit.cpp
	$(CC) $(INCLUDE) $(CFLAGS) -c firstfit.cpp

test_topology.o: test_topology.cpp test_topology.h topology.h
	$(CC) $(INCLUDE) $(CFLAGS) -c test_topology.cpp

fc_topology.o: fc_topology.cpp fc_topology.h topology.h
	$(CC) $(INCLUDE) $(CFLAGS) -c fc_topology.cpp

fat_tree_topology.o: fat_tree_topology.cpp fat_tree_topology.h topology.h
	$(CC) $(INCLUDE) $(CFLAGS) -c fat_tree_topology.cpp

os_fattree.o: os_fattree.cpp os_fattree.h topology.h
	$(CC) $(INCLUDE) $(CFLAGS) -c os_fattree.cpp

flat_topology.o: flat_topology.cpp ../flat_topology.h topology.h
	$(CC) $(INCLUDE) $(CFLAGS) -c flat_topology.cpp

agg_os_fattree.o: agg_os_fattree.cpp agg_os_fattree.h topology.h
	$(CC) $(INCLUDE) $(CFLAGS) -c agg_os_fattree.cpp


mixnet.o: mixnet.cpp mixnet.h topology.h fat_tree_topology.cpp fat_tree_topology.h topology.h
	@echo "mixnet"
	$(CC) $(INCLUDE) $(CFLAGS) -c mixnet.cpp

clean:	
	rm -f *.o htsim_ndp* htsim_tcp* htsim_dctcp*

htsim_tcp_glassfb_pm: main_tcp_glassfb.o firstfit.o glassfb_topology.o
	$(CC) $(CFLAGS) $(INCLUDE) firstfit.o main_tcp_glassfb.o glassfb_topology.o $(OBJS) $(LIB) -lhtsim -o htsim_tcp_glassfb_pm

# Identical to htsim_tcp_glassfb_pm; separate output name so it can be built
# while jobs are still spawning the _pm path. Carries the GLASS_LOG_FLOWS
# instrumentation in tcp.cpp (TcpSrc::set_flowsize), which is the only
# choke point every collective passes through -- ffapp.cpp prints flow_size
# at ONE site, inside the all-to-all, so an ffapp-derived flow log silently
# omits every DP and PP flow.
htsim_tcp_glassfb_pmlog: main_tcp_glassfb.o firstfit.o glassfb_topology.o
	$(CC) $(CFLAGS) $(INCLUDE) firstfit.o main_tcp_glassfb.o glassfb_topology.o $(OBJS) $(LIB) -lhtsim -o htsim_tcp_glassfb_pmlog

# Carries GLASS_LOG_HOPS (per-tier hop classification from the topology itself)
# alongside GLASS_LOG_FLOWS. Separate output name so it can be built while the
# _pm and _pmlog binaries are in use by running jobs.
htsim_tcp_glassfb_pmhop: main_tcp_glassfb.o firstfit.o glassfb_topology.o
	$(CC) $(CFLAGS) $(INCLUDE) firstfit.o main_tcp_glassfb.o glassfb_topology.o $(OBJS) $(LIB) -lhtsim -o htsim_tcp_glassfb_pmhop

htsim_tcp_glassfb: main_tcp_glassfb.o firstfit.o glassfb_topology.o
	$(CC) $(CFLAGS) $(INCLUDE) firstfit.o main_tcp_glassfb.o glassfb_topology.o $(OBJS) $(LIB) -lhtsim -o htsim_tcp_glassfb

main_tcp_glassfb.o: main_tcp_glassfb.cpp
	$(CC) $(INCLUDE) $(CFLAGS) -c main_tcp_glassfb.cpp

glassfb_topology.o: glassfb_topology.cpp glassfb_topology.h topology.h
	$(CC) $(INCLUDE) $(CFLAGS) -c glassfb_topology.cpp

htsim_tcp_wafer: main_tcp_wafer.o firstfit.o wafer_rowcol_topology.o
	$(CC) $(CFLAGS) $(INCLUDE) firstfit.o main_tcp_wafer.o wafer_rowcol_topology.o glassfb_topology.o $(OBJS) $(LIB) -lhtsim -o htsim_tcp_wafer

main_tcp_wafer.o: main_tcp_wafer.cpp
	$(CC) $(INCLUDE) $(CFLAGS) -c main_tcp_wafer.cpp

wafer_rowcol_topology.o: wafer_rowcol_topology.cpp wafer_rowcol_topology.h topology.h
	$(CC) $(INCLUDE) $(CFLAGS) -c wafer_rowcol_topology.cpp
