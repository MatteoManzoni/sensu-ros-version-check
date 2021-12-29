#!/bin/bash

ROUTEROS_REPO="https://download.mikrotik.com/routeros"

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -p|--port)
    SNMP_PORT="$2"
    shift
    shift
    ;;
    -H|--host)
    SNMP_HOST="$2"
    shift
    shift
    ;;
    -c|--community)
    SNMP_COMMUNITY="$2"
    shift
    shift
    ;;
    --target-ros-branch)
    ROS_BRANCH="$2"
    shift
    ;;
    *)
    POSITIONAL+=("$1")
    shift
    ;;
esac
done
set -- "${POSITIONAL[@]}"

case $ROS_BRANCH in
    development)
    ROS_BRANCH_NUMBER="7.development"
    ;;
    testing)
    ROS_BRANCH_NUMBER="7.testing"
    ;;
    stable)
    ROS_BRANCH_NUMBER="7.stable"
    ;;
    LTS)
    ROS_BRANCH_NUMBER="6.stable"
    ;;
    *)
    ROS_BRANCH_NUMBER="6"
    ;;
esac

if ! current_ros_version=$(snmpget -O qv -v 2c -c "$SNMP_COMMUNITY" "$SNMP_HOST":"$SNMP_PORT" .1.3.6.1.4.1.14988.1.1.4.4.0 2> /dev/null); then
    echo "Could not SNMP connect to: $SNMP_HOST"
    exit 3
else
    current_ros_version=$(echo "$current_ros_version" | tr -d '"')
fi

if ! latest_ros_version_string=$(curl -fsA "check_routeros-upgrade" "$ROUTEROS_REPO/NEWEST.$ROS_BRANCH_NUMBER"); then
    echo "Could not connect to Mikrotik repo to check latest ROS version"
    exit 3
fi

latest_ros_version=$(echo "$latest_ros_version_string" | cut -d " " -f 1)
latest_ros_releasedate=$(echo "$latest_ros_version_string" | cut -d " " -f 2)

if [ "$current_ros_version" == "$latest_ros_version" ]; then
    echo -e "HOST: $SNMP_HOST is upto date \n$current_ros_version is up to date (release: $(date -u -d @"$latest_ros_releasedate" +'%b-%d'))"
    exit 0
else
    if ! changelog=$(curl -fsA "check_routeros-upgrade" "$ROUTEROS_REPO/$latest_ros_version/CHANGELOG"); then
        echo "Could not connect to Mikrotik repo to check latest ROS version changelog"
        exit 3
    fi

    if [ -n "$changelog" ]; then
      changelog_lines=$(echo "$changelog" | grep -n "What" | head -n 2 | tail -n 1 | cut -d ":" -f 1)

      changelog_impfix=$(echo "$changelog" | head -n "$changelog_lines" | grep -c '!)')
      changelog_avgfix=$(echo "$changelog" | head -n "$changelog_lines" | grep -c '[*])')


      if [ "$changelog_impfix" -ne 0 ] && [ "$changelog_avgfix" -ne 0 ]; then
          fix_text="$changelog_impfix important fixes, $changelog_avgfix average fixes"
          fix_result=2
      elif [ "$changelog_impfix" -ne 0 ]; then
          fix_text="$changelog_impfix important fixes"
          fix_result=2
      elif [ "$changelog_avgfix" -ne 0 ]; then
          fix_text="$changelog_avgfix average fixes"
          fix_result=1
      else
          fix_result=1
      fi
    else 
      fix_result=1
      fix_text="NO CHANGELOG IS PRESENT"
    fi

    echo "RouterOS is upgradable to $latest_ros_version ($fix_text)"
    exit $fix_result
fi
