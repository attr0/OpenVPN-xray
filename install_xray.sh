#!/bin/sh

#reference https://github.com/XTLS/Xray-install/blob/main/install-release.sh


DAT_PATH=${DAT_PATH:-/usr/local/share/xray}
JSON_PATH=${JSON_PATH:-/usr/local/etc/xray}

# Gobal verbals
XRAY_IS_INSTALLED_BEFORE_RUNNING_SCRIPT=0

# Xray current version
CURRENT_VERSION=''

# Xray latest release version
RELEASE_LATEST=''

# Xray latest prerelease/release version
PRE_RELEASE_LATEST=''

# Xray version will be installed
INSTALL_VERSION=''

# install
INSTALL='0'

# install-geodata
INSTALL_GEODATA='0'

# remove
REMOVE='0'

# help
HELP='0'

# check
CHECK='0'

# --force
FORCE='0'

# --beta
BETA='0'

# --install-user ?
INSTALL_USER=''

# --without-geodata
NO_GEODATA='0'

# --without-logfiles
NO_LOGFILES='0'

# --no-update-service
N_UP_SERVICE='0'

# --reinstall
REINSTALL='0'

# --version ?
SPECIFIED_VERSION=''

# --local ?
LOCAL_FILE=''

# --proxy ?
PROXY=''

# --purge
PURGE='0'

curl() {
  $(type -P curl) -L -q --retry 5 --retry-delay 10 --retry-max-time 60 "$@"
}

