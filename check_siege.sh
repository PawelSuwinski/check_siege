#! /bin/bash
#
# @author Paweł Suwiński, psuw@wp.pl
# @licence MIT
# ---

EXIT_STATUS=('OK' 'WARNING' 'CRITICAL' 'UNKNOWN')

usage() {
  cat <<EOT
Usage: $0 [-h] [-v] [-w WARN_THRE] [-c CRIT_THRE] [-- SIEGE OPTIONS AND ARGUMENTS]

PLUGIN OPTIONS
  -h             help
  -v             print alerts list on error
  -w  WARN_THRE  warning thresholds
  -c  CRIT_THRE  critical thresholds

THRESHOLDS
   Thresholds are given with tha name of  measured quantities  which are
   searched using wildcards so make sure that uniq phrase was given.

   Supported are only 'less than' and 'greather than' range definitions.

   In an example below for 'Response time' (*Res*) warning alert is set if
   value is greathen than 0.20 and critical if  value is greather than 0.50
   and for 'Transaction rate'(*rate*) warning if value is less than 30 and
   critical if value less than 20.

SIEGE OPTIONS AND ARGUMENTS
  See siege man page: siege(1).

EXAMPLE:
  ./check_siege.sh -w 'Res=0.20,rate=30:' -c 'Res=0.50,rate=20:' -- -r 10 -c 25 -f urls.txt
  ./check_siege.sh -w Res=0.20 -w rate=30: -c Res=0.50 -c rate=20: -- -r 10 -c 25 -f urls.txt

SEE ALSO:
  https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT
EOT
}

err() {
  echo ${EXIT_STATUS[3]}: $@
  exit 3
}

