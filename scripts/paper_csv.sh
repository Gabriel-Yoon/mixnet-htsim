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

csv_open() {  # csv_open <file> <header>
    _CSV_FILE=$1
    _CSV_DONE=0
    printf '%s\n' "$2" > "$_CSV_FILE"
    _csv_emit_row submitted \
        "job=${SLURM_JOB_ID:-none} host=$(hostname -s) start=$(date +%FT%T)" >> "$_CSV_FILE"
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
}

_csv_exit() {
    local rc=${1:-0}
    [ -z "$_CSV_FILE" ] && return 0
    [ "$_CSV_DONE" = 1 ] && return 0
    _csv_drop_sentinel
    _csv_emit_row ABORTED \
        "job=${SLURM_JOB_ID:-none} exit=$rc died=$(date +%FT%T) -- script did not reach csv_close" \
        >> "$_CSV_FILE"
    return 0
}