systemd_cat_config() {
  if systemd-analyze --help | grep -qw 'cat-config'; then
    systemd-analyze --no-pager cat-config "$@"
    echo
  else
    echo "${aoi}~~~~~~~~~~~~~~~~"
    cat "$@" "$1".d/*
    echo "${aoi}~~~~~~~~~~~~~~~~"
    echo "${red}warning: ${green}The systemd version on the current operating system is too low."
    echo "${red}warning: ${green}Please consider to upgrade the systemd or the operating system.${reset}"
    echo
  fi
}

check_if_running_as_root() {
  # If you want to run as another user, please modify $EUID to be owned by this user
  if [[ "$EUID" -ne '0' ]]; then
    echo "error: You must run this script as root!"
    exit 1
  fi
}

identify_the_operating_system_and_architecture() {
  
    case "$(uname -m)" in
      'i386' | 'i686')
        MACHINE='32'
        ;;
      'amd64' | 'x86_64')
        MACHINE='64'
        ;;
      'armv5tel')
        MACHINE='arm32-v5'
        ;;
      'armv6l')
        MACHINE='arm32-v6'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
        ;;
      'armv7' | 'armv7l')
        MACHINE='arm32-v7a'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
        ;;
      'armv8' | 'aarch64')
        MACHINE='arm64-v8a'
        ;;
      'mips')
        MACHINE='mips32'
        ;;
      'mipsle')
        MACHINE='mips32le'
        ;;
      'mips64')
        MACHINE='mips64'
        ;;
      'mips64le')
        MACHINE='mips64le'
        ;;
      'ppc64')
        MACHINE='ppc64'
        ;;
      'ppc64le')
        MACHINE='ppc64le'
        ;;
      'riscv64')
        MACHINE='riscv64'
        ;;
      's390x')
        MACHINE='s390x'
        ;;
      *)
        echo "error: The architecture is not supported."
        exit 1
        ;;
    esac
    
    PACKAGE_MANAGEMENT_INSTALL='apk add --no-cache'
    PACKAGE_MANAGEMENT_REMOVE='apk del'
    package_provide_tput='ncurses'

}

## Demo function for processing parameters
judgment_parameters() {
  local local_install='0'
  local temp_version='0'
  while [[ "$#" -gt '0' ]]; do
    case "$1" in
      'install')
        INSTALL='1'
        ;;
      'install-geodata')
        INSTALL_GEODATA='1'
        ;;
      'remove')
        REMOVE='1'
        ;;
      'help')
        HELP='1'
        ;;
      'check')
        CHECK='1'
        ;;
      '--without-geodata')
        NO_GEODATA='1'
        ;;
      '--without-logfiles')
        NO_LOGFILES='1'
        ;;
      '--purge')
        PURGE='1'
        ;;
      '--version')
        if [[ -z "$2" ]]; then
          echo "error: Please specify the correct version."
          exit 1
        fi
        temp_version='1'
        SPECIFIED_VERSION="$2"
        shift
        ;;
      '-f' | '--force')
        FORCE='1'
        ;;
      '--beta')
        BETA='1'
        ;;
      '-l' | '--local')
        local_install='1'
        if [[ -z "$2" ]]; then
          echo "error: Please specify the correct local file."
          exit 1
        fi
        LOCAL_FILE="$2"
        shift
        ;;
      '-p' | '--proxy')
        if [[ -z "$2" ]]; then
          echo "error: Please specify the proxy server address."
          exit 1
        fi
        PROXY="$2"
        shift
        ;;
      '-u' | '--install-user')
        if [[ -z "$2" ]]; then
          echo "error: Please specify the install user.}"
          exit 1
        fi
        INSTALL_USER="$2"
        shift
        ;;
      '--reinstall')
        REINSTALL='1'
        ;;
      '--no-update-service')
        N_UP_SERVICE='1'
        ;;
      *)
        echo "$0: unknown option -- -"
        exit 1
        ;;
    esac
    shift
  done
  if ((INSTALL+INSTALL_GEODATA+HELP+CHECK+REMOVE==0)); then
    INSTALL='1'
  elif ((INSTALL+INSTALL_GEODATA+HELP+CHECK+REMOVE>1)); then
    echo 'You can only choose one action.'
    exit 1
  fi
  if [[ "$INSTALL" -eq '1' ]] && ((temp_version+local_install+REINSTALL+BETA>1)); then
    echo "--version,--reinstall,--beta and --local can't be used together."
    exit 1
  fi
}

check_install_user() {
  if [[ -z "$INSTALL_USER" ]]; then
    if [[ -f '/usr/local/bin/xray' ]]; then
      INSTALL_USER="$(grep '^[ '$'\t]*User[ '$'\t]*=' /etc/systemd/system/xray.service | tail -n 1 | awk -F = '{print $2}' | awk '{print $1}')"
      if [[ -z "$INSTALL_USER" ]]; then
        INSTALL_USER='root'
      fi
    else
      INSTALL_USER='nobody'
    fi
  fi
  if ! id $INSTALL_USER > /dev/null 2>&1; then
    echo "the user '$INSTALL_USER' is not effective"
    exit 1
  fi
  INSTALL_USER_UID="$(id -u $INSTALL_USER)"
  INSTALL_USER_GID="$(id -g $INSTALL_USER)"
}

install_software() {
  package_name="$1"
  file_to_detect="$2"
  type -P "$file_to_detect" > /dev/null 2>&1 && return
  if ${PACKAGE_MANAGEMENT_INSTALL} "$package_name"; then
    echo "info: $package_name is installed."
  else
    echo "error: Installation of $package_name failed, please check your network."
    exit 1
  fi
}

get_current_version() {
  # Get the CURRENT_VERSION
  if [[ -f '/usr/local/bin/xray' ]]; then
    CURRENT_VERSION="$(/usr/local/bin/xray -version | awk 'NR==1 {print $2}')"
    CURRENT_VERSION="v${CURRENT_VERSION#v}"
  else
    CURRENT_VERSION=""
  fi
}

get_latest_version() {
  # Get Xray latest release version number
  local tmp_file
  tmp_file="$(mktemp)"
  if ! curl -x "${PROXY}" -sS -H "Accept: application/vnd.github.v3+json" -o "$tmp_file" 'https://api.github.com/repos/XTLS/Xray-core/releases/latest'; then
    "rm" "$tmp_file"
    echo 'error: Failed to get release list, please check your network.'
    exit 1
  fi
  RELEASE_LATEST="$(sed 'y/,/\n/' "$tmp_file" | grep 'tag_name' | awk -F '"' '{print $4}')"
  if [[ -z "$RELEASE_LATEST" ]]; then
    if grep -q "API rate limit exceeded" "$tmp_file"; then
      echo "error: github API rate limit exceeded"
    else
      echo "error: Failed to get the latest release version."
      echo "Welcome bug report:https://github.com/XTLS/Xray-install/issues"
    fi
    "rm" "$tmp_file"
    exit 1
  fi
  "rm" "$tmp_file"
  RELEASE_LATEST="v${RELEASE_LATEST#v}"
  if ! curl -x "${PROXY}" -sS -H "Accept: application/vnd.github.v3+json" -o "$tmp_file" 'https://api.github.com/repos/XTLS/Xray-core/releases'; then
    "rm" "$tmp_file"
    echo 'error: Failed to get release list, please check your network.'
    exit 1
  fi
  local releases_list
  releases_list=($(sed 'y/,/\n/' "$tmp_file" | grep 'tag_name' | awk -F '"' '{print $4}'))
  if [[ "${#releases_list[@]}" -eq '0' ]]; then
    if grep -q "API rate limit exceeded" "$tmp_file"; then
      echo "error: github API rate limit exceeded"
    else
      echo "error: Failed to get the latest release version."
      echo "Welcome bug report:https://github.com/XTLS/Xray-install/issues"
    fi
    "rm" "$tmp_file"
    exit 1
  fi
  local i
  for i in ${!releases_list[@]}
  do
    releases_list[$i]="v${releases_list[$i]#v}"
    grep -q "https://github.com/XTLS/Xray-core/releases/download/${releases_list[$i]}/Xray-linux-$MACHINE.zip" "$tmp_file" && break
  done
  "rm" "$tmp_file"
  PRE_RELEASE_LATEST="${releases_list[$i]}"
}

version_gt() {
  # compare two version
  # 0: $1 >  $2
  # 1: $1 <= $2

  if [[ "$1" != "$2" ]]; then
    local temp_1_version_number="${1#v}"
    local temp_1_major_version_number="${temp_1_version_number%%.*}"
    local temp_1_minor_version_number
    temp_1_minor_version_number="$(echo "$temp_1_version_number" | awk -F '.' '{print $2}')"
    local temp_1_minimunm_version_number="${temp_1_version_number##*.}"
    # shellcheck disable=SC2001
    local temp_2_version_number="${2#v}"
    local temp_2_major_version_number="${temp_2_version_number%%.*}"
    local temp_2_minor_version_number
    temp_2_minor_version_number="$(echo "$temp_2_version_number" | awk -F '.' '{print $2}')"
    local temp_2_minimunm_version_number="${temp_2_version_number##*.}"
    if [[ "$temp_1_major_version_number" -gt "$temp_2_major_version_number" ]]; then
      return 0
    elif [[ "$temp_1_major_version_number" -eq "$temp_2_major_version_number" ]]; then
      if [[ "$temp_1_minor_version_number" -gt "$temp_2_minor_version_number" ]]; then
        return 0
      elif [[ "$temp_1_minor_version_number" -eq "$temp_2_minor_version_number" ]]; then
        if [[ "$temp_1_minimunm_version_number" -gt "$temp_2_minimunm_version_number" ]]; then
          return 0
        else
          return 1
        fi
      else
        return 1
      fi
    else
      return 1
    fi
  elif [[ "$1" == "$2" ]]; then
    return 1
  fi
}

download_xray() {
  DOWNLOAD_LINK="https://github.com/XTLS/Xray-core/releases/download/$INSTALL_VERSION/Xray-linux-$MACHINE.zip"
  echo "Downloading Xray archive: $DOWNLOAD_LINK"
  if ! curl -x "${PROXY}" -R -H 'Cache-Control: no-cache' -o "$ZIP_FILE" "$DOWNLOAD_LINK"; then
    echo 'error: Download failed! Please check your network or try again.'
    return 1
  fi
  return 0
  echo "Downloading verification file for Xray archive: $DOWNLOAD_LINK.dgst"
  if ! curl -x "${PROXY}" -sSR -H 'Cache-Control: no-cache' -o "$ZIP_FILE.dgst" "$DOWNLOAD_LINK.dgst"; then
    echo 'error: Download failed! Please check your network or try again.'
    return 1
  fi
  if [[ "$(cat "$ZIP_FILE".dgst)" == 'Not Found' ]]; then
    echo 'error: This version does not support verification. Please replace with another version.'
    return 1
  fi

  # Verification of Xray archive
  for LISTSUM in 'md5' 'sha1' 'sha256' 'sha512'; do
    SUM="$(${LISTSUM}sum "$ZIP_FILE" | sed 's/ .*//')"
    CHECKSUM="$(grep ${LISTSUM^^} "$ZIP_FILE".dgst | grep "$SUM" -o -a | uniq)"
    if [[ "$SUM" != "$CHECKSUM" ]]; then
      echo 'error: Check failed! Please check your network or try again.'
      return 1
    fi
  done
}

