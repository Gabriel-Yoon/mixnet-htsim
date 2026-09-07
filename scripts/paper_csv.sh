# paper_csv.sh -- make a paper CSV say whether its job ever ran.
#
# WHY. experiments/results/paper/cliff_pkt.csv sat header-only for days. The job
# that should have filled it aborted two seconds in, every time it was submitted
# (an unbound ${tag} in a `local` line, under set -u). A header-only CSV is
# indistinguishable from one whose job simply has not been run yet: nothing in
# the file recorded that a run had been attempted at all, so it read as "still to
# do" rather than "failing every time". The rows were on the must-have list and
# their absence was invisible.
#
# csv_open writes the header plus ONE sentinel row with status=submitted carrying
# the job id and start time. If the script reaches csv_close, that row is
# removed. If it dies first, an EXIT trap rewrites it as status=ABORTED with the
# exit code -- so a dead job leaves a corpse, while a file that is genuinely
# waiting on a queue still says "submitted" and names the job.
#
# Usage:
#   source "$(dirname "$0")/paper_csv.sh"
#   csv_open "$CSV" "paper_ref,model,...,status,note"
#   ... append rows as usual ...
#   csv_close
#
# The sentinel is placed by column NAME (status, note), read from the header, so
# it works for every one of these CSVs despite their differing column orders.
# Notes must not contain commas.

_CSV_FILE=""
_CSV_DONE=0

_csv_emit_row() {  # status note -> one line matching the header's columns
    awk -v st="$1" -v note="$2" -F, 'NR == 1 {
        has = 0
        for (i = 1; i <= NF; i++) if ($i == "status") has = 1
        for (i = 1; i <= NF; i++) {
            v = ""
            if ($i == "status") v = st
            # nvs_gates.csv and friends have no status column; keep the marker
            # visible by folding it into the note rather than dropping it.
            else if ($i == "note") v = (has ? note : "status=" st " " note)
            printf "%s%s", v, (i < NF ? "," : "\n")
        }
        exit
    }' "$_CSV_FILE"
}

_csv_drop_sentinel() {
    awk -F, 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == "status") c = i; print; next }
             c == 0 || $c != "submitted"' "$_CSV_FILE" > "$_CSV_FILE.tmp" \
        && mv "$_CSV_FILE.tmp" "$_CSV_FILE"
}

# Announce what a fresh sweep is about to erase. `echo "$HDR" > "$CSV"` discards
# any column another tool added (fct_recompute.py's flows_*/._all/status_fct,
# schema_model.py's model_name) along with every earlier row. Those columns are
# regenerable, so truncating is correct -- but silent loss is not. Warns; never
# blocks.
csv_warn_truncate() {
    local file=$1 hdr=$2
    [ -f "$file" ] || return 0
    local old; old=$(head -1 "$file")
    [ "$old" = "$hdr" ] && return 0
    local rows; rows=$(( $(wc -l < "$file") - 1 ))
    echo "csv: $file is being rewritten with a different header" >&2
    echo "csv:   discarding $rows existing row(s)" >&2
    local c
    local IFS=,
    for c in $old; do
        case ",$hdr," in *",$c,"*) ;; *) echo "csv:   column dropped: $c" >&2 ;; esac
    done
    echo "csv:   re-run scripts/fct_recompute.py and scripts/schema_model.py afterwards" >&2
    return 0
}

# A ".writing" sibling marks a CSV a running job is appending to. The rewriters
# (gate_quotable, fct_recompute, the table builders) skip marked files: they
# read-modify-write, and doing that under an appending job silently drops rows.
_csv_mark()   { [ -n "${1:-}" ] && : > "$1.writing" 2>/dev/null || true; }
_csv_unmark() { [ -n "${1:-}" ] && rm -f "$1.writing" 2>/dev/null || true; }

