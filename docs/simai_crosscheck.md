# SimAI cross-check: what was established, and where it stopped

Time-boxed attempt, 2026-09-07 17:25–20:56. Stopped at the box, not at a conclusion.
Two results below are usable without the curve; the curve itself did not land.

## 1. SimAI's NVSwitch is a single aggregate link, so it is our *striped* control

This is the result that matters most, and it holds whether or not the ladder ever runs.

`gen_Topo_Template.py -topo Spectrum-X -g 8 -gps 8 -gt H100 -nvbw 3600Gbps` writes:

```
0 8 3600Gbps 0.000025ms 0
1 8 3600Gbps 0.000025ms 0
...                             one line per GPU, all to node 8, the NV switch
```

Each GPU has **one** link of 3600 Gbps (450 GB/s) to one switch node. The generator's
only knobs are `-nvbw` (aggregate, default 2880Gbps) and `-nsps` (switches per server,
default 1). A flow crosses GPU → switch → GPU over one link each way. There is no
per-link structure to hash a flow onto because there is only one link.

So SimAI corresponds to our **s1 striped control**, not to the **s18 pinned /
per-flow-ECMP** model. Its curve can corroborate the ceiling; it is **silent** on lane
pinning, because the effect that separates our two curves is one its model does not
represent. Labelling it "hardware-validated" *between* our curves would invite a
reader to take it as adjudicating between them, which it cannot do.

That is also the sharpest statement of why the s18 number is the interesting one: the
incumbent's own published simulator does not model the failure mode we quantify.

## 2. `ALLTOALL` comm_size is the per-GPU buffer, and 7/8 of it crosses the wire

Settled by measurement, not by reading the source. Asking for `comm_size = 469762048`
produced `All data sent from node 0 is 411041792`, and 411041792 / 469762048 = 7/8
exactly. So each GPU's buffer is split into 8 chunks, one per peer including itself,
and 7 leave.

**For M bytes per ordered pair, set `comm_size = 8M.**  (Checked: 8 × 64 MiB = 536870912,
of which 7/8 = 469762048 = 7 × 64 MiB.)

## 3. Two environment defects, both fixed, neither in SimAI's model

- **Segfault before any simulation, on the shipped example too.** `SimAI.conf` points
  its four `*_MON_FILE` paths at `/etc/astra-sim/simulation/`, which is root-owned;
  `SetupNetwork` (`common.h:1011`) fopens one, does not check, and hands the null
  `FILE*` to `SimSetting::Serialize`. Fixed by copying the conf with those four paths
  redirected — **no model parameter changed**. The `MockNcclLog` warning about
  `/etc/astra-sim/SimAI.log` is a separate, harmless message and was a red herring;
  the gdb backtrace is what identified the real site.
- **`ep: 8` in the workload header raises SIGFPE.** `model_parallel_NPU_group: 8 ep: 1
  pp: 1 vpp: 8 ga: 1 all_gpus: 8` — the shipped header shape — runs. `ep: 8` with
  `vpp: 1` divides by zero somewhere in the parallelism setup. The all-to-all over the
  model-parallel group of 8 is what we want anyway.

Also: the ns-3 build is a **batch job**, not a login-node job. On a compute node with
8 cores it takes 6 min 13 s and peaks at 5.5 GB. Run on the login node it took the
load average to 111, made the node unusable for everyone on it, and was OOM-killed
without finishing.

## 4. Where it stopped

`ncclFlowModel_EndToEnd.csv` and `ncclFlowModel_detailed_9.csv` are written **empty**,
so no collective completion time was extracted and there is no `simai_calib.csv`. The
run itself completes (`rc=0`, all 8 nodes report their bytes sent and received), so the
simulation is happening; only the timing output is missing. Finding where SimAI reports
collective time is the next step and was not attempted within the box.

**Nothing in this file is a number for the paper.** The calibration stands on
`calib_nvswitch.csv` as before.
