#!/bin/bash
#set -x

################################################################################
#                      S C R I P T    D E F I N I T I O N
################################################################################
#

#-------------------------------------------------------------------------------
# Revision History
#-------------------------------------------------------------------------------
# 20150114     Jason W. Plummer          Original: A generic script to run a 
#                                        docker job from bamboo.  Added code
#                                        to checkout and build a docker image
#                                        from a Stash repo.  Can also be run
#                                        standalone.
# 20150115     Jason W. Plummer          Added code to tag and commit docker
#                                        images both locally and remotely if
#                                        they are unique
# 20150116     Jason W. Plummer          Added more verbosity for operational
#                                        status during execution
# 20150119     Jason W. Plummer          Added argument to support custom docker
#                                        build arguments.  Also added code to
#                                        support latest git tag detection.
#                                        Added code to support making docker
#                                        build log available as an artifact 
#                                        when run from bamboo.
# 20150120     Jason W. Plummer          Added support to echo remote registry
#                                        operations into build log
# 20150121     Jason W. Plummer          Added --registry_namespace to allow
#                                        docker_namespace override when tagging
#                                        and pushing to a registry server.  Also
#                                        added git branch to ${docker_image_tag}
#                                        when not dealing with a release
# 20150122     Jason W. Plummer          Improved git branch and tag detection
# 20150126     Jason W. Plummer          Added --config option which allows
#                                        use of a file that when sourced 
#                                        provides key=value pairs for runtime,
#                                        rather than multiple command line args.
#                                        Added code to support checkout of 
#                                        submodiles within a git branch
# 20150127     Jason W. Plummer          Added more embedded code execution
#                                        protection for command line args
# 20150128     Jason W. Plummer          Added support for passing a fully 
#                                        qualified stash project uri.  Fixed
#                                        check for Dockerfile before building
# 20150129     Jason W. Plummer          Added current date in YYYYMMDDHHMMSS
#                                        format to docker image tag when the
#                                        git branch is not a tag
# 20150130     Jason W. Plummer          Added --registry_tag to allow
#                                        docker_image_tag override when pushing
#                                        to a registry server.
# 20150227     Jason W. Plummer          Added missing --remote_tag to images
#                                        that are being updated via push
# 20150303     Jason W. Plummer          Added support for Makefile detection
# 20150625     Jason W. Plummer          Added support for SSH key injection.
#                                        If the environment variables:
#                                            SSH_PUB_KEY
#                                            SSH_PRIV_KEY
#                                        are defined, then <source root>/ssh is 
#                                        populated with the respective values
#                                        for id_rsa.pub and id_rsa
# 20150625     Jason W. Plummer          Added logging for SSH key detection
# 20150702     Jason W. Plummer          Added -f to force remote tag overwrite
# 20150715     Jason W. Plummer          Added support for github repos.  Using
#                                        username + password for authentication
#                                        is NOT supported on purpose ... instead
#                                        add the invoking user's public SSH key
#                                        to the project's read-only permissions
#                                        to make this feature work

################################################################################
# DESCRIPTION
################################################################################
#

# NAME: icg-docker-build
# 
# This script performs a checkout of a stash based Docker project and attempts
# to build the docker image in question using the project's Dockerfile
#
# OPTIONS:
#
# --docker_registry        - The fully qualified URL of a private remote 
#                            docker registry.  This argument is OPTIONAL.
# --docker_namespace       - The namespace to use as a first level identifier 
#                            of the docker image created.  Defaults to 
#                            "ingramcontent".  This argument is OPTIONAL.
# --stash_project          - The Stash project name (both with or without the 
#                            .git suffix.  DO NOT USE THE FULLY QUALIFIED GIT 
#                            CHECKOUT URI FOR THIS OPTION.  This argument is 
#                            REQUIRED **UNLESS** --personal_stash_project is 
#                            provided.
# --git_branch             - The git branch upon which build operations are to 
#                            be performed.  This argument is REQUIRED.
# --personal_stash_project - The fully qualified git checkout URI from Stash
#                            for a personal project.  Setting this option has
#                            the following affect on environment variables:
#
#                            * STASH_BASE_URI is set using the ~ as the 
#                              delimiter
#                            * docker_namespace is set using the username after
#                              the ~
#                            * stash_project is set using the remaining portion
#                              of the string after the username
#
# --github_project         - The fully qualified git checkout GitHub URL
# --docker_build_args      - Extra build arguments to be passed to the docker
#                            build process.  This argument is OPTIONAL
# --registry_namespace     - The namespace to use when pushing to a docker
#                            registry server.  This argument is OPTIONAL
# --config                 - The path to a text file conatining key=value pairs
#                            in Bourne Shell syntax, meant to be used in lieu of
#                            multiple command line args.  This argument is 
#                            OPTIONAL
# --registry_tag           - The tag to use when pushing an image to a registry.
#                            This argument is OPTIONAL