csv_open() {  # csv_open <file> <header>
    _CSV_FILE=$1
    _CSV_DONE=0
    # Provenance every row carries: did the binary that produced it have the
    # link-rate fix, and which commit was it built from. gate_quotable refuses an
    # affected fabric's row without the first, so a run whose environment does not
    # assert it produces unquotable rows rather than silently trusted ones.
    _CSV_FIXED=${LINK_RATE_FIXED:-}
    _CSV_SHA=${HTSIM_BINARY_SHA:-}
    case ",$2," in
        *,link_rate_fixed,*) ;;
        *) set -- "$1" "$2,link_rate_fixed,binary_sha" ;;
    esac
    csv_warn_truncate "$1" "$2"
    printf '%s\n' "$2" > "$_CSV_FILE"
    _csv_emit_row submitted \
        "job=${SLURM_JOB_ID:-none} host=$(hostname -s) start=$(date +%FT%T)" >> "$_CSV_FILE"
    _csv_mark "$_CSV_FILE"
    trap '_csv_exit $?' EXIT
}

# Append one row to a CSV by COLUMN NAME, in the order the file's own header
# gives. Safe when columns are added later; a positional append is not.
#
#   csv_row "$CSV" makespan_ms=91.367 status=final note="some text"
#
# Unknown keys abort the run rather than shifting every later field by one.
# Values must not contain commas.
csv_row() {
    local file=$1; shift
    local hdr; hdr=$(head -1 "$file")
    local -A kv=()
    local pair k v
    for pair in "$@"; do
        k=${pair%%=*}; v=${pair#*=}
        kv[$k]=$v
    done
    # A value containing a comma shifts every column after it, and nothing
    # downstream can tell a shifted row from a short one. This is the port-cap
    # banner defect (awk $1 kept "ENABLED," from the sentence it was cut from) and
    # it recurred here from a note written by hand. Replace and say so: a silent
    # quote would hide that the caller wrote something the format cannot carry.
    for k in "${!kv[@]}"; do
        case "${kv[$k]}" in
            *,*) echo "csv_row: value for '$k' contains a comma; replaced with ';' to keep the row aligned" >&2
                 kv[$k]=${kv[$k]//,/;} ;;
        esac
    done
    # every supplied key must exist in the header
    local col missing=""
    for k in "${!kv[@]}"; do
        case ",$hdr," in
            *",$k,"*) ;;
            *) missing="$missing $k" ;;
        esac
    done
    if [ -n "$missing" ]; then
        echo "csv_row: $file has no column(s):$missing" >&2
        echo "csv_row: header is: $hdr" >&2
        return 1
    fi
    # fill the provenance columns unless the caller set them explicitly
    case ",$hdr," in
        *,link_rate_fixed,*) [ -z "${kv[link_rate_fixed]+x}" ] && kv[link_rate_fixed]=${_CSV_FIXED:-} ;;
    esac
    case ",$hdr," in
        *,binary_sha,*) [ -z "${kv[binary_sha]+x}" ] && kv[binary_sha]=${_CSV_SHA:-} ;;
    esac
    local out="" first=1
    local IFS=,
    for col in $hdr; do
        if [ "$first" = 1 ]; then first=0; else out="$out,"; fi
        out="$out${kv[$col]-}"
    done
    printf '%s\n' "$out" >> "$file"
}

csv_close() {
    _CSV_DONE=1
    [ -n "$_CSV_FILE" ] && _csv_drop_sentinel
    _csv_unmark "$_CSV_FILE"
}

_csv_exit() {
    local rc=${1:-0}
    [ -z "$_CSV_FILE" ] && return 0
    [ "$_CSV_DONE" = 1 ] && return 0
    _csv_drop_sentinel
    _csv_unmark "$_CSV_FILE"
    _csv_emit_row ABORTED \
        "job=${SLURM_JOB_ID:-none} exit=$rc died=$(date +%FT%T) -- script did not reach csv_close" \
        >> "$_CSV_FILE"
    return 0
}
