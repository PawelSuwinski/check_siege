#! /bin/bash
#
# @author Paweł Suwiński, psuw@wp.pl
# @licence MIT
# ---

EXIT_STATUS=('OK' 'WARNING' 'CRITICAL' 'UNKNOWN')

usage() {
  cat <<EOT
Usage: $0 [-h] [-w  WARN_THRE] [-c CRIT_THRE] [-- SIEGE OPTIONS AND ARGUMENTS]

PLUGIN OPTIONS
  -h             help
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
  echo "${EXIT_STATUS[3]}: $1"
  exit 3
}

# Parse input options.
declare -A WARN_THRE CRIT_THRE
validate_threshold() {
  [[ ! $OPTARG =~ ^[A-Za-z]+=[0-9]+(.[0-9]+)?:?(,[A-Za-z]+=[0-9]+(.[0-9]+)?:?)*$ ]] &&
    err "threshold format error!"
}
while getopts "hw:c:-" opt; do
  case $opt in
    h) usage && exit 0;;
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
    warn=${WARN_THRE[$key]}; crit=${CRIT_THRE[$key]}
    if [[ $warn == *.* || $crit == *.* ]]; then
      warnDec=${warn#*.}; critDec=${crit#*.}
      [[ $warn != *.* || $crit != *.* || ${#warnDec} -ne ${#critDec} ]] &&
        err "'$key' - same thresholds precision required!"
      # strip decimal point for comparision
      warn=${warn/./}; crit=${crit/./}
    fi
    [[ $warn == *: || $crit == *: ]] && [[ $warn != *: || $crit != *: ]] &&
        err "'$key' - mixed thresholds range definition error!"
    [[ $warn == *: &&  ${warn/:/} -le ${crit/:/} || $warn != *: && $warn -ge $crit ]] &&
        err "'$key' - thresholds order error!"
  done
fi

# Default exit code.
exitCode=0
# Avaibility default thresholds: critical 0%, warn != 100%.
declare -A DEF_WARN_THRE=([Avail]='100.00:') DEF_CRIT_THRE=([Avail]='1.00:')

# Siege output parser helpers.
val() { local v=${line#*:}; [[ $v != *[0-9] ]] && v=${v% *}; echo -n $v; }
perf() { local v="${line#*:}"; echo -n "'${line%%:*}'="; echo -n ${v// /}; }
warn() {
  for key in ${!WARN_THRE[*]} ${!DEF_WARN_THRE[*]}; do
    [[ ${line%%:*} != *${key}* ]] && continue
    [[ -n ${WARN_THRE[$key]} ]] &&
      echo -n ${WARN_THRE[$key]} || echo -n ${DEF_WARN_THRE[$key]}
  done
}
crit() {
  for key in ${!CRIT_THRE[*]} ${!DEF_CRIT_THRE[*]}; do
    [[ ${line%%:*} != *${key}* ]] && continue
    [[ -n ${CRIT_THRE[$key]} ]] &&
      echo -n ${CRIT_THRE[$key]} || echo -n ${DEF_CRIT_THRE[$key]}
  done
}
out_of_range() { 
# FIXME
  [[ $line == Resp* ]] && return 1
  [[ $line == Throu* ]] && return 0
  return 1
}

# Parse siege output.
while read line; do
  # mark start of statistics and init  perf data
  if [[ $line == Transactions:* ]]; then
    hits=$(val); perfData=$(perf)
    # Successful transactions default thresholds: critical 0, warn < hits
    # Failed transactions default thresholds: critical == hits, warn > 0
    DEF_WARN_THRE+=([Success]="${hits}:" [Fail]='0')
    DEF_CRIT_THRE+=([Success]='1:' [Fail]="$((${hits}-1)):")
    continue
  fi
   
  # omit not statistics output line or empty results
  [[ -z $hits  || $hits -eq 0 ]] && continue

  # normalize, print output end exit on end of statistics
  if [[ -n $hits && $line == '' ]]; then
    # normalize seconds according to SI
    perfData=${perfData//secs/s}; perfData=${perfData//sec/s}
    echo ${EXIT_STATUS[$exitCode]}: $exitMsg '|' $perfData
    exit $exitCode
  fi

  # performance data
  perfData+=" $(perf)"

  # add omitted units 
  [[ $line == Longest* || $line == Shortest* ]] &&
    [[ $line == *[0-9] ]] && perfData+='s'

  # thresholds 
  warn=$(warn) crit=$(crit) 
  perfData+=";$warn;$crit"

  # add min/ max
  [[ $line == Success* || $line == Fail* ]] && perfData+=";0;${hits}"
  
  # set alert status code on value out of range
  if [[ -n $warn || -n $crit ]]; then
    value=$(val)
    [[ $exitCode -lt 2 ]] && out_of_range $value $crit && exitCode=2
    [[ $exitCode -lt 1 ]] && out_of_range $value $warn && exitCode=1
  fi

  # format exit message based on successful stat line
  [[ $line == Success* ]] && exitMsg="${line/:/} of $hits."
done < <(siege $@ 2>&1)

err "Investigate issues by executing \`siege $@\`"