# split float to further significant numbers for comparison
split() {
  local IFS='.' num dec n prec
  read num dec <<< "$1"
  prec=${#dec}
  # convert to int to avoid leading zeros issues
  echo -n $((10#$num+0)) 
  for ((n=0; n < prec; n++)); do
    echo -n '' ${dec:$n:1}
  done
}
# cmp a b : 0 - a == b, 1 - a < b, 2 - a > b
cmp() { 
  local a=($(split $1)) b=($(split $2)) n len
  [[ ${#a[*]} -gt ${#b[*]} ]] && len=${#a[*]} || len=${#b[*]}
  for ((n=0; n < len; n++)); do
    if [[ ${a[$n]:-0} -ne ${b[$n]:-0} ]]; then
      [[ ${a[$n]:-0} -lt ${b[$n]:-0} ]] && return 1 || return 2
    fi
  done
}
# out_of_range value threshold
out_of_range() { 
  cmp $1 ${2/:/}
  [[ $2 == *: && $? -eq 1  || $2 != *: && $? -eq 2 ]]
}

# Parse input options.
declare -A WARN_THRE CRIT_THRE
validate_threshold() {
  [[ ! $OPTARG =~ ^[A-Za-z]+=[0-9]+(.[0-9]+)?:?(,[A-Za-z]+=[0-9]+(.[0-9]+)?:?)*$ ]] &&
    err 'threshold format error!'
}
while getopts 'hvw:c:-' opt; do
  case $opt in
    h) usage && exit 0;;
    v) VERBOSE='true';;
    w)
      validate_threshold
      for t in ${OPTARG//,/ }; do
        WARN_THRE[${t%=*}]=${t#*=}
      done;;
    c)
      validate_threshold
      for t in ${OPTARG//,/ }; do
        CRIT_THRE[${t%=*}]=${t#*=}
      done;;
  esac
done
shift $((OPTIND-1))

# Thresholds validation.
if [[ ${#WARN_THRE[*]} -gt 0 ]]; then
  for key in ${!WARN_THRE[*]}; do
    [[ -z ${CRIT_THRE[$key]} ]] && continue
    warn=${WARN_THRE[$key]} crit=${CRIT_THRE[$key]}
    [[ $warn == *: || $crit == *: ]] && [[ $warn != *: || $crit != *: ]] &&
      err "'$key' - mixed thresholds range definition error!"
    cmp ${warn/:/} ${crit/:}
    [[ $warn == *: && $? -ne 2 || $warn != *: && $? -ne 1 ]] &&
      err "'$key' - thresholds order error!"
  done
fi

# Default exit code.
exitCode=0
# Availability default thresholds: critical 0%, warn != 100%.
declare -A DEF_WARN_THRE=([Avail]='100:') DEF_CRIT_THRE=([Avail]='1:')

# Siege output parser helpers.
val() { 
  local v=${line#*:}
  [[ $v != *[0-9] ]] && v=${v% *}
  echo -n ${v:-0}
}
perf() { 
  local v="${line#*:}"
  echo -n "'${line%%:*}'="
  echo -n ${v// /}
}
thre() {
  local keys=($1) thresholds=($2) n
  for ((n=0; $n < ${#keys[*]}; n++)); do 
    [[ ${line%%:*} == *${keys[$n]}* ]] && echo -n ${thresholds[$n]} && break
  done
}
alerts() {
  echo -n " $1: $2"
  shift 2
  [[ -n $@ ]] && printf ', %s' "$@"
  echo -n '.'
}

# Parse siege output.
while read line; do
  # mark start of statistics and init  perf data
  if [[ $line == Transactions:* ]]; then
    hits=$(val); perfData=$(perf)
    # Successful transactions default thresholds: critical 0, warn < hits
    # Failed transactions default thresholds: critical == hits, warn > 0
    DEF_WARN_THRE+=([Success]="${hits}:" [Fail]='0')
    DEF_CRIT_THRE+=([Success]='1:' [Fail]="$((${hits}-1))")
    continue
  fi
   
  # omit not statistics output line or empty results
  [[ -z $hits  || $hits -eq 0 ]] && continue

  # normalize, print output end exit on end of statistics
  if [[ -n $hits && $line == '' ]]; then
    # normalize seconds according to SI
    perfData=${perfData//secs/s}; perfData=${perfData//sec/s}
    echo -n "${EXIT_STATUS[$exitCode]}: $hits transactions with "
    [[ $exitCode -eq 0 ]] && echo -n 'no' ||
      echo -n "${#critAlerts[*]} critical and ${#warnAlerts[*]} warning"
    echo -n ' alerts.'
    # list alerts on verbose
    if [[ -n $VERBOSE ]]; then
      [[ ${#critAlerts[*]} -gt 0 ]] && alerts 'Critical' "${critAlerts[@]}"
      [[ ${#warnAlerts[*]} -gt 0 ]] && alerts 'Warning' "${warnAlerts[@]}"
    fi
    echo ' |' $perfData
    exit $exitCode
  fi

  # performance data
  perfData+=" $(perf)"

  # add omitted units 
  [[ $line == Longest* || $line == Shortest* ]] &&
    [[ $line == *[0-9] ]] && perfData+='s'

  # add and process thresholds if not empty
  warn=$(thre "${!WARN_THRE[*]}" "${WARN_THRE[*]}")
  crit=$(thre "${!CRIT_THRE[*]}" "${CRIT_THRE[*]}")
  if [[ -z $warn && -z $crit ]]; then
    warn=$(thre "${!DEF_WARN_THRE[*]}" "${DEF_WARN_THRE[*]}")
    crit=$(thre "${!DEF_CRIT_THRE[*]}" "${DEF_CRIT_THRE[*]}")
  fi
  [[ -z $warn && -z $crit ]] && continue

  perfData+=";$warn;$crit"

  # add min/ max for successful and failed transactions
  [[ $line == Success* || $line == Fail* ]] && perfData+=";0;${hits}"
  
  # set alerts and exit code on value out of range
  value=$(val)
  if [[ -n $crit ]] && out_of_range $value $crit; then
    critAlerts+=("${line%:*}")
    [[ $exitCode -lt 2 ]] && exitCode=2
  elif [[ -n $warn ]] && out_of_range $value $warn; then
    warnAlerts+=("${line%:*}")
    [[ $exitCode -lt 1 ]] && exitCode=1
  fi
done < <(siege $@ 2>&1)

err "Investigate issues by executing \`siege $@\`"