################################################################################
# CONSTANTS
################################################################################
#

PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin
TERM=vt100
export TERM PATH

SUCCESS=0
ERROR=1

GIT_CHECKOUT_BASE="/usr/local/src/DOCKER"
STASH_BASE_URI="ssh://git@stash.ingramcontent.com:7999"

# Example clone from Stash:
# git clone ssh://git@stash.ingramcontent.com:7999/docker/passenger-nginx-rbenv.git
# ${my_git} ${my_git_action} ${STASH_BASE_URI}/${stash_project_repo}

STDOUT_OFFSET="    "

SCRIPT_NAME="${0}"

USAGE_ENDLINE="\n${STDOUT_OFFSET}${STDOUT_OFFSET}${STDOUT_OFFSET}${STDOUT_OFFSET}"
USAGE="${SCRIPT_NAME}${USAGE_ENDLINE}"
USAGE="${USAGE}[ --config <path to a config file that provides key=value assignments (suppresses command line args) *OPTIONAL*> ]${USAGE_ENDLINE}"
USAGE="${USAGE}[ --docker_build_args <extra arguments to the docker build command *OPTIONAL*> ]${USAGE_ENDLINE}"
USAGE="${USAGE}[ --docker_registry <fully qualified URL of remote docker registry server *OPTIONAL*> ]${USAGE_ENDLINE}"
USAGE="${USAGE}[ --docker_namespace <string 4-30 characters in length *OPTIONAL*> ]${USAGE_ENDLINE}"
USAGE="${USAGE}[ --git_branch <git branch to checkout *REQUIRED*> ]${USAGE_ENDLINE}"
USAGE="${USAGE}[ --personal_stash_project <fully qualified Git URI for checkout from Stash *SUPERCEDES --stash_project*> ]${USAGE_ENDLINE}"
USAGE="${USAGE}[ --github_project <fully qualified URL for checkout from GitHub *SUPERCEDES --stash_project*> ]${USAGE_ENDLINE}"
USAGE="${USAGE}[ --registry_namespace <namespace to use when pushing to a registry *OPTIONAL*> ]${USAGE_ENDLINE}"
USAGE="${USAGE}[ --registry_tag <image tag to use when pushing to a registry *OPTIONAL*> ]${USAGE_ENDLINE}"
USAGE="${USAGE}[ --stash_project <name of Stash project *REQUIRED*> ]"

################################################################################
# VARIABLES
################################################################################
#

err_msg=""
exit_code=${SUCCESS}

container_id=""
docker_image_tag=""
default_docker_namespace="ingramcontent"
is_release=0

################################################################################
# SUBROUTINES
################################################################################
#

# WHAT: Subroutine f__check_command
# WHY:  This subroutine checks the contents of lexically scoped ${1} and then
#       searches ${PATH} for the command.  If found, a variable of the form
#       my_${1} is created.
# NOTE: Lexically scoped ${1} should not be null, otherwise the command for
#       which we are searching is not present via the defined ${PATH} and we
#       should complain
#
f__check_command() {
    return_code=${SUCCESS}
    my_command="${1}"

    if [ "${my_command}" != "" ]; then
        my_command_check=`unalias "${i}" 2> /dev/null ; which "${1}" 2> /dev/null`

        if [ "${my_command_check}" = "" ]; then
            return_code=${ERROR}
        else
            eval my_${my_command}="${my_command_check}"
        fi

    else
        echo "${STDOUT_OFFSET}ERROR:  No command was specified"
        return_code=${ERROR}
    fi

    return ${return_code}
}

#-------------------------------------------------------------------------------

