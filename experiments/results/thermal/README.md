# Panel thermal CSVs — read this before using the numbers

`hcp_W_m2K = 100000`, and that is **not** what `run_panel_hq.sh` declares.

The runner sets `HCP=70000` and cites Coenen et al. for it. The solve that produced
`panhq_glass.rth` / `panhq_si.rth` used **100000**, recovered from the solve database:

    RESUME,panhq_glass,db  →  *STATUS
      HCP        100000.000
      NDPT        32.0000000
      P_GPU      700.000000
      FHOT         0.500000000
      TCP_IN      55.0000000
      TCP_RISE    20.0000000
      MATFLAG      1.00000000

There is no `_out_pan_glass.out`; the solve has no log. The `.db` retaining its
scalar parameters is the only reason the discrepancy is knowable at all.

So every row here carries `bc_source`, and the rule is:

> The runner script is not evidence of what ran. Recover boundary conditions and
> parameters from the solve artifact — `.db` `*STATUS`, a run banner, a `.meta` —
> never from the script that was supposed to have set them.

A re-solve at 70000 (the cited value) is pending; those rows will land as
`panel_*_h70k.csv` and become the primary numbers, with 100000 kept as a point on
the HTC sweep {30, 50, 70, 100}k.

Three panel configurations exist on disk. Only this one has known parameters — the
literal-named `%CSVTILE%.csv` (tile (0,0) = 94.010 °C) is from a third
configuration whose settings are not recoverable.
