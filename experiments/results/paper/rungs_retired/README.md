# Retired rungs

## p32_* -- the 8x4 flattened butterfly at 192 GB/s per optical link

Correctly measured, for a configuration that cannot be built.

192 GB/s was derived by holding the per-GPU optical egress BANDWIDTH fixed at
1536 GB/s (4 x 384 at 4x4, 12 x 128 at 8x8, therefore 8 x 192 at 8x4). That
identity is real but it is not the constraint. The constraint is a per-GPU
WAVEGUIDE COUNT, `2*deg*n + 4m <= 60` with `4m = 12.5`, so `n <= 47.5/(2*deg)`
where `n` is waveguides per optical link at 128 GB/s each:

| panel | optical degree | n allowed | n used | GB/s |
|---|---|---|---|---|
| 4x4 | 4 | <= 5.94 | 3 (the paper's choice) | 384 |
| 8x4 | 8 | <= 2.97 | **2** | **256** |
| 8x8 | 12 | <= 1.98 | 1 | 128 |

**192 GB/s is n = 1.5 waveguides, and there is no such link.** The bandwidth
identity holds at 4x4 and 8x8 only because 3 and 1 happen to be integers; at 8x4
it demands a fraction, and the waveguide budget breaks the tie. The arm was
therefore under-provisioned by 25% and these makespans are pessimistic.

Re-run at 256 GB/s under the same tags. These files are kept because data that was
measured correctly for the wrong configuration is still evidence about the model,
and deleting it would leave no trace that the correction happened.

The MESH arm at 8x4 (`m32_*`) is NOT affected and was not re-run: with
`GLASS_MAXDIST=1` every intra-panel hop is grid-adjacent and electrical. Verified,
not assumed -- `glassfb_hopdump` over the EP=32 flow log returns elec-hops 35984,
opt-hops 0, inter-hops 456 at both 192 and 256, byte-identical.