# WHAT: Subroutine f__git_operation
# WHY:  This subroutine performs a git operation ( passed as "${1}" ) against 
#       the Stash project in question ( passed as "${2}" ).  All git operations 
#       are performed in the following location:
#
#           ${GIT_CHECKOUT_BASE}/${stash_project}
#
# NOTE: The directory ${GIT_CHECKOUT_BASE}/${stash_project} is always flushed
#       before the start of operaitons to ensure concurrency
#
f__git_operation() {
    return_code=${SUCCESS}

    if [ "${1}" != "" ]; then
        this_git_action="${1}"

        case "${this_git_action}" in 

            branch)

                if [ "${GIT_CHECKOUT_BASE}" != "" -a "${stash_project}" != "" -a -d "${GIT_CHECKOUT_BASE}/${stash_project}" ]; then

                    if [ "${2}" = "" ]; then
                        cd "${GIT_CHECKOUT_BASE}/${stash_project}"
                        git_branch=`${my_git} ${this_git_action} 2> /dev/null | ${my_egrep} "^\*" | ${my_awk} '{print $NF}'`
                    else
                        new_branch="${2}"
                        ${my_git} ${this_git_action} ${new_branch}
                    fi

                else
                    err_msg="Could not complete git operation: ${this_git_action}"
                    ${my_false}
                fi

            ;;

            clone)

                if [ "${GIT_CHECKOUT_BASE}" != "" -a "${2}" != "" ]; then
                    this_stash_project_repo="${2}"
                    this_stash_project=`echo "${this_stash_project_repo}" | ${my_sed} -e 's/\.git$//g'`

                    if [ -d "${GIT_CHECKOUT_BASE}/${this_stash_project}" ]; then
                        ${my_rm} -rf "${GIT_CHECKOUT_BASE}/${this_stash_project}"
                    fi

                    if [ ! -d "${GIT_CHECKOUT_BASE}" ]; then
                        ${my_mkdir} -p "${GIT_CHECKOUT_BASE}"
                    fi
         
                    echo "${STDOUT_OFFSET}Performing git ${this_git_action} of ${STASH_BASE_URI}/${this_stash_project_repo}"
                    cd "${GIT_CHECKOUT_BASE}" && ${my_git} ${this_git_action} ${STASH_BASE_URI}/${this_stash_project_repo} &&

                    # Perform a git fetch --all to grab all refs, and a git pull --all to slurp down all branches
                    cd "${GIT_CHECKOUT_BASE}/${this_stash_project}" && ${my_git} fetch --all && ${my_git} pull --all &&

                    # Initialize any submodules
                    if [ -e "${GIT_CHECKOUT_BASE}/${this_stash_project}/.gitmodules" ]; then
                        ${my_git} submodule update --init --recursive &&
                        ${my_git} submodule foreach --recursive ${my_git} fetch
                    fi

                else
                    err_msg="Could not complete git operation: ${this_git_action}"
                    ${my_false}
                fi

            ;;

            checkout)

                if [ "${GIT_CHECKOUT_BASE}" != "" -a "${stash_project}" != "" -a "${2}" != "" ]; then
                    this_branch="${2}"

                    # Fetch all tags as they may be needed later
                    ${my_git} fetch --all
                    ${my_git} fetch --tags

                    if [ "${this_branch}" = "lastest_tag" ]; then
                        latest_tag=`${my_git} tag | ${my_sort} | ${my_tail} -1`

                        if [ "${latest_tag}" != "" ]; then
                            this_branch="${latest_tag}"
                        else
                            this_branch="ERROR__NO_LATEST_TAG_EXISTS"
                        fi

                    fi

                    # See if this branch exists
                    cd "${GIT_CHECKOUT_BASE}/${stash_project}"
                    let branch_check=`${my_git} branch -a | ${my_egrep} -c "origin/${this_branch}$"`

                    # If ${this_branch} cannot be found then see if we were passed a tag
                    if [ ${branch_check} -eq 0 ]; then
                        let branch_check=`${my_git} tag | ${my_egrep} -c "^${this_branch}$"`

                        if [ ${branch_check} -gt 0 ]; then
                            let is_release=1
                            docker_image_tag="${this_branch}"
                        fi

                    fi

                    # If ${this_branch} cannot be found then use master
                    if [ ${branch_check} -eq 0 ]; then
                        this_branch="master"
                    fi
            
                    echo "${STDOUT_OFFSET}Performing git ${this_git_action} of branch ${this_branch} in repo ${stash_project}"
                    cd "${GIT_CHECKOUT_BASE}/${stash_project}" && ${my_git} ${this_git_action} ${this_branch}

                    # Find our submodules and perform git checkout against them
                    submodule_files=`${my_find} . -depth -type f -name ".gitmodules"`

                    if [ "${submodule_files}" != "" ]; then

                        for submodule_file in ${submodule_files}; do
                            base_scm_dir=`${my_dirname} "${submodule_file}"`
                            these_submodules=`${my_egrep} "path =" "${submodule_file}" | ${my_awk} '{print $NF}'`

                            # Try to checkout the branch name we were passed, otherwise fall back to the master branch for the submodule
                            for this_submodule in ${these_submodules} ; do
                                cd "${GIT_CHECKOUT_BASE}/${base_scm_dir}/${this_submodule}" && ${my_git} ${this_git_action} ${this_branch} || ${my_git} ${this_git_action} master
                            done

                        done

                        # If all went well, set us back in the top level directory of the stash project
                        if [ ${?} -eq ${SUCCESS} ]; then
                            cd "${GIT_CHECKOUT_BASE}/${stash_project}"
                        fi

                    fi

                else
                    err_msg="Could not complete git operation: ${this_git_action}"
                    ${my_false}
                fi

            ;;

            rev-parse)

                if [ "${GIT_CHECKOUT_BASE}" != "" -a "${stash_project}" != "" -a -d "${GIT_CHECKOUT_BASE}/${stash_project}" -a "${2}" != "" -a "${3}" != "" ]; then
                    this_git_extra_args="${2}"
                    this_git_ref="${3}"
                    right_now=`${my_date} +%Y%m%d%H%M%S`
                    docker_image_tag=`cd "${GIT_CHECKOUT_BASE}/${stash_project}" && ${my_git} ${this_git_action} ${this_git_extra_args} ${this_git_ref}`
                    docker_image_tag="${right_now}.${git_branch}.${docker_image_tag}"
                else
                    err_msg="Could not complete git operation: ${this_git_action}"
                    ${my_false}
                fi

            ;;

        esac

        return_code=${?}
    else
        err_msg="No argument specified to function f__git_operation"
        return_code=${ERROR}
    fi

    return ${return_code}
}

