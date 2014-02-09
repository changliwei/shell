#!/bin/bash

#############################################################################
# This script is for monitoring disk usage and for alerting when the disk
# usage exceed certain percentage usage values. It will run continuously.
#
# For each file system to be monitored, you can specify up to 5 threshold
# values. The way the script works is that when the first threshold is hit,
# an alert is sent. A second alert is only sent if the second threshold is
# hit.
#
# Please note that the max alerts allowed is reset if the script if ever
# stopped and restarted.
#############################################################################

#
# This how often the disk usage will be examined. This value is in minutes
#
DISK_USAGE_CHECK_INTERVAL_MINS=5

#
# This is a comma separate list of email addresses that will be notified
# when we have a situation requiring a notification
#
NOTIFICATION_TARGETS=lstorm2003@yahoo.com,jsfinis@yahoo.com

#
# These are the filesystems to be monitored and their threshold values. each
# record contains a colon separated fields as follows:
#
# <file_system_name>:<t1>:<t2>:<t3>:<t4>:<t5>:<max_alerts>
#
# You must specify all 5 threshold values as percentages. If you want
# to use less than 5 different percentages, you can use the same value multiple
# times.
#
# <max_alerts> is used to specify the maximum number of alerts that would be
# sent out for a filesystem threshold issue. If this is -1, then there will
# be no maximum. Even though there are just 5 threshold values, if the
# 5th threshold is hit, then we would alert everytime as long as we haven't
# exceeded the <max_alerts> setting
#
# Here are some examples and how they would work:
#
# /home:90:92:94:96:98:5
# This will generate the first alert once we hit 90%. Subsequent
# alerts will only be sent when we hit 92%, 94%, 96%, and 98%
# respectively. We will only send 5 alerts even if we continue
# to remain above 98%
#
# /home:90:92:94:94:94:-1
# This will generate the first alert once we hit 90%. The
# next alert will only be sent when we hit 92%. From that point
# forward, once we go above 94% we will continue to send alerts
# indefinitely
#
cat << EOF > vrdiskmon.fs
/home:90:92:94:96:98:5
/home/dtdb23in:90:92:94:96:98:5
/opt/sapdb:90:92:94:96:98:5
/var/vvt:90:92:94:96:98:5
/var:90:92:94:96:98:5
/home/dtdb23in:90:92:94:96:98:5
/db2translog:90:92:94:96:98:5
/opt/sapdb:90:92:94:96:98:5
/var/vvt:90:92:94:96:98:5
/opt/vsuite:90:92:94:96:98:5
EOF

#############################################################################
# All customizations should occur above here. Nothing below here was #
# designed to be configrable #
#############################################################################

HOSTNAME=`hostname`

FILESYSTEM_USAGE_INFO_FILE=""
FS=""
T1=""
T2=""
T3=""
T4=""
T5=""
MAX_ALERTS=""

NUM_ALERTS_SENT=""
LAST_THRESHOLD_USED=""
LAST_USAGE=""

THESHOLD_VALUE_TO_CHECK_AGAINST=""
THRESHOLD_NUMBER_BEING_USED=""



#
# Get the current usage percentage for the given filesystem. This function
# takes a single parameter, the filesystem name. The method
# returns the percentage usage. The invoker of the function would get
# this by checking "$?"
#
getCurrentUsage()
{
    _USAGE=`df -k | grep $1 | grep -v "$1/" | # Find the filesystem
    tr -s ' ' | # Collapse whitespace
    cut -d' ' -f4 | # Get the 4th field
    sed 's/%//g'` # Strip the '%' symbol

    return $_USAGE
}


#
# Get the last usage info from the specified file. This function takes a
# single parameter, the filename. It then fills in the following
# variables: NUM_ALERTS_SENT, LAST_THRESHOLD_USED, and LAST_USAGE. If there
# is no file which is the case if we never hit a threshold value, then these
# variables get filled in with zeros
#
getLastUsageInfo()
{
    NUM_ALERTS_SENT="0"
    LAST_THRESHOLD_USED="0"
    LAST_USAGE="0"

    if (test -f "$1") then
		NUM_ALERTS_SENT=`grep NUM_ALERTS_SENT $1 |
		cut -d'=' -f2`
		LAST_THRESHOLD_USED=`grep LAST_THRESHOLD_USED $1 |
		cut -d'=' -f2`
		LAST_USAGE=`grep LAST_USAGE $1 |
		cut -d'=' -f2`
	else
	return
	fi
}

saveLastUsageInfo()
{
	rm -f $1
	echo "NUM_ALERTS_SENT=$NUM_ALERTS_SENT" >> $1
	echo "LAST_THRESHOLD_USED=$LAST_THRESHOLD_USED" >> $1
	echo "LAST_USAGE=$LAST_USAGE" >> $1
}


#
# Get the name of the file we'll use to hold info about a filesystem. The
# name of the file is based on the filename name and stored in /tmp. The
# filename is returned in the variable FILESYSTEM_USAGE_INFO_FILE
#
getUsageInfoFilename()
{
	_SAFE_FS_NAME=`echo $1 | sed 's/\//_/g'`
	FILESYSTEM_USAGE_INFO_FILE="/tmp/vrdiskmon.$_SAFE_FS_NAME.info"
}


