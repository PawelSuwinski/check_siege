#! /bin/bash
#
# @author Paweł Suwiński, psuw@wp.pl
# @see https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT
# @licence MIT
# ---

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

echo "UNKNOWN: Investigate issues by executing \`siege $@\`"
exit 3
