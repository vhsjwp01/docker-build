#!/bin/bash
#set -s

PATH="/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin"
TERM="vt100"
export TERM PATH

DOCKER_BUILD_DIR="/usr/local/src/DOCKER/"

max_age="30"

my_rm=$(unalias rm > /dev/null 2>&1 ; which rm 2> /dev/null)
my_logger=$(unalias logger > /dev/null 2>&1 ; which logger 2> /dev/null)

if [ "${my_rm}" != "" -a "${my_logger}" != "" -a -d "${DOCKER_BUILD_DIR}" ]; then
    echo "Removing temporary build directories from ${DOCKER_BUILD_DIR} more than 30 days old ... "
    eval "find ${DOCKER_BUILD_DIR} -type d -maxdepth 1 -ctime +${max_age} -print -exec ${my_rm} -rf {} \;"
fi
