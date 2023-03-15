#!/bin/bash
# sarav (hello@grity.com)
# convert key=value to json
# Created at Gritfy ( Devops Junction )
#
file_name=$1
last_line=$(wc -l < $file_name)
current_line=0
pattern="[a-zA-Z_]+=[(*\n)|.\n]"

echo "{"
while read line
do
  current_line=$(($current_line + 1))
  [ -z "$line" ] && continue
  if [[ $current_line -ne $last_line ]]; then
    echo $line|awk -F'='  '{ print " \""$1"\" : \""$2"\","}'|grep -iv '\"#'
  else
    echo $line|awk -F'='  '{ print " \""$1"\" : \""$2"\""}'|grep -iv '\"#'
  fi
done < $file_name
echo "}"