################################################################################
# MAIN
################################################################################
#

# WHAT: Make sure we have some useful commands
# WHY:  Cannot proceed otherwise
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    for command in awk basename chmod curl date dirname docker egrep false file find git host jq mkdir rm sed sort tail tee wc ; do
        unalias ${command} > /dev/null 2>&1
        f__check_command "${command}"

        if [ ${?} -ne ${SUCCESS} ]; then
            let exit_code=${exit_code}+1
        fi

    done

fi

# WHAT: Make sure we have necessary arguments
# WHY:  Cannot proceed otherwise
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    while (( "${#}" )); do
        key=`echo "${1}" | ${my_sed} -e 's?\`??g'`
        value=`echo "${2}" | ${my_sed} -e 's?\`??g'`

        case "${key}" in

            --config|--docker_build_args|--docker_namespace|--docker_registry|--git_branch|--personal_stash_project|--registry_namespace|--registry_tag|--stash_project|--github_project)
                key=`echo "${key}" | ${my_sed} -e 's?^--??g'`

                if [ "${value}" != "" ]; then
                    eval ${key}="${value}"
                    shift
                    shift
                else
                    echo "${STDOUT_OFFSET}ERROR:  No value assignment can be made for command line argument \"--${key}\""
                    exit_code=${ERROR}
                    shift
                fi

            ;;

            *)
                # We bail immediately on unknown or malformed inputs
                echo "${STDOUT_OFFSET}ERROR:  Unknown command line argument ... exiting"
                exit
            ;;

        esac

    done

    # If we were passed --config, then make sure the config file exists,
    # that is is a text file, then source it.  Otherwise, bail immediately
    if [ "${config}" != "" -a -e "${config}" ]; then
        let is_text=`${my_file} "${config}" | ${my_egrep} -ic "text"`

        if [ ${is_text} -eq 0 ]; then
            echo "${STDOUT_OFFSET}ERROR:  Config file \"${config}\" is not a text file ... exiting"
            exit
        else
            source "${config}"
        fi

    fi

    # If we were passed --personal_stash_project, then parse that and redefine
    # STASH_BASE_URI, stash_project, and docker_namespace
    # ssh://git@stash.ingramcontent.com:7999/~ptinsley/prodstatdev.git
    if [ "${personal_stash_project}" != "" ]; then
        stash_base_uri=`echo "${personal_stash_project}" | ${my_awk} -F'~' '{print $1}' | ${my_sed} -e 's?/$??g'`
        docker_namespace=`echo "${personal_stash_project}" | ${my_awk} -F'~' '{print $2}' | ${my_awk} -F'/' '{print $1}'`
        stash_project=`echo "${personal_stash_project}" | ${my_awk} -F'~' '{print $2}' | ${my_awk} -F'/' '{print $NF}'`
        STASH_BASE_URI="${stash_base_uri}/~${docker_namespace}"
    fi

    # If we were passed --github_project, then parse that snd redefine
    # STASH_BASE_URI, stash_project, and docker_namespace
    # git@github.com:vitalsource/vst-client.git
    if [ "${github_project}" != "" ]; then
        stash_base_uri=`echo "${github_project}" | ${my_awk} -F'/' '{print $1}'`
        docker_namespace=`echo "${github_project}" | ${my_awk} -F':' '{print $2}' | awk -F'/' '{print $1}'`
        stash_project=`echo "${github_project}" | ${my_awk} -F'/' '{print $NF}'`
        STASH_BASE_URI="${stash_base_uri}/${docker_namespace}"
    fi

    # See if we were passed a fully qualified stash URL
    # Example: ssh://git@stash.ingramcontent.com:7999/wad/prodstatdev.git
    if [ "${stash_project}" != "" ]; then
        let stash_url_check=`echo "${stash_project}" | ${my_egrep} -ci "^${STASH_BASE_URI}"`

        # If so, let's redefine STASH_BASE_URI, stash_project, and docker_namespace
        if [ ${stash_url_check} -gt 0 ]; then
            real_stash_project=`echo "${stash_project}" | ${my_awk} -F'/' '{print $NF}'`
            stash_base_uri=`echo "${stash_project}" | ${my_sed} -e "s?/${real_stash_project}\\\$??g"`

            if [ "${docker_namespace}" = "" ]; then
                docker_namespace=`echo "${stash_base_uri}" | ${my_awk} -F'/' '{print $NF}'`
            fi

            stash_project="${real_stash_project}"
            STASH_BASE_URI="${stash_base_uri}"
        fi

    fi

    # Make sure supplied arguments are sane
    if [ "${docker_namespace}" != "" ]; then

        # Make sure namespace is sane
        let ns_check=`echo "${docker_namespace}" | ${my_egrep} -c "[^a-zA-Z0-9]"`
        let ns_length=`echo -ne "${docker_namespace}" | ${my_wc} -c | ${my_awk} '{print $1}'`

        if [ ${ns_check} -gt 0 ]; then
            echo "${STDOUT_OFFSET}ERROR:  Invalid characters detected in namespace \"${docker_namespace}\".  Only a-z, A-Z, and 0-9 are allowed"
            exit_code=${ERROR}
        fi

        if [ ${ns_length} -lt 4 -o ${ns_length} -gt 30 ]; then
            echo "${STDOUT_OFFSET}ERROR:  The docker namespace must be between 4 and 30 characters in length"
            exit_code=${ERROR}
        fi

    else
        docker_namespace="${default_docker_namespace}"
    fi

    if [ "${registry_namespace}" != "" ]; then

        # Make sure namespace is sane
        let ns_check=`echo "${registry_namespace}" | ${my_egrep} -c "[^a-zA-Z0-9]"`
        let ns_length=`echo -ne "${registry_namespace}" | ${my_wc} -c | ${my_awk} '{print $1}'`

        if [ ${ns_check} -gt 0 ]; then
            echo "${STDOUT_OFFSET}ERROR:  Invalid characters detected in namespace \"${registry_namespace}\".  Only a-z, A-Z, and 0-9 are allowed"
            exit_code=${ERROR}
        fi

        if [ ${ns_length} -lt 4 -o ${ns_length} -gt 30 ]; then
            echo "${STDOUT_OFFSET}ERROR:  The docker registry namespace must be between 4 and 30 characters in length"
            exit_code=${ERROR}
        fi

    fi

    if [ "${docker_registry}" != "" ]; then

        # Make sure docker_registry is a URL
        let dr_url_check=`echo "${docker_registry}" | ${my_egrep} -c "^http"`

        if [ ${dr_url_check} -gt 0 ]; then

            # We use the uri env var to perform docker pull and push commands
            docker_registry_uri=`echo "${docker_registry}" | ${my_awk} -F'//' '{print $NF}'`
            docker_registry_host=`echo "${docker_registry_uri}" | awk -F':' '{print $1}'`
            let is_valid_host=`${my_host} "${docker_registry_host}" | ${my_egrep} -c "has address|domain name pointer"`

            # We use the url env var to perform curl commands
            if [ ${is_valid_host} -gt 0 ]; then
                docker_registry_url="${docker_registry}"
            else
                echo "${STDOUT_OFFSET}ERROR:  Docker registry \"${docker_registry}\" could not be resolved via DNS"
                exit_code=${ERROR}
            fi

        else
            echo "${STDOUT_OFFSET}ERROR:  The value for --docker_registry must be a properly formatted URL"
            exit_code=${ERROR}
        fi

    fi

    if [ "${stash_project}" != "" -a "${git_branch}" != "" ]; then

        # Make sure stash project name is sane (stash project repo name should end in .git"
        git_suffix_check=`echo "${stash_project}" | ${my_egrep} -c "\.git$"`

        if [ ${git_suffix_check} -eq 0 ]; then
            stash_project_repo="${stash_project}.git"
        else
            stash_project_repo="${stash_project}"
            stash_project=`echo "${stash_project}" | ${my_sed} -e 's/\.git$//g'`
        fi

    else
        echo "${STDOUT_OFFSET}ERROR:  Not enough arguments provided.  Arguments --stash_project and --git_branch must be defined"
        exit_code=${ERROR}
    fi

