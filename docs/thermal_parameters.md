# Thermal model parameters behind the paper's thermal figure

Every value below is read from the ANSYS decks and wrapper scripts that produced the quoted
rows, not from prose: `thermal/legacy_pace/panel/thermal_panel_map_body.inp` (steady 4x4 panel,
PIC-plane heatmap), `thermal_tile_transient.inp` (single-tile idle->TDP step) and
`thermal_tile_schedule.inp` (single-tile periodic load), driven by `run_panel_cal.sh`
(`cal_h200k_tin40`, `cal_h200k_tin40_si`), `run_tile_transient.sh` and
`run_tile_schedule.sh` / `run_tile_period_sweep.sh`. Result CSVs:
`experiments/results/thermal/panel_cal_tiles.csv`, `panel_plane_{glass,si}_cal_h200k_tin40.csv`,
`tile_transient.csv`, `tile_schedule.csv`.

## Geometry (identical in all three decks)

| Item | Value | Deck symbol |
|---|---|---|
| Panel | 4 x 4 tiles | `NX=4` |
| Tile footprint | 28.3 mm x 28.3 mm | `TILE_W` |
| Tile gap / pitch | 2.0 mm / 30.3 mm | `GAP`, `PT` |
| Panel footprint | 121.2 mm x 121.2 mm | `PANEL=NX*PT` |
| Layer 1: board / carrier | 0.50 mm | `T_BRD` |
| Layer 2: substrate (glass, or Si control) | 0.70 mm | `T_SUB` |
| Layer 3: PIC (embedded, full tile area) | 0.05 mm | `T_PIC` |
| Layer 4: RDL | 0.10 mm | `T_RDL` |
| Layer 5: GPU die | 0.75 mm | `T_DIE` |
| Die hotspot | central (W/3)^2 = 1/9 of the die area | `AHOT` |
| Single-tile decks | one 28.3 mm tile, same five layers | |

## Materials

| Layer (MAT) | k (W/mK) x, y, z | rho (kg/m^3) | c_p (J/kgK) | Note |
|---|---|---|---|---|
| 1 board / carrier | 1.0 | 1900 | 1200 | organic carrier |
| 2 substrate, glass (`MATFLAG=1`) | 1.2 | 2500 | 800 | the design |
| 2 substrate, silicon (`MATFLAG=0`) | 150 | 2500 | 800 | control; same rho, c_p as glass by deck |
| 3 PIC | 80 | 2330 | 700 | silicon photonic die |
| 4 RDL | 200 / 200 / 60 (anisotropic) | 8900 | 385 | copper-dominated in plane, dielectric through plane |
| 5 GPU die | 150 | 2330 | 700 | silicon |

All properties are constants (no `MPTEMP` tables), so the solve is linear in the sink
temperature; rho and c_p enter only the transient decks.

## Heat sources

| Source | Value | Deck |
|---|---|---|
| GPU die power | 700 W per die | `P_GPU`, `P_HI` |
| Hotspot fraction | 0.50 of die power in the central ninth, 0.50 uniform over the rest | `FHOT` |
| PIC power, interior tile | 14.1 W link + 1.44 W ring tuning = 15.54 W | `PIC_INT`, `PIC_TUNE` |
| PIC power, edge tile | 35.9 + 1.44 = 37.34 W | `PIC_EDGE` |
| PIC power, corner tile | 57.7 + 1.44 = 59.14 W | `PIC_CORNER` |
| PIC pJ/bit behind those | 1.15 pJ/bit, 1 waveguide = 1.178 W both directions; 12 / 30.5 / 49 waveguides | deck header |
| PIC power in the tile decks | 43 W, constant through the transient (link budget, not compute phase) | `P_PIC` |
| PIC heat distribution | uniform volumetric over the whole PIC layer | `BFE,HGEN` |

## Boundary conditions

| Surface | Condition | Deck |
|---|---|---|
| Die back (top, z = Z5) | convection h = 200,000 W/m^2K to the coolant | `HCP=200000` |
| Coolant temperature, panel | 40 C at the inlet edge rising linearly to 60 C at the outlet edge (`TCP_IN=40`, `TCP_RISE=20`), a tabular BC along x | `TCPTAB` |
| Coolant temperature, tile decks | 60 C uniform (the outlet tile); the period sweep repeats two points at 40 C as a linearity control (identical swing) | `TCP` |
| Board underside (z = 0) | natural convection h = 50 W/m^2K to 40 C | `SFA,...,CONV,50,40` |
| Side faces | adiabatic | (default) |
| Contact resistances | none in the deck; 0.02-0.10 cm^2K/W at the three interfaces was bounded separately at +0.4-1.8 K on the PIC | paper Sec. III-D |

h = 200k is the coefficient at which this die model meets its 85-90 C junction
specification at 700 W with the 0.5 hotspot; 100k and 150k were solved as the sweep
(`cal_h100k_tin40`, `cal_h150k_tin40`).

## Mesh and solver

| Item | Panel steady | Tile step | Tile periodic |
|---|---|---|---|
| Element | SOLID70 | SOLID70 | SOLID70 |
| In-plane element size | pitch / 32 = 0.95 mm (`NDPT=32`) | tile / 16 = 1.77 mm (`NDPT=16`) | tile / 16 |
| Through-plane | one element per layer (light-mesh convention) | same | same |
| Analysis | steady state | transient: steady baseline at GPU idle (PIC on), then step to 700 W | transient: steady baseline at the LOW phase, then `NPER` periods of 50% duty |
| Time stepping | -- | `DELTIM 1e-5 s` (1e-7 min, 1e-3 max), stepped loads (`KBC,1`) | `DELTIM PERIOD/1000` (min 1e-7, max PERIOD/200), `AUTOTS,ON`, `KBC,1` |
| Duration | -- | `TEND=0.3 s` (`glass_stack_h200k_long`; = 6.8 x the 44 ms 10-90 rise) | `NPER=6`; the last period is reported |
| Monitor | PIC-plane cut at z = Z2 + T_PIC/2, per-tile max/min | PIC layer centre node | PIC layer centre node |
| Reported | per-tile PIC max, die max, PIC-die offset | delta_T (asymptote), 10-90 rise | peak-to-trough over the last period, drift vs the previous period |

## Periodic-load schedule (Fig. thermal (b))

| Parameter | Values |
|---|---|
| Duty | 50% (high for PERIOD/2, low for PERIOD/2) |
| P_hi | 700 W |
| P_lo | 210 W (assumed 30%-of-TDP communication floor), 0 W (bound), 350 W |
| Periods | 1, 3, 10, 10.84, 30, 86.75, 100, 300, 1000, 3000 ms (10.84 = one microbatch, 86.75 = one EP=16 iteration, from the paper's own rows) |
| Step asymptote used as the long-period bound | 28.77 K, 10-90 rise 44 ms (`glass_stack_h200k_long`) |

## What the decks reproduce

* With all PIC sources set to zero the map body reproduces the archived die-only solve
  (119.300 C PIC max, glass) exactly -- the gate before any PIC-powered row is trusted.
* The 40 C controls of the period sweep reproduce the 60 C rows' peak-to-peak swing to
  three decimals, which is the linearity the constant-property deck implies.