decompression() {
  if ! unzip -q "$1" -d "$TMP_DIRECTORY"; then
    echo 'error: Xray decompression failed.'
    "rm" -r "$TMP_DIRECTORY"
    echo "removed: $TMP_DIRECTORY"
    exit 1
  fi
  echo "info: Extract the Xray package to $TMP_DIRECTORY and prepare it for installation."
}

install_file() {
  NAME="$1"
  if [[ "$NAME" == 'xray' ]]; then
    install -m 755 "${TMP_DIRECTORY}/$NAME" "/usr/local/bin/$NAME"
  elif [[ "$NAME" == 'geoip.dat' ]] || [[ "$NAME" == 'geosite.dat' ]]; then
    install -m 644 "${TMP_DIRECTORY}/$NAME" "${DAT_PATH}/$NAME"
  fi
}

install_xray() {
  # Install Xray binary to /usr/local/bin/ and $DAT_PATH
  install_file xray
  # If the file exists, geoip.dat and geosite.dat will not be installed or updated
  if [[ "$NO_GEODATA" -eq '0' ]] && [[ ! -f "${DAT_PATH}/.undat" ]]; then
    install -d "$DAT_PATH"
    install_file geoip.dat
    install_file geosite.dat
    GEODATA='1'
  fi

  # Install Xray configuration file to $JSON_PATH
  # shellcheck disable=SC2153
  if [[ -z "$JSONS_PATH" ]] && [[ ! -d "$JSON_PATH" ]]; then
    install -d "$JSON_PATH"
    echo "{}" > "${JSON_PATH}/config.json"
    CONFIG_NEW='1'
  fi

  # Install Xray configuration file to $JSONS_PATH
  if [[ -n "$JSONS_PATH" ]] && [[ ! -d "$JSONS_PATH" ]]; then
    install -d "$JSONS_PATH"
    for BASE in 00_log 01_api 02_dns 03_routing 04_policy 05_inbounds 06_outbounds 07_transport 08_stats 09_reverse; do
      echo '{}' > "${JSONS_PATH}/${BASE}.json"
    done
    CONFDIR='1'
  fi

  # Used to store Xray log files
  if [[ "$NO_LOGFILES" -eq '0' ]]; then
    if [[ ! -d '/var/log/xray/' ]]; then
      install -d -m 700 -o "$INSTALL_USER_UID" -g "$INSTALL_USER_GID" /var/log/xray/
      install -m 600 -o "$INSTALL_USER_UID" -g "$INSTALL_USER_GID" /dev/null /var/log/xray/access.log
      install -m 600 -o "$INSTALL_USER_UID" -g "$INSTALL_USER_GID" /dev/null /var/log/xray/error.log
      LOG='1'
    else
      chown -R "$INSTALL_USER_UID:$INSTALL_USER_GID" /var/log/xray/
    fi
  fi
}