fi

# WHAT: Checkout the stash project
# WHY:  Asked to
#
if [ ${exit_code} -eq ${SUCCESS} ]; then
    my_git_action="clone"
    f__git_operation ${my_git_action} ${stash_project_repo}
    exit_code=${?}
fi

# WHAT: Checkout code branch
# WHY:  Asked to
#
if [ ${exit_code} -eq ${SUCCESS} ]; then
    my_git_action="checkout"
    f__git_operation ${my_git_action} ${git_branch}
    exit_code=${?}
fi

# WHAT: Figure out what branch we are really on
# WHY:  This is needed because we fall back to the master branch 
#       if the requested branch doesn't exist
#
if [ ${exit_code} -eq ${SUCCESS} ]; then
    my_git_action="branch"
    f__git_operation ${my_git_action}
    exit_code=${?}
fi

# WHAT: Build docker image from source
# WHY:  Asked to
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    # Setup logging
    if [ "${bamboo_working_directory}" != "" ]; then
        artifact_file="${bamboo_working_directory}/${stash_project}.dockerbuild.log"
        env_file="${bamboo_working_directory}/${stash_project}.env"
    else
        artifact_file="/tmp/${stash_project}.dockerbuild.log"
        env_file="/tmp/${stash_project}.env"
    fi

    echo "Starting build `${my_date}`" > "${artifact_file}"

    # WHAT: If ${SSH_PUB_KEY} and ${SSH_PRIV_KEY} is defined, then create
    #       an ssh folder at the top level and seed it as asked
    # WHY:  Needed for image borne automation
    #

    # Detect ssh pub key passed in as bamboo variable
    if [ "${bamboo_ssh_pub_key}" != "" ]; then
        echo "Detected SSH public key from Bamboo" >> "${artifact_file}" 2>&1
        SSH_PUB_KEY="${bamboo_ssh_pub_key}"
    fi

    # Detect ssh priv key passed in as bamboo variable
    if [ "${bamboo_ssh_priv_key}" != "" ]; then
        echo "Detected SSH private key from Bamboo" >> "${artifact_file}" 2>&1
        SSH_PRIV_KEY="${bamboo_ssh_priv_key}"
    fi

    # Pick up SSH keys and make them real
    if [ "${SSH_PUB_KEY}" != "" -a "${SSH_PRIV_KEY}" != "" ]; then
        echo "Detected SSH public and private keys from ENV" >> "${artifact_file}" 2>&1
        target_dir="${GIT_CHECKOUT_BASE}/${stash_project}/ssh"

        # Create the ssh directory if it is absent
        if [ ! -d "${target_dir}" ]; then
            echo "Creating SSH key dir \"${target_dir}\"" >> "${artifact_file}" 2>&1
            ${my_mkdir} -p "${target_dir}"
        fi

        echo "Creating SSH key file \"${target_dir}/id_rsa.pub\"" >> "${artifact_file}" 2>&1
        echo -ne "${SSH_PUB_KEY}\n" > "${target_dir}/id_rsa.pub"

        echo "Creating SSH key file \"${target_dir}/id_rsa\"" >> "${artifact_file}" 2>&1
        echo -ne "${SSH_PRIV_KEY}\n" > "${target_dir}/id_rsa"

        echo "Creating SSH config file \"${target_dir}/config\"" >> "${artifact_file}" 2>&1
        echo "StrictHostKeyChecking no" > "${target_dir}/config"

        echo "Setting permissions on \"${target_dir}/config\" to 700" >> "${artifact_file}" 2>&1
        ${my_chmod} 700 "${target_dir}"

        echo "Setting permissions on \"${target_dir}/id_rsa.pub\" to 644" >> "${artifact_file}" 2>&1
        ${my_chmod} 644 "${target_dir}/id_rsa.pub"

        echo "Setting permissions on \"${target_dir}/id_rsa\" to 600" >> "${artifact_file}" 2>&1
        ${my_chmod} 600 "${target_dir}/id_rsa"

        echo "Setting permissions on \"${target_dir}/config\" to 644" >> "${artifact_file}" 2>&1
        ${my_chmod} 644 "${target_dir}/config"
    fi

    # Build using a Makefile
    #    ASSUMPTIONS:
    #        (1) There is a build target named "build" which builds *AND* tags the docker image
    #        (2) There is a build target named "push" which pushes the docker image to the registry
    if [ -e "${GIT_CHECKOUT_BASE}/${stash_project}/Makefile" ]; then
        my_make=`which make 2> /dev/null`

        if [ "${my_make}" != "" ]; then
            let build_directive=`${my_make} -qpn | ${my_egrep} "^build:" | ${my_wc} -l | ${my_awk} '{print $1}'`

            if [ ${build_directive} -gt 0 ]; then
                echo "Performing docker build against ${GIT_CHECKOUT_BASE}/${stash_project}/Makefile ... see ${artifact_file} for status"
                cd "${GIT_CHECKOUT_BASE}/${stash_project}" && ${my_make} build >> "${artifact_file}" 2>&1
                exit_code=${?}

                if [ ${exit_code} -ne ${SUCCESS} ]; then
                    err_msg="Build of Docker image ${stash_project} failed"
                else
                    container_id=`${my_tail} -1 ${artifact_file} | ${my_egrep} -i "^successfully built" | ${my_awk} '{print $NF}'`

                    if [ "${container_id}" = "" ]; then
                        err_msg="Failed to determine container id after building docker image ${stash_project}"
                        exit_code=${ERROR}
                    fi

                fi

            else
                err_msg="Makefile found, but no target named \"build\" was detected"
                exit_code=${ERROR}
            fi

        fi

    # Build using a Dockerfile
    elif [ -e "${GIT_CHECKOUT_BASE}/${stash_project}/Dockerfile" ]; then
        echo "Performing docker build against ${GIT_CHECKOUT_BASE}/${stash_project}/Dockerfile ... see ${artifact_file} for status"
        cd "${GIT_CHECKOUT_BASE}/${stash_project}" && ${my_docker} build ${docker_build_args} . >> "${artifact_file}" 2>&1
        exit_code=${?}

        if [ ${exit_code} -ne ${SUCCESS} ]; then
            err_msg="Build of Docker image ${stash_project} failed"
        else
            container_id=`${my_tail} -1 ${artifact_file} | ${my_egrep} -i "^successfully built" | ${my_awk} '{print $NF}'`

            if [ "${container_id}" = "" ]; then
                err_msg="Failed to determine container id after building docker image ${stash_project}"
                exit_code=${ERROR}
            fi

        fi

    else
        err_msg="Could locate neither a Makefile nor Dockerfile in directory \"${GIT_CHECKOUT_BASE}/${stash_project}\""
        exit_code=${ERROR}
    fi

