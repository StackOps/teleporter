#   Copyright 2013 STACKOPS TECHNOLOGIES S.L.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
#!/usr/bin/env bash

set -e
set -o nounset                              # Treat unset variables as an error
ScriptVersion="1.0"
ScriptName="teleporter.sh"

DISK_FORMAT="raw"

#OS_USERNAME=$1
#OS_PASSWORD=$2
#OS_TENANT_NAME=$3
#IMAGE_NAME=$4
#DEVICE=$5

OS_USERNAME=${1:-admin}
OS_PASSWORD=${2:-password}
OS_TENANT_NAME=${3:-admin}
OS_AUTH_URL=https://api.stackops.net/v2.0
OS_GLANCE_URL=http://glance-se1.stackops.net:9292/v1
IMAGE_NAME=${4:-`hostname`}
DEVICE=${5:-sda}


usage() {
    cat << EOT

  Usage :  ${ScriptName} [options] <install-args>

  Options:
  -h|help       Display this message
  -v|version    Display script version
EOT
}

while getopts ":hvc:" opt
do
  case $opt in

    h|help          )  usage; exit 0   ;;

    v|version       )  echo "$0 -- Version $ScriptVersion"; exit 0   ;;

    \?              )  echo "\n  Option does not exist : $OPTARG\n"
                       usage; exit 1   ;;

  esac
done
shift $(($OPTIND-1))

__check_unparsed_options() {
    shellopts="$1"
    unparsed_options=$( echo "$shellopts" | grep -E '[-]+[[:alnum:]]' )
    if [ "x$unparsed_options" != "x" ]; then
        usage
        echo
        echo " * ERROR: options come before install arguments"
        echo
        exit 1
    fi
}

if [ "$#" -gt 5 ]; then
    __check_unparsed_options "$*"
    usage
    echo
    echo " * ERROR: Too many arguments."
    exit 1
fi

# Root permissions are required to run this script
if [ $(whoami) != "root" ] ; then
    echo " * ERROR: Requires root. Please re-run this script as root."
    exit 1
fi

