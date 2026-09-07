"""Refuse to rewrite a paper CSV that a job is appending to.

Every rewriter here -- gate_quotable, fct_recompute, mark_fct_status, the table
builders -- is a read-modify-write. Run while a job appends, the sequence is:
reader loads the rows, job appends one, reader writes back without it. The row is
gone and nothing errors. That is what emptied cliff_ep64_gt_ext.csv of both its
measured EP=64 points.

TWO GUARDS, because the first one alone has a coverage hole that has already been
hit twice.

1. The .writing marker (paper_csv.sh). Explicit and cheap, but it only protects a
   job that OPENED the file through a csv_open carrying the marker code. Jobs
   started before that code landed have no marker -- 12898877 called csv_open at
   00:32:11 against a paper_csv.sh that gained _csv_mark at 01:47:10, and its CSV
   was rewritten underneath it -- and portmap_cliff.sh never calls csv_open at
   all. Both needed a marker placed by hand, which is the kind of protection that
   works until someone forgets.

2. The size+mtime compare-and-swap here. Stamp the file before reading, check the
   stamp again immediately before writing, and skip if it moved. This needs no
   cooperation from the runner, so it covers the jobs the marker misses.

The CAS narrows the window rather than closing it: an append landing between the
final check and the truncate is still lost. It goes from the whole processing time
-- seconds to minutes across a directory of CSVs -- to the microseconds between
two syscalls. Closing it completely needs the writers to take a real lock, which
is a change to every runner rather than to the four rewriters.
"""
import os


def being_written(path):
    """True if a running job declared it is appending to this CSV."""
    return os.path.exists(path + ".writing")


def stamp(path):
    """Cheap identity of the file's current contents: (size, mtime_ns)."""
    try:
        st = os.stat(path)
        return (st.st_size, st.st_mtime_ns)
    except OSError:
        return None


def changed(path, before):
    """True if the file moved since `before` was taken -- do not write it."""
    return stamp(path) != before


def skip_reason(path, before=None):
    """Why this CSV must not be rewritten right now, or None if it is safe.

    Pass the stamp taken before reading to get the compare-and-swap check too.
    """
    if being_written(path):
        return "a job is writing it"
    if before is not None and changed(path, before):
        return "it changed while being read -- a job is appending"
    return None