fi

# WHAT: Set the environment variable ${docker_image_tag}
# WHY:  If we got here, then ${container_id} is defined
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    # Only execute this if we are *NOT* using Makefiles
    if [ "${my_make}" = "" ]; then

        # If this is a release, then ${docker_image_tag} is already defined as
        # the git tag, otherwise we need to run git rev-parse so we can set the 
        # ${docker_image_tag} to the shortened git commit hash for this branch
        #
        # Use git commit hash for the current branch as the image tag ( when ${is_release} == 0 ):
        # git rev-parse --short=10 HEAD
        # 
        if [ ${is_release} -eq 0 ]; then
            my_git_action="rev-parse"
            my_git_action_arg="--short=10"
            my_git_ref="HEAD"
            f__git_operation ${my_git_action} ${my_git_action_arg} ${my_git_ref}
            exit_code=${?}
        fi

    fi

fi

# WHAT: Commit the new container ID with a tag
# WHY:  If we got here, then ${docker_image_tag} is defined
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    # Only execute this if we are *NOT* using Makefiles
    if [ "${my_make}" = "" ]; then
        # Convert '/' in ${docker_image_tag} to '-'
        docker_image_tag=`echo "${docker_image_tag}" | ${my_sed} -e 's?/?\-?g'`

        local_image_change="no"
        let local_image_check=`${my_docker} images | ${my_awk} '{print $1 ":" $2}' | ${my_egrep} -c "^${docker_namespace}/${stash_project}:${docker_image_tag}$"`

        # Only perform a local tag if the image is absent from the local registry
        if [ ${local_image_check} -eq 0 ]; then
            local_image_change="yes"
            echo "Tagging newly created container id ${container_id} as: ${docker_namespace}/${stash_project}:${docker_image_tag}" | ${my_tee} >> "${artifact_file}"
            ${my_docker} tag ${container_id} ${docker_namespace}/${stash_project}:${docker_image_tag}
            exit_code=${?}

            if [ ${exit_code} -ne ${SUCCESS} ]; then
                err_msg="Failed to locally tag docker image ID: ${container_id}"
            fi

        else
            echo "Docker local image tag ${docker_namespace}/${stash_project}:${docker_image_tag} already exists ... no action taken" | ${my_tee} >> "${artifact_file}"
        fi

    fi