#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __gather_hardware_info
#   DESCRIPTION:  Discover hardware information
#-------------------------------------------------------------------------------
__gather_hardware_info() {
    if [ -f /proc/cpuinfo ]; then
        CPU_VENDOR_ID=$(cat /proc/cpuinfo | grep -E 'vendor_id|Processor' | head -n 1 | awk '{print $3}' | cut -d '-' -f1 )
    else
        CPU_VENDOR_ID=$( sysctl -n hw.model )
    fi
    CPU_VENDOR_ID_L=$( echo $CPU_VENDOR_ID | tr '[:upper:]' '[:lower:]' )
    CPU_ARCH=$(uname -m 2>/dev/null || uname -p 2>/dev/null || echo "unknown")
    CPU_ARCH_L=$( echo $CPU_ARCH | tr '[:upper:]' '[:lower:]' )

}
__gather_hardware_info


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __gather_os_info
#   DESCRIPTION:  Discover operating system information
#-------------------------------------------------------------------------------
__gather_os_info() {
    OS_NAME=$(uname -s 2>/dev/null)
    OS_NAME_L=$( echo $OS_NAME | tr '[:upper:]' '[:lower:]' )
    OS_VERSION=$(uname -r)
    OS_VERSION_L=$( echo $OS_VERSION | tr '[:upper:]' '[:lower:]' )
}
__gather_os_info


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __parse_version_string
#   DESCRIPTION:  Parse version strings ignoring the revision.
#                 MAJOR.MINOR.REVISION becomes MAJOR.MINOR
#-------------------------------------------------------------------------------
__parse_version_string() {
    VERSION_STRING="$1"
    PARSED_VERSION=$(
        echo $VERSION_STRING |
        sed -e 's/^/#/' \
            -e 's/^#[^0-9]*\([0-9][0-9]*\.[0-9][0-9]*\)\(\.[0-9][0-9]*\).*$/\1/' \
            -e 's/^#[^0-9]*\([0-9][0-9]*\.[0-9][0-9]*\).*$/\1/' \
            -e 's/^#[^0-9]*\([0-9][0-9]*\).*$/\1/' \
            -e 's/^#.*$//'
    )
    echo $PARSED_VERSION
}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __gather_linux_system_info
#   DESCRIPTION:  Discover Linux system information
#-------------------------------------------------------------------------------
__gather_linux_system_info() {
    DISTRO_NAME=""
    DISTRO_VERSION=""

    if [ -f /etc/lsb-release ]; then
        DISTRO_NAME=$(grep DISTRIB_ID /etc/lsb-release | sed -e 's/.*=//')
        DISTRO_VERSION=$(__parse_version_string $(grep DISTRIB_RELEASE /etc/lsb-release | sed -e 's/.*=//'))
    fi

    if [ "x$DISTRO_NAME" != "x" -a "x$DISTRO_VERSION" != "x" ]; then
        # We already have the distribution name and version
        return
    fi

    for rsource in $(
            cd /etc && /bin/ls *[_-]release *[_-]version 2>/dev/null | env -i sort | \
            sed -e '/^redhat-release$/d' -e '/^lsb-release$/d'; \
            echo redhat-release lsb-release
            ); do

        [ -L "/etc/${rsource}" ] && continue        # Don't follow symlinks
        [ ! -f "/etc/${rsource}" ] && continue      # Does not exist

        n=$(echo ${rsource} | sed -e 's/[_-]release$//' -e 's/[_-]version$//')
        v=$( __parse_version_string "$( (grep VERSION /etc/${rsource}; cat /etc/${rsource}) | grep '[0-9]' | sed -e 'q' )" )
        case $(echo ${n} | tr '[:upper:]' '[:lower:]') in
            redhat )
                if [ ".$(egrep '(Red Hat Enterprise Linux|CentOS)' /etc/${rsource})" != . ]; then
                    n="<R>ed <H>at <E>nterprise <L>inux"
                else
                    n="<R>ed <H>at <L>inux"
                fi
                ;;
            arch               ) n="Arch"           ;;
            centos             ) n="CentOS"         ;;
            debian             ) n="Debian"         ;;
            ubuntu             ) n="Ubuntu"         ;;
            fedora             ) n="Fedora"         ;;
            suse               ) n="SUSE"           ;;
            mandrake*|mandriva ) n="Mandriva"       ;;
            gentoo             ) n="Gentoo"         ;;
            slackware          ) n="Slackware"      ;;
            turbolinux         ) n="TurboLinux"     ;;
            unitedlinux        ) n="UnitedLinux"    ;;
            *                  ) n="${n}"           ;
        esac
        DISTRO_NAME=$n
        DISTRO_VERSION=$v
        break
    done
}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __gather_sunos_system_info
#   DESCRIPTION:  Discover SunOS system info
#-------------------------------------------------------------------------------
__gather_sunos_system_info() {
    DISTRO_NAME="Solaris"
    DISTRO_VERSION=$(
        echo "${OS_VERSION}" |
        sed -e 's;^4\.;1.;' \
            -e 's;^5\.\([0-6]\)[^0-9]*$;2.\1;' \
            -e 's;^5\.\([0-9][0-9]*\).*;\1;'
    )
}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __gather_bsd_system_info
#   DESCRIPTION:  Discover OpenBSD, NetBSD and FreeBSD systems information
#-------------------------------------------------------------------------------
__gather_bsd_system_info() {
    DISTRO_NAME=${OS_NAME}
    DISTRO_VERSION=$(echo "${OS_VERSION}" | sed -e 's;[()];;' -e 's/-.*$//')
}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __gather_system_info
#   DESCRIPTION:  Discover which system and distribution we are running.
#-------------------------------------------------------------------------------
__gather_system_info() {
    case ${OS_NAME_L} in
        linux )
            __gather_linux_system_info
            ;;
        sunos )
            __gather_sunos_system_info
            ;;
        openbsd|freebsd|netbsd )
            __gather_bsd_system_info
            ;;
        * )
            echo " * ERROR: $OS_NAME not supported.";
            exit 1
            ;;
    esac

}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __function_defined
#   DESCRIPTION:  Checks if a function is defined within this scripts scope
#    PARAMETERS:  function name
#       RETURNS:  0 or 1 as in defined or not defined
#-------------------------------------------------------------------------------
__function_defined() {
    FUNC_NAME=$1
    if [ "${DISTRO_NAME}" = "centos" ]; then
        if typeset -f $FUNC_NAME &>/dev/null ; then
            echo " * INFO: Found function $FUNC_NAME"
            return 0
        fi
    elif [ "${DISTRO_NAME}" = "ubuntu" ]; then
        if $( type ${FUNC_NAME} | grep -q 'shell function' ); then
            echo " * INFO: Found function $FUNC_NAME"
            return 0
        fi
    # Last resorts try POSIXLY_CORRECT or not
    elif test -n "${POSIXLY_CORRECT+yes}"; then
        if typeset -f $FUNC_NAME >/dev/null 2>&1 ; then
            echo " * INFO: Found function $FUNC_NAME"
            return 0
        fi
    else
        # Arch linux seems to fall here
        if $( type ${FUNC_NAME}  >/dev/null 2>&1 ) ; then
            echo " * INFO: Found function $FUNC_NAME"
            return 0
        fi
    fi
    echo " * INFO: $FUNC_NAME not found...."
    return 1
}
__gather_system_info

