###########################################################################
## ##
## Ubuntu Mirror Script ##
## ##
## Creation: 06.07.2008 ##
## Last Update: 02.06.2012 ##
## ##
## Copyright (c) 2008-2012 by Georg Kainzbauer <georgkainzbauer@gmx.net> ##
## ##
## This program is free software; you can redistribute it and/or modify ##
## it under the terms of the GNU General Public License as published by ##
## the Free Software Foundation; either version 2 of the License, or ##
## (at your option) any later version. ##
## ##
###########################################################################
#!/bin/sh

appname=`basename $0`
nowdate=`date +%Y%m%d%H%M%S`
echo $$ > ${nowdate}.${appname}.pid

# Ubuntu mirror server and mirror directory
#SOURCE_SRV=cn.archive.ubuntu.com
SOURCE_SRV=archive.ubuntu.com
#SOURCE_SRV=mirrors.163.com
SOURCE_DIR=/ubuntu
# Distribution, section and architecture list
DIST=precise,precise-security,precise-updates,precise-backports,precise-proposed
SECTION=main,main/debian-installer,restricted,restricted/debian-installer,universe,universe/debian-installer,multiverse,multiverse/debian-installer
ARCH=i386,amd64
# Local mirror directory
#MIRRORDIR=/var/ftp/pub/linux/ubuntu/
MIRRORDIR=/home/ubuntu/
# Log file
LOGFILE=/var/log/ubuntu_mirror.log
# Debug file (if you do not want to debug the download process set this option to "/dev/null")
DEBUGFILE=/var/log/ubuntu_mirror.debug
# Who will be informed in case if anything goes wrong (if you do not want to be informed via mail, set this option to "")
#MAILNOTIFY="root@localhost"
# Lock file

LOCK=/var/tmp/ubuntu_mirror.lock
##################################################################
# NORMALY THERE IS NO NEED TO CHANGE ANYTHING BELOW THIS COMMENT #
##################################################################
function log()
{
    echo `date +%d.%m.%Y%t%H:%M:%S` " LOG:" $1 >>${LOGFILE}
}

function error()
{
    echo `date +%d.%m.%Y%t%H:%M:%S` " ERROR:" $1 >>${LOGFILE}
    if [ -n "$MAILNOTIFY" ] ; then
    echo `date +%d.%m.%Y%t%H:%M:%S` " ERROR:" $1 | mail -s "ERROR while synchronizing Ubuntu" $MAILNOTIFY
    fi
    echo $1 | grep "Lockfile" >/dev/null
    if [ $? = 1 ] ; then
    rm -f ${LOCK}
    fi
    rm ${nowdate}.${appname}.pid
    exit 1
}

function status()
{
    case "$1" in
    0)
    log "Synchronization completed."
    ;;
    1)
    error "DEBMIRROR: Connection closed"
    ;;
    2)
    error "DEBMIRROR: Timeout"
    ;;
    *)
    error "DEBMIRROR: Unknown error $1"
    ;;
    esac
}


if [ -f ${LOCK} ] ; then
    error "Lockfile ${LOCK} exists."
fi
touch ${LOCK}
# Create local mirror directory if not exists
if [ ! -d ${MIRRORDIR} ] ; then
    log "Creating local mirror directory."
    mkdir -p ${MIRRORDIR}
fi
log "Starting Ubuntu download process."
debmirror -v -e http -h ${SOURCE_SRV} -r ${SOURCE_DIR} --ignore-release-gpg --dist=${DIST} --section=${SECTION} --arch=${ARCH} ${MIRRORDIR} >> ${DEBUGFILE} 2>&1
status $?
rm -f ${LOCK}
rm ${nowdate}.${appname}.pid
exit 0


