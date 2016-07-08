#!/bin/bash
#set -x

PATH="/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin"
TERM="vt100"
export TERM PATH

SUCCESS=0
ERROR=1

this_day=$(date +%A | tr '[A-Z]' '[a-z]')
this_host=$(hostname)
this_date=$(date)
message=""

# Make sure it is Saturday
#if [ "${this_day}" = "saturday" ]; then
if [ "${this_day}" = "thursday" ]; then
    target_dir="/var/lib/docker"
    bamboo_uid=$(ps -eaf | egrep "\-Dbamboo.home" | egrep -v grep | awk '{print $1}' | sort -nu | egrep -v root | tail -1)
    let idle_bamboo_uid_count=2

    if [ -d "${target_dir}" -a "${bamboo_uid}" != "" ]; then
        bamboo_uid_count=$(ps -eaf | awk '{print $1}' | egrep -c "^${bamboo_uid}$")

        if [ ${bamboo_uid_count} -eq ${idle_bamboo_uid_count} ]; then
            service docker stop                                                                           && 
            cd "${target_dir}"                                                                            &&
            rm -rf *                                                                                      && 
            cd /                                                                                          &&
            service docker start                                                                          &&
            message="Successfully sanitized docker container storage on ${this_host}, DATE: ${this_date}" ||
            message="Failed to sanitize docker container storage on ${this_host}, DATE: ${this_date}"
        fi

    fi

    if [ "${message}" != "" ]; then
        hipchat_config="/etc/sysconfig/hipchat/docker_cleanup.conf"
        hipchat_notify=$(unalias hipchat_room_message > /dev/null 2>&1 ; which hipchat_room_message 2> /dev/null)

        if [ "${hipchat_notify}" != "" -a -x "${hipchat_notify}" -a -e "${hipchat_config}" ]; then
            . "${hipchat_config}"

            if [ "${hipchat_API_token}" != "" -a "${hipchat_room_ID}" != "" -a "${hipchat_FROM}" != "" ]; then
                success_color="green"
                failure_color="red"

                let success_check=$(echo "${message}" | egrep -c "^Successfully")

                if [ ${success_check} -gt 0 ]; then
                    message_color="${success_color}"
                else
                    message_color="${failure_color}"
                fi

                echo -ne "DOCKER CLEANUP: ${message}" | "${hipchat_notify}" -n -t "${hipchat_API_token}" -c "${message_color}" -r "${hipchat_room_ID}" -f "${hipchat_FROM}" > /dev/null 2>&1
            fi

        fi

    fi

fi