echo " * System Information:"
echo "     CPU:          ${CPU_VENDOR_ID}"
echo "     CPU Arch:     ${CPU_ARCH}"
echo "     OS Name:      ${OS_NAME}"
echo "     OS Version:   ${OS_VERSION}"
echo "     Distribution: ${DISTRO_NAME} ${DISTRO_VERSION}"


# Simplify version naming on functions
if [ "x${DISTRO_VERSION}" = "x" ]; then
    DISTRO_VERSION_NO_DOTS=""
else
    DISTRO_VERSION_NO_DOTS="_$(echo $DISTRO_VERSION | tr -d '.')"
fi
# Simplify distro name naming on functions
DISTRO_NAME_L=$(echo $DISTRO_NAME | tr '[:upper:]' '[:lower:]' | sed 's/[^a-zA-Z0-9_ ]//g' | sed -e 's|[:space:]+|_|g')

#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __apt_get_noinput
#   DESCRIPTION:  (DRY) apt-get install with noinput options
#-------------------------------------------------------------------------------
__apt_get_noinput() {
    apt-get install -y -o DPkg::Options::=--force-confold $@
}

__check_command() {
    command -v $1 >/dev/null 2>&1 || { echo >&2 "I require $1 but it's not installed.  Aborting."; exit 1; }
}

__check_device() {
    if [ ! -e /dev/$1 ] ; then
         echo >&2 "/dev/$1 does not exists.  Aborting."; exit 1;
    fi
}

__get_auth_token() {
    credentials=`curl -s -d "{\"auth\":{\"passwordCredentials\": {\"username\": \"$OS_USERNAME\", \"password\": \"$OS_PASSWORD\"}, \"tenantName\": \"$OS_TENANT_NAME\"}}" -H "Content-type: application/json" $OS_AUTH_URL/tokens`
    auth_token=`echo $credentials | python -c "import sys; import json; tok = json.loads(sys.stdin.read()); print tok['access']['token']['id'];"`
    [ ! -z "${auth_token}" ] || { echo >&2 `echo $credentials | python -c "import sys; import json; tok = json.loads(sys.stdin.read()); print tok['error'];"`; exit 1; }
    echo $auth_token
}

__show_credentials() {
    echo "Username: $OS_USERNAME"
    echo "Tenant: $OS_TENANT_NAME"
    echo "Image: $IMAGE_NAME"
    echo "Device: /dev/$DEVICE"
}

__export_physical_disk() {
    echo "Exporting /dev/$DEVICE as file name $IMAGE_NAME. It can take a while!"
    dd bs=16M if=/dev/$DEVICE | curl -s -S  -i -X POST -H 'x-image-meta-container_format: bare' -H 'Transfer-Encoding: chunked' -H 'User-Agent: stackops-teleporter' -H 'x-image-meta-is_public: False' -H "X-Auth-Token: $1" -H 'Content-Type: application/octet-stream' -H "x-image-meta-disk_format: $DISK_FORMAT" -H "x-image-meta-name: $IMAGE_NAME" -T - $OS_GLANCE_URL/images
}

install_ubuntu_1404() {
    __check_command "dd"
    __check_command "curl"
    __check_device $DEVICE
    __show_credentials
}

post_install_ubuntu_1404() {
     echo "Post install on ubuntu_1404"
}

conf_ubuntu_1404() {
    auth_token=`__get_auth_token`
    echo "Token: $auth_token"
    __export_physical_disk $auth_token
}


install_ubuntu_1204() {
     install_ubuntu_1404
}

post_install_ubuntu_1204() {
     post_install_ubuntu_1404
}

conf_ubuntu_1204() {
    conf_ubuntu_1404
}

DEPS_INSTALL_FUNC="install_${DISTRO_NAME_L}${DISTRO_VERSION_NO_DOTS}"
CONFIG_FUNC="conf_${DISTRO_NAME_L}${DISTRO_VERSION_NO_DOTS}"
POST_INSTALL_FUNC="post_install_${DISTRO_NAME_L}${DISTRO_VERSION_NO_DOTS}"

# Install dependencies
echo " * Running ${DEPS_INSTALL_FUNC}()"
$DEPS_INSTALL_FUNC
if [ $? -ne 0 ]; then
    echo " * Failed to run ${DEPS_INSTALL_FUNC}()!!!"
    exit 1
fi

# Configure basic stuff
$CONFIG_FUNC
if [ $? -ne 0 ]; then
    echo " * Failed to run ${CONFIG_FUNC}()!!!"
    exit 1
fi

if [ "$POST_INSTALL_FUNC" != "null" ]; then
    echo " * Running ${POST_INSTALL_FUNC}()"
    $POST_INSTALL_FUNC
    if [ $? -ne 0 ]; then
        echo " * Failed to run ${POST_INSTALL_FUNC}()!!!"
        exit 1
    fi
fi

# Done!
echo " * Exported disk!"
exit 0