fi

# WHAT: Tag and push the new container ID to the registry, if possible
# WHY:  If we got here, then ${docker_image_tag} is defined
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    # If we are using Makefiles, then execute push directive ...
    if [ "${my_make}" != "" ]; then
        let push_directive=`${my_make} -qpn | ${my_egrep} "^push:" | ${my_wc} -l | ${my_awk} '{print $1}'`

        if [ ${build_directive} -gt 0 ]; then
            echo "Pushing image to remote registry" | ${my_tee} >> "${artifact_file}"
            cd "${GIT_CHECKOUT_BASE}/${stash_project}" && ${my_make} push >> "${artifact_file}"
            exit_code=${?}

            if [ ${exit_code} -ne ${SUCCESS} ]; then
                err_msg="Push of Docker image ${stash_project} failed"
            fi

        else
            err_msg="Makefile found, but no target named \"push\" was detected"
            exit_code=${ERROR}
        fi

    # ... otherwise, process based on docker build output and other command line directives
    else

        # Only do this part if ${docker_registry} is defined, otherwise
        # we're done processing this docker image repo
        #
        if [ "${docker_registry}" != "" ]; then
            remote_namespace="${docker_namespace}"
            remote_tag="${docker_image_tag}"

            # Override ${remote_namespace} if ${registry_namespace} is defined
            if [ "${registry_namespace}" != "" ]; then
                remote_namespace="${registry_namespace}"
            fi

            # Override ${remote_tag} if ${registry_tag} is defined
            if [ "${registry_tag}" != "" ]; then
                remote_tag="${registry_tag}"
            fi

            remote_image_change="no"
            let remote_tag_check=0
            let remote_image_check=`${my_curl} ${docker_registry_url}/v1/search?q=${stash_project} 2> /dev/null | ${my_jq} ".num_results"`

            # Only perform a remote tag and push if the image is absent from the registry server
            if [ ${remote_image_check} -eq 0 ]; then
                remote_image_change="yes"
                remote_image_name="${docker_registry_uri}/${remote_namespace}/${stash_project}:${remote_tag}"
                echo "Adding new image ${docker_namespace}/${stash_project}:${docker_image_tag} to remote registry as ${docker_registry_uri}/${remote_namespace}/${stash_project}:${remote_tag}" | ${my_tee} >> "${artifact_file}"
                ${my_docker} tag ${container_id} ${docker_registry_uri}/${remote_namespace}/${stash_project}:${remote_tag} &&
                ${my_docker} push ${docker_registry_uri}/${remote_namespace}/${stash_project}:${remote_tag}
            else
                # JSON results use zero based indexing
                let remote_image_counter=${remote_image_check}-1

                while [ ${remote_image_counter} -ge 0 ]; do
                    this_image_name=`${my_curl} ${docker_registry_url}/v1/search?q=${stash_project} 2> /dev/null | ${my_jq} ".results[${remote_image_counter}].name" | ${my_sed} -e 's/"//g'`

                    if [ "${this_image_name}" = "${remote_namespace}/${stash_project}" ]; then
                        remote_image_tags=`${my_curl} ${docker_registry_url}/v1/repositories/${this_image_name}/tags 2> /dev/null | ${my_jq} "." | ${my_awk} '/:/ {print $1}' | ${my_sed} -e 's/[",:]//g'`

                        for remote_image_tag in ${remote_image_tags} ; do

                            if [ "${this_image_name}:${remote_image_tag}" = "${remote_namespace}/${stash_project}:${docker_image_tag}" ]; then
                                let remote_tag_check=${remote_tag_check}+1
                            fi

                        done

                    fi

                    let remote_image_counter=${remote_image_counter}-1
                done

                if [ ${remote_tag_check} -eq 0 ]; then
                    echo "Pushing updated image ${docker_namespace}/${stash_project}:${docker_image_tag} to remote registry as ${docker_registry_uri}/${remote_namespace}/${stash_project}:${remote_tag}" | ${my_tee} >> "${artifact_file}"
                    ${my_docker} tag -f ${container_id} ${docker_registry_uri}/${remote_namespace}/${stash_project}:${remote_tag} &&
                    ${my_docker} push ${docker_registry_uri}/${remote_namespace}/${stash_project}:${remote_tag}
                else
                    echo "Docker remote image tag ${docker_registry_uri}/${remote_namespace}/${stash_project}:${remote_tag} already exists ... no action taken" | ${my_tee} >> "${artifact_file}"
                fi

            fi

            exit_code=${?}
        fi

    fi

fi

# WHAT: If ${env_file} is defined, dump all of our custom variables into it
# WHY:  Used for debugging, and also for CI
#
if [ "${env_file}" != "" ]; then

    for var in config docker_build_args docker_image_tag docker_namespace docker_registry docker_registry_uri git_branch personal_stash_project registry_namespace registry_tag stash_project ; do
        eval "echo ${var}=\"\$${var}\""
    done > "${env_file}"

fi
    
# WHAT: Complain if necessary and exit
# WHY:  Success or failure, either way we are through
#
if [ ${exit_code} -ne ${SUCCESS} ]; then

    if [ "${err_msg}" != "" ]; then
        echo
        echo -ne "${STDOUT_OFFSET}ERROR:  ${err_msg} ... processing halted\n"
        echo
    fi

    echo
    echo -ne "${STDOUT_OFFSET}USAGE:  ${USAGE}\n"
    echo
fi

exit ${exit_code}
