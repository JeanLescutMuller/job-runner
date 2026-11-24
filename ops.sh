#!/bin/sh
# job-runner's operations on an env's folder (DESIGN.md §12): the only things a check does on the NAS, in its clone of
# job-runner-sync, or here. Run from that folder: sh ops.sh OPERATION ARG…, every argument a plain name (on the NAS, gate.sh
# makes sure of it for the job-runner keys).
#   put-status JOB MACHINE                   status/JOB/MACHINE.tsv ← stdin, whole
#   put-log JOB MACHINE FILE                 logs/JOB/MACHINE/FILE ← stdin, whole
#   put-conf JOB                             conf/JOB.conf ← stdin, whole: the job's dashboard settings (DESIGN §11); a working
#                                            link (the job's project installed on the NAS too) is kept
#   get-statuses JOB                         stdout: a tar of status/JOB/
#   list-logs JOB MACHINE                    stdout: the file names in logs/JOB/MACHINE/
#   claim WHERE JOB MACHINE NOW UNTIL PID    claims/JOB/owner = "MACHINE UNTIL PID", if free; else prints why, exits 1
#   release WHERE JOB MACHINE PID            removes claims/JOB if it is this check's
# WHERE: here (this machine's own disk: a claim of its own is held while its pid lives), NAS, or GITHUB (the claim is the
# file claims/JOB, held until it expires).
put() { mkdir -p "${1%/*}" && cat > "$1.tmp" && mv "$1.tmp" "$1"; }
op=$1; shift
case $op in
  put-status) put "status/$1/$2.tsv" ;;
  put-log) put "logs/$1/$2/$3" ;;
  put-conf) if [ -L "conf/$1.conf" ] && [ -e "conf/$1.conf" ]; then cat > /dev/null; echo "kept: linked on the NAS"; else put "conf/$1.conf"; fi ;;
  get-statuses) mkdir -p "status/$1" && tar cf - "status/$1" ;;
  list-logs) ls "logs/$1/$2" 2> /dev/null; exit 0 ;;
  claim | release)
    where=$1; shift; o=claims/$1/owner; [ "$where" = GITHUB ] && o=claims/$1
    if [ $op = release ]; then read -r who until pid 2> /dev/null < "$o"; [ "$who $pid" = "$2 $3" ] && rm -rf "claims/$1"; exit; fi
    mkdir -p claims
    if [ "$where" = GITHUB ] || ! mkdir "claims/$1" 2> /dev/null; then
      who=; read -r who until pid 2> /dev/null < "$o"
      if [ -z "$who" ]; then [ "$where" = GITHUB ] || { echo "held (being taken)"; exit 1; }
      elif [ "$who" = "$2" ]; then [ "$where" = here ] && [ "$pid" != "$5" ] && kill -0 "${pid:-0}" 2> /dev/null && { echo "running $pid"; exit 1; }
      elif [ "${until:-0}" -gt "$3" ]; then echo "held $who $until"; exit 1; fi
    fi
    echo "$2 $4 $5" > "$o" ;;
  *) echo "ops.sh: unknown operation $op" >&2; exit 2 ;;
esac