install_startup_service_file() {
  true
}

start_xray() {
  true
}

stop_xray() {
  true
}

install_geodata() {
  download_geodata() {
    if ! curl -x "${PROXY}" -R -H 'Cache-Control: no-cache' -o "${dir_tmp}/${2}" "${1}"; then
      echo 'error: Download failed! Please check your network or try again.'
      exit 1
    fi
    if ! curl -x "${PROXY}" -R -H 'Cache-Control: no-cache' -o "${dir_tmp}/${2}.sha256sum" "${1}.sha256sum"; then
      echo 'error: Download failed! Please check your network or try again.'
      exit 1
    fi
  }
  local download_link_geoip="https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"
  local download_link_geosite="https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
  local file_ip='geoip.dat'
  local file_dlc='dlc.dat'
  local file_site='geosite.dat'
  local dir_tmp
  dir_tmp="$(mktemp -d)"
  [[ "$XRAY_IS_INSTALLED_BEFORE_RUNNING_SCRIPT" -eq '0' ]] && echo "warning: Xray was not installed"
  download_geodata $download_link_geoip $file_ip
  download_geodata $download_link_geosite $file_dlc
  cd "${dir_tmp}" || exit
  for i in "${dir_tmp}"/*.sha256sum; do
    if ! sha256sum -c "${i}"; then
      echo 'error: Check failed! Please check your network or try again.'
      exit 1
    fi
  done
  cd - > /dev/null
  install -d "$DAT_PATH"
  install -m 644 "${dir_tmp}"/${file_dlc} "${DAT_PATH}"/${file_site}
  install -m 644 "${dir_tmp}"/${file_ip} "${DAT_PATH}"/${file_ip}
  rm -r "${dir_tmp}"
  exit 0
}

check_update() {
  if [[ "$XRAY_IS_INSTALLED_BEFORE_RUNNING_SCRIPT" -eq '1' ]]; then
    get_current_version
    echo "info: The current version of Xray is $CURRENT_VERSION ."
  else
    echo 'warning: Xray is not installed.'
  fi
  get_latest_version
  echo "info: The latest release version of Xray is $RELEASE_LATEST ."
  echo "info: The latest pre-release/release version of Xray is $PRE_RELEASE_LATEST ."
  exit 0
}

remove_xray() {
  true
}

# Explanation of parameters in the script
show_help() {
  echo "usage: $0 ACTION [OPTION]..."
  echo
  echo 'ACTION:'
  echo '  install                   Install/Update Xray'
  echo '  install-geodata           Install/Update geoip.dat and geosite.dat only'
  echo '  remove                    Remove Xray'
  echo '  help                      Show help'
  echo '  check                     Check if Xray can be updated'
  echo 'If no action is specified, then install will be selected'
  echo
  echo 'OPTION:'
  echo '  install:'
  echo '    --version                 Install the specified version of Xray, e.g., --version v1.0.0'
  echo '    -f, --force               Force install even though the versions are same'
  echo '    --beta                    Install the pre-release version if it is exist'
  echo '    -l, --local               Install Xray from a local file'
  echo '    -p, --proxy               Download through a proxy server, e.g., -p http://127.0.0.1:8118 or -p socks5://127.0.0.1:1080'
  echo '    -u, --install-user        Install Xray in specified user, e.g, -u root'
  echo '    --reinstall               Reinstall current Xray version'
  echo "    --no-update-service       Don't change service files if they are exist"
  echo "    --without-geodata         Don't install/update geoip.dat and geosite.dat"
  echo "    --without-logfiles        Don't install /var/log/xray"
  echo '  install-geodata:'
  echo '    -p, --proxy               Download through a proxy server'
  echo '  remove:'
  echo '    --purge                   Remove all the Xray files, include logs, configs, etc'
  echo '  check:'
  echo '    -p, --proxy               Check new version through a proxy server'
  exit 0
}

main() {
  check_if_running_as_root
  identify_the_operating_system_and_architecture
  judgment_parameters "$@"

  install_software "$package_provide_tput" 'tput'
  red=$(tput setaf 1)
  green=$(tput setaf 2)
  aoi=$(tput setaf 6)
  reset=$(tput sgr0)

  # Parameter information
  [[ "$HELP" -eq '1' ]] && show_help
  [[ "$CHECK" -eq '1' ]] && check_update
  [[ "$REMOVE" -eq '1' ]] && remove_xray
  [[ "$INSTALL_GEODATA" -eq '1' ]] && install_geodata

  # Check if the user is effective
  check_install_user

  # Two very important variables
  TMP_DIRECTORY="$(mktemp -d)"
  ZIP_FILE="${TMP_DIRECTORY}/Xray-linux-$MACHINE.zip"

  # Install Xray from a local file, but still need to make sure the network is available
  if [[ -n "$LOCAL_FILE" ]]; then
    echo 'warn: Install Xray from a local file, but still need to make sure the network is available.'
    echo -n 'warn: Please make sure the file is valid because we cannot confirm it. (Press any key) ...'
    read -r
    install_software 'unzip' 'unzip'
    decompression "$LOCAL_FILE"
  else
    get_current_version
    if [[ "$REINSTALL" -eq '1' ]]; then
      if [[ -z "$CURRENT_VERSION" ]]; then
        echo "error: Xray is not installed"
        exit 1
      fi
      INSTALL_VERSION="$CURRENT_VERSION"
      echo "info: Reinstalling Xray $CURRENT_VERSION"
    elif [[ -n "$SPECIFIED_VERSION" ]]; then
      SPECIFIED_VERSION="v${SPECIFIED_VERSION#v}"
      if [[ "$CURRENT_VERSION" == "$SPECIFIED_VERSION" ]] && [[ "$FORCE" -eq '0' ]]; then
        echo "info: The current version is same as the specified version. The version is $CURRENT_VERSION ."
        exit 0
      fi
      INSTALL_VERSION="$SPECIFIED_VERSION"
      echo "info: Installing specified Xray version $INSTALL_VERSION for $(uname -m)"
    else
      install_software 'curl' 'curl'
      get_latest_version
      if [[ "$BETA" -eq '0' ]]; then
        INSTALL_VERSION="$RELEASE_LATEST"
      else
        INSTALL_VERSION="$PRE_RELEASE_LATEST"
      fi
      if ! version_gt "$INSTALL_VERSION" "$CURRENT_VERSION" && [[ "$FORCE" -eq '0' ]]; then
        echo "info: No new version. The current version of Xray is $CURRENT_VERSION ."
        exit 0
      fi
      echo "info: Installing Xray $INSTALL_VERSION for $(uname -m)"
    fi
    install_software 'curl' 'curl'
    install_software 'unzip' 'unzip'
    if ! download_xray; then
      "rm" -r "$TMP_DIRECTORY"
      echo "removed: $TMP_DIRECTORY"
      exit 1
    fi
    decompression "$ZIP_FILE"
  fi

  install_xray
  ([[ "$N_UP_SERVICE" -eq '1' ]] && [[ -f '/etc/systemd/system/xray.service' ]]) || install_startup_service_file
  echo 'installed: /usr/local/bin/xray'
  # If the file exists, the content output of installing or updating geoip.dat and geosite.dat will not be displayed
  if [[ "$GEODATA" -eq '1' ]]; then
    echo "installed: ${DAT_PATH}/geoip.dat"
    echo "installed: ${DAT_PATH}/geosite.dat"
  fi
  if [[ "$CONFIG_NEW" -eq '1' ]]; then
    echo "installed: ${JSON_PATH}/config.json"
  fi
  if [[ "$CONFDIR" -eq '1' ]]; then
    echo "installed: ${JSON_PATH}/00_log.json"
    echo "installed: ${JSON_PATH}/01_api.json"
    echo "installed: ${JSON_PATH}/02_dns.json"
    echo "installed: ${JSON_PATH}/03_routing.json"
    echo "installed: ${JSON_PATH}/04_policy.json"
    echo "installed: ${JSON_PATH}/05_inbounds.json"
    echo "installed: ${JSON_PATH}/06_outbounds.json"
    echo "installed: ${JSON_PATH}/07_transport.json"
    echo "installed: ${JSON_PATH}/08_stats.json"
    echo "installed: ${JSON_PATH}/09_reverse.json"
  fi
  if [[ "$LOG" -eq '1' ]]; then
    echo 'installed: /var/log/xray/'
    echo 'installed: /var/log/xray/access.log'
    echo 'installed: /var/log/xray/error.log'
  fi
  "rm" -r "$TMP_DIRECTORY"
  echo "removed: $TMP_DIRECTORY"
  get_current_version
  echo "info: Xray $CURRENT_VERSION is installed."
}

main "$@"