#
# Get he next threshold value to be used for checking the disk usage.
# This takes a single parameter, the last threshold number that was used. It
# sets the variables THESHOLD_VALUE_TO_CHECK_AGAINST and
# THRESHOLD_NUMBER_BEING_USED
#
getNextThresholdToUse()
{
	THESHOLD_VALUE_TO_CHECK_AGAINST=""
	THRESHOLD_NUMBER_BEING_USED=""

	case $LAST_THRESHOLD_USED in
	0)
	THESHOLD_VALUE_TO_CHECK_AGAINST=$T1
	THRESHOLD_NUMBER_BEING_USED=1
	;;
	1)
	THESHOLD_VALUE_TO_CHECK_AGAINST=$T2
	THRESHOLD_NUMBER_BEING_USED=2
	;;
	2)
	THESHOLD_VALUE_TO_CHECK_AGAINST=$T3
	THRESHOLD_NUMBER_BEING_USED=3
	;;
	3)
	THESHOLD_VALUE_TO_CHECK_AGAINST=$T4
	THRESHOLD_NUMBER_BEING_USED=4
	;;
	*)
	THESHOLD_VALUE_TO_CHECK_AGAINST=$T5
	THRESHOLD_NUMBER_BEING_USED=5
	;;
	esac
}

#
# Take a record of the filesystem to be checked and the threshold values
# and parse it. The results are placed in the variables: FS, T1, T2, T3, T4,
# T5, and MAX_ALERTS.
#
parseFilesystemRecord()
{
	FS=`echo $1 | cut -d: -f1`
	T1=`echo $1 | cut -d: -f2`
	T2=`echo $1 | cut -d: -f3`
	T3=`echo $1 | cut -d: -f4`
	T4=`echo $1 | cut -d: -f5`
	T5=`echo $1 | cut -d: -f6`
	MAX_ALERTS=`echo $1 | cut -d: -f7`

	if (test $MAX_ALERTS -lt 0) then
	MAX_ALERTS=999999
	fi
}


#
# Send an alert. This function expects the following arguments:
# - The filesystem
# - The current usage
# - The last usage
#
sendAlert()
{
	ALERT_MSG=/tmp/vrdiskmon.alert

	if (test $3 -eq 0) then
	STATUS_MSG="$HOSTNAME: $1 at $2%."
	else
	STATUS_MSG="$HOSTNAME: $1 at $2%. Previous: $3%"
	fi

	echo "To: $NOTIFICATION_TARGETS" >> $ALERT_MSG
	echo "Subject: $STATUS_MSG" >> $ALERT_MSG
	echo "" >> $ALERT_MSG
	date >> $ALERT_MSG
	echo "$STATUS_MSG" >> $ALERT_MSG

	sendmail $NOTIFICATION_TARGETS < $ALERT_MSG
	rm -f $ALERT_MSG
}


#
# Remove any old usage data before starting
#
rm -f /tmp/vrdiskmon.*.info > /dev/null 2>&1

while (true) do
echo " "
echo " "
cat vrdiskmon.fs |
while (true) do
read line
if (test "$line" = "") then
break
fi

parseFilesystemRecord $line

# Get the current usage
getCurrentUsage $FS
CURRENT_USAGE=$?

getUsageInfoFilename $FS

if (test $CURRENT_USAGE -lt $T1) then
echo "The current usage of [$CURRENT_USAGE] for [$FS] is below the lowest threshold of [$T1]"

# Since we are below the alerting threshold, remove any previous
# info we may have so we can start the "checking" with a clean
# slate
rm -f $FILESYSTEM_USAGE_INFO_FILE

else
getLastUsageInfo $FILESYSTEM_USAGE_INFO_FILE
getNextThresholdToUse $LAST_THRESHOLD_USED

if (test $CURRENT_USAGE -ge $THESHOLD_VALUE_TO_CHECK_AGAINST) then
echo " "
echo "FileSystem=[$FS], currentUsage=[$CURRENT_USAGE] usageFile=[$FILESYSTEM_USAGE_INFO_FILE]"
echo " LAST USAGE: numAlertsSent=[$NUM_ALERTS_SENT] lastThresholdUsed=[$LAST_THRESHOLD_USED] lastUsage=[$LAST_USAGE]"

if (test $NUM_ALERTS_SENT -lt $MAX_ALERTS) then
echo "Sending an alert for filesystem [$FS]"

sendAlert $FS $CURRENT_USAGE $LAST_USAGE

NUM_ALERTS_SENT=`expr $NUM_ALERTS_SENT + 1`
else
echo "Reached the maximum number of alerts. Alert NOT sent"
fi

LAST_USAGE=$CURRENT_USAGE
LAST_THRESHOLD_USED=$THRESHOLD_NUMBER_BEING_USED
else
echo "The usage of [$CURRENT_USAGE] for filesystem [$FS] has not exceeded the next threshold value of [$THESHOLD_VALUE_TO_CHECK_AGAINST]"
fi

saveLastUsageInfo $FILESYSTEM_USAGE_INFO_FILE

fi
done

# Sleep
SLEEP_INTERVAL_SECS=`expr $DISK_USAGE_CHECK_INTERVAL_MINS \* 60`
echo "Sleeping for $DISK_USAGE_CHECK_INTERVAL_MINS minutes ($SLEEP_INTERVAL_SECS seconds)"
sleep $SLEEP_INTERVAL_SECS

done