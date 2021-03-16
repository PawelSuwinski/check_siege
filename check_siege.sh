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
  echo "UNKNOWN: $1"
  exit 3
}

validate_threshold() { 
  [[ ! $OPTARG =~ ^[A-Za-z]+=[0-9]+(.[0-9]+)?:?(,[A-Za-z]+=[0-9]+(.[0-9]+)?:?)*$ ]] && 
    err "threshold format error!"
}

# input options
declare -A WARN_THRE CRIT_THRE
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

units() { [[ $line == *[0-9] ]] && echo '' || echo ${line##* }; }
val() { local v=${line#*:}; [[ $v == *[0-9] ]] && echo $v || echo ${v% *}; }
label() { echo ${line%%:*}; }

while read line; do
  # mark start of statistics
  [[ $line == Transactions:* ]] && hits=$(val) &&
    perfData="'$(label)'=$(val)$(units)" && continue
  [[ -z $hits  || $hits -eq 0 ]] && continue

  # normalize and print output on end of statistics
  if [[ -n $hits && $line == '' ]]; then
    # normalize seconds according to SI
    perfData=${perfData//secs/s}; perfData=${perfData//sec/s}

    exitStatus='OK'; exitCode='0'
    [[ $success -lt $hits || $avail -lt 100 ]] &&
      exitStatus='WARNING' && exitCode='1'
    [[ $success -eq 0 || $avail -eq 0 ]] &&
      exitStatus='CRITICAL' && exitCode='2'
    echo "$exitStatus: $message $success of $hits. | $perfData"
    exit $exitCode
  fi

  # get value and format percentage
  value=$(val); [[ $line == Availability:* ]] && value=${value%.*}
  perfData+=" '$(label)'=${value}$(units)"

  # critical 0%, warn != 100%
  [[ $line == Availability:* ]] && perfData+=';100:;1:' && avail=$value
  # critical 0, warn < hits
  [[ $line == Successful* ]] && perfData+=";${hits}:;1:;0;${hits}" &&
    success=$value && message=$(label)
  # critical == hits, warn > 0
  [[ $line == Failed* ]] && perfData+=";0;$((${hits}-1)):;0;${hits}"

  # add units
  [[ $line == Longest* || $line == Shortest* ]] && perfData+='s'
done < <(siege $@ 2>&1)

err "Investigate issues by executing \`siege $@\`"
