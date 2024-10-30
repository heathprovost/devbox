#!/usr/bin/env bash

{ # this ensures that the entire script is downloaded #

#
# set bash flags
# -e : exit immediately if any command exits with a non-zero status
# -u : Treat unset variables and parameters as an error when performing parameters expansion
# -o pipefail - returns a non-zero exit code if any command in the pipeline fails, not just the last one
#
set -euo pipefail

#=============================================================================#
# Utility Functions
#=============================================================================#

#
# report an error and exit
#
# @param string $1 - The error message to display. Defaults to "An unknown error occurred."
# @param integer $2 - The exit code to set. Defaults to 1
#
function err() {
  print_as "error" "${1:-An unknown error occurred.}"
  exit ${2:-1}
}

#
# ensures that script itself is *not* run using the sudo command but that there *is* a sudo session that can be used when needed
#
# @globals - reads SUDO_USER
#
function resolve_sudo() {
  local os="$(uname -o 2> /dev/null || true)"
  if [[ ! -x "/usr/bin/sudo" ]]
  then
    err "This script requires \"sudo\" to be installed."
  fi
  if [[ -n "${SUDO_USER-}" ]]
  then
    # user run script using sudo, we dont support that.
    err "This script must be run **without** using \"sudo\". You will be prompted if needed."
  else
    # ensure we have a directory to work in
    DEVBOX_DIR=~/.devbox
    if [[ ! -d "$DEVBOX_DIR" ]]
    then
      mkdir -p "$DEVBOX_DIR" || err "Could not create required directory \"$DEVBOX_DIR\". Cannot continue."
    fi
    if [[ "$os" == "Darwin" ]]
    then
      if [[ ! -f "$DEVBOX_DIR/ask-sudo.sh" ]]
      then
        printf "#!/bin/bash\npw=\"\$(osascript -e 'Tell application \"System Events\" to display dialog \"Enter Sudo Password:\" default answer \"\" with hidden answer' -e 'text returned of result' 2>/dev/null)\" && echo \"\$pw\"" > "$DEVBOX_DIR/ask-sudo.sh"
        chmod +x "$DEVBOX_DIR/ask-sudo.sh"
        export SUDO_ASKPASS="$DEVBOX_DIR/ask-sudo.sh"
      fi
    else
      # validate sudo session (prompting for password if necessary)
      local sudo_session_ok=0
      sudo -n true 2> /dev/null || sudo_session_ok=$?
      if [[ "$sudo_session_ok" -ne 0 ]]
      then
        sudo -v
        if [[ $? -ne 0 ]]
        then
          err "Something went wrong when using \"sudo\" to elevate the current script."
        fi
      fi
    fi
  fi
}

#
# prints a message to the console. Each type is display using a custom glyph and/or color
# single quoted substrings are highlighted in blue when detected
#
# @param string $1 - the message type, one of "success", "skipped", "failed", "error", "important", "prompt", "info"
# @param string $2 - the message to print
#
function print_as() {
  local red='\033[0;31m'
  local green='\033[0;32m'
  local yellow='\033[0;33m'
  local blue='\033[0;34m'
  local cyan='\033[0;36m'
  local default='\033[0;39m'
  local reset='\033[0m'
  local success_glyph="${green}✓${reset} "
  local success_color="$default"
  local skipped_glyph="${blue}✗${reset} "
  local skipped_color="$default"
  local failed_glyph="${red}✗${reset} "
  local failed_color="$default"
  local error_glyph="${red}✗${reset} "
  local error_color="$red"
  local important_glyph=""
  local important_color="$yellow"
  local prompt_glyph=""
  local prompt_color="$cyan"
  local info_glyph=""
  local info_color="$cyan"
  local nl="\n"

  # store $1 as the msgtype
  local msgtype=$1
  local glyph
  local color

  # use eval to assign reference vars
  eval "glyph=\${${msgtype}_glyph}"
  eval "color=\${${msgtype}_color}"

  # use sed to highlight quoted substrings in $2 and store as msg
  local msg=$(echo -n -e "$(echo -e -n "$2" | sed -e "s/'\([^'\\\"]*\)'/\\${blue}\1\\${reset}\\${color}/g")")

  # for prompts dont emit a linebreak
  if [ "$msgtype" = "prompt" ]; then
    nl=""
  fi

  printf "${glyph}${color}${msg}${reset}${nl}"
}

#
# log to the log file
#
# @param string(s) $@ - the message(s) to log (expands to all arguments)
#
function log() {
  printf "$@\n" >> "$DEVBOX_DIR/devbox.log" 2>&1
}

#
# return its arguments as a single string with leading and trailing space trimmed
#
# @param string(s) $*- The string(s) to trim. Arguments are merged into a single string
#
function trim() {
  local var="$*"
  # remove leading whitespace characters
  var="${var#"${var%%[![:space:]]*}"}"
  # remove trailing whitespace characters
  var="${var%"${var##*[![:space:]]}"}"
  printf '%s' "$var"
}

#
# Run the installer command passed as 1st argument and shows the spinner until this is done
#
# @param string $1 - the installer command to run
# @param string $2 - the title to show next the spinner
# @globals - reads DEVBOX_DIR, writes DEVBOX_ENV_UPDATED, DEVBOX_INSTALLER_FAILED
#
function install() {
  command="$1"
  shift
  install_$command $@ >> "$DEVBOX_DIR/devbox.log" 2>&1 &
  local pid=$!
  log "===================================\n$command: pid $pid\n===================================\n"
  local delay=0.05

  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

  # Hide the cursor, it looks ugly :D
  tput civis
  local index=0
  local framesCount=${#frames[@]}

  while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
    printf "\033[0;34m${frames[$index]}\033[0m Installing $command"

    let index=index+1
    if [ "$index" -ge "$framesCount" ]; then
      index=0
    fi

    printf "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b"
    sleep $delay
  done

  #
  # Wait the command to be finished, this is needed to capture its exit status
  #
  local exit_code=0
  wait $pid || exit_code=$?

  log "\nInstall function completed with exit code: $exit_code\n"

  if [ $exit_code -eq 0 ] || [ $exit_code -eq 90 ]; then
    print_as "success" "Installing $command"
    if [ $exit_code -eq 90 ]; then
      # 90 means environment will need to be reloaded, so this still successful run. Just set flag to output correct message later
      DEVBOX_ENV_UPDATED="true"
    fi
  elif [ $exit_code -eq 65 ]; then
    print_as "skipped" "Installing $command ... skipped (upgrade not supported, manual removal required)"
  elif [ $exit_code -eq 66 ]; then
    print_as "skipped" "Installing $command ... skipped (existing installation is up-to-date)"
  elif [ $exit_code -eq 67 ]; then
    print_as "skipped" "Installing $command ... skipped (superuser required: run as root or use sudo)"
  else
    DEVBOX_INSTALLER_FAILED="true"
    print_as "failed" "Installing $command"
  fi

  # Restore the cursor
  tput cnorm
}

#
# Validates that all commands used by functions in this script are available
#
function validate_commands() {
  local rc=0
  local commands="printf sed uname ps awk grep sleep tput cut mkdir which"
  for command in $commands; do
    rc=0
    command -v "$command" >/dev/null || rc=$?
    if [[ $rc -ne 0 ]]
    then
      err "validate_commands() failed. Command \"$command\" not found."
    fi
  done
}

#
# ensure we are executing on a supported operating system
# Currently supported: Ubuntu 24.x or higher and MacOS 15.x or higher
#
# @globals - writes DEVBOX_OS_NAME, DEVBOX_OS_VERSION, DEVBOX_OS_MAJOR_VERSION, DEVBOX_OS_ARCH, DEVBOX_OS_KERNEL, DEVBOX_OS_MACHINE
#
function validate_os() {
  DEVBOX_OS_NAME="$(lsb_release -si 2> /dev/null || sw_vers -productName || true)"
  DEVBOX_OS_VERSION="$(lsb_release -sr 2> /dev/null || sw_vers -productVersion || true)"
  DEVBOX_OS_MAJOR_VERSION="$(cut -d '.' -f 1 <<< "$DEVBOX_OS_VERSION")"
  DEVBOX_OS_ARCH="$(uname -m)"
  if [[ "$DEVBOX_OS_NAME" == "macOS" ]]
  then
    # uppercase macOS for consistency
    DEVBOX_OS_NAME="MacOS"
  fi
  if [[ "$DEVBOX_OS_ARCH" == "arm64" ]]
  then
    # some systems report arm64 instead of aarch64. Normalize to aarch64
    DEVBOX_OS_ARCH="aarch64"
  fi
  DEVBOX_OS_MACHINE="$DEVBOX_OS_ARCH"
  if [[ -d "/run/WSL" ]]
  then
    DEVBOX_OS_MACHINE="$DEVBOX_OS_MACHINE/WSL2"
  elif [[ -d "/opt/orbstack-guest" ]]
  then
    DEVBOX_OS_MACHINE="$DEVBOX_OS_MACHINE/OrbStack"
  elif [[ -n "${DEVBOX_CONTAINERIZED:-}" ]]
  then
    DEVBOX_OS_MACHINE="$DEVBOX_OS_MACHINE/Docker"
  fi
  DEVBOX_OS="$DEVBOX_OS_NAME $DEVBOX_OS_MAJOR_VERSION"
  if [[ "$DEVBOX_OS_NAME" == "Ubuntu" ]] && [[ $DEVBOX_OS_MAJOR_VERSION -ge 24 ]]
  then
    DEVBOX_OS_KERNEL="Linux"
  elif [[ "$DEVBOX_OS_NAME" == "MacOS" ]] && [[ $DEVBOX_OS_MAJOR_VERSION -ge 15 ]]
  then
    DEVBOX_OS_KERNEL="Darwin"
  else
    err "validate_os() failed. \"$DEVBOX_OS_NAME $DEVBOX_OS_VERSION ($DEVBOX_OS_MACHINE)\" is not a supported operating system."
  fi
}

#
# validate shell is supported and the users profile is already configured
#
# @globals - reads SHELL, HOME, writes DEVBOX_PROFILE_FILE
#
function validate_shell() {
  # validate the users shell is either bash or zsh and that they already have a valid profile
  if [[ "${SHELL#*bash}" != "$SHELL" ]]
  then
    if [[ -f "$HOME/.bashrc" ]]
    then
      DEVBOX_PROFILE_FILE="$HOME/.bashrc"
    elif [[ -f "$HOME/.bash_profile" ]]
    then
      DEVBOX_PROFILE_FILE="$HOME/.bash_profile"
    else
      err "validate_shell() failed. Can not find a valid bash profile. Ensure either ~/.bashrc or ~/.bash_profile already exist"
    fi
  elif [[ "${SHELL#*zsh}" != "$SHELL" ]]
  then
    if [[ -f "$HOME/.zshrc" ]]
    then
      DEVBOX_PROFILE_FILE="$HOME/.zshrc"
    elif [[ -f "$HOME/.zprofile" ]]
    then
      DEVBOX_PROFILE_FILE="$HOME/.zprofile"
    else
      err "validate_shell() failed. Can not find a valid zsh profile. Ensure either ~/.zshrc or ~/.zprofile already exist"
    fi
  else
    err "validate_shell() failed. The current shell \"$SHELL\" is not supported."
  fi
}

#
# prepare the log file. We want a new log file for each run
#
# @globals - reads DEVBOX_DIR, writes DEVBOX_LOGFILE
#
function prepare_log() {
  # delete log if it exists.
  if [[ -f "$DEVBOX_DIR/devbox.log" ]]
  then
    rm -f "$DEVBOX_DIR/devbox.log"
  fi

  # create log file and make current user owner if sudo was used
  touch "$DEVBOX_DIR/devbox.log"
}

#
# Collects configuration options, either by prompting user or reading them from .devboxrc file
#
# @globals - reads and writes DEVBOX_GIT_USER_NAME, DEVBOX_GIT_USER_EMAIL, GIT_HUB_PKG_TOKEN
#
function configure() {
  local rc_file="$HOME/.devboxrc"
  local key
  local value
  local name
  local email
  local token
  local output

  # load configuration from .devboxrc file if it exists
  while IFS='=' read -r key value; do
    key="${key// /}"  # Remove spaces from key
    value="${value//\"/}"  # Remove quotes from value
    if [[ "$key" == "name" ]]
    then
      name="$value"
    elif [[ "$key" == "email" ]]
    then
      email="$value"
    elif [[ "$key" == "token" ]]
    then
      token="$value"
    fi
  done < <(awk -F'=' '/^[^;#]/ {gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $2); print $1 "=" $2}' "$rc_file")

  # if .devboxrc was sourced and everything is already set skip prompts
  if [[ -n "${name:-}" ]] && [[ -n "${email:-}" ]]
  then
    print_as "info" "Using existing \"~/.devboxrc\" file for configuration."
    printf "\n"
  else
    print_as "info" "Responses will be saved in \"~/.devboxrc\" for future use."
    printf "\n"
    if [[ -z "${name:-}" ]]
    then
      print_as "prompt" "Full name: "
      read name
      DEVBOX_GIT_USER_NAME=$(trim $name)
    fi
    if [[ -z "${email:-}" ]]
    then
      print_as "prompt" "Email address: "
      read email
      DEVBOX_GIT_USER_EMAIL=$(trim $email)
    fi
    if [[ -z "${token:-}" ]] && [[ -z "${GIT_HUB_PKG_TOKEN:-}" ]] # if token is already set in the environment, skip the prompt
    then
      print_as "prompt" "Github token: "
      read token
      GIT_HUB_PKG_TOKEN=$(trim $token)
    fi
    printf "\n"

    output="name = $name\nemail = $email\n"

    # if token was set, add it to the output, otherwise it was already in the environment
    if [[ -n "${token:-}" ]]
    then
      output="${output}token = $token\n"
    fi

    # save to .devboxrc for future use
    printf "$output" > "$HOME/.devboxrc"
  fi
}

#
# Runs all required validations before executing installation scripts
#
function devbox_init() {
  validate_commands
  validate_shell
  validate_os
  prepare_log
  configure
}

#
# Cleanup variables and environment
# Note: there is no safe way to get the list of functions defined in a particular bash script, so we have to list them manually
#
function cleanup() {
  local utils="err resolve_suo print_as log trim install validate_commands validate_os validate_shell prepare_log configure devbox_init cleanup completion_report setup"
  local installers="install_common-packages install_git install_git-config install_dotnet-sdk install_java-jdk install_aws-cli install_fnm install_node install_nawsso"
  unset "${!DEVBOX_@}" # unset all variables starting with DEVBOX_
  unset -f $utils $installers # unset all functions defined in this script
}

#
# Print messages upon completion
#
# @globals - reads DEVBOX_DIR, DEVBOX_INSTALLER_FAILED, DEVBOX_ENV_UPDATED
#
function completion_report() {
  if [[ "${DEVBOX_INSTALLER_FAILED:-false}" == "true" ]]
  then
    print_as "failed" "Done!"
    printf "\n"
    print_as "important" "An error occured. Review \"$DEVBOX_DIR/devbox.log\" for more information."
  fi
  print_as "success" "Done!"
  printf "\n"
  if [[ "${DEVBOX_ENV_UPDATED:-false}" == "true" ]]
  then
    print_as "important" "Environment was updated. Reload your current shell before proceeding."
  fi
}

#=============================================================================#
# Installers
#=============================================================================#

#
# Install required OS packages. This installer script uses sudo
#
# @param string $1 - the name of the OS (currently either Ubuntu or MacOS)
#
function install_common-packages() {
  local os="$1"
  if [[ "$os" == "Ubuntu" ]]
  then
    # Use apt-get to install os packages
    # list of base packages to install
    local base_pkgs="curl wget zip unzip procps file build-essential make gcc g++ python3-minimal"
    # list of packages that are required to meet specific dependencies
    local cypress_deps="libgtk2.0-0t64 libgtk-3-0t64 libgbm-dev libnotify-dev libnss3 libxss1 libasound2t64 libxtst6 xauth xvfb"
    local meteor_deps="libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev"
    # update and upgrade, then install dependencies, then cleanup
    sudo apt-get -y update
    sudo apt-get -y upgrade
    sudo apt-get -y install ${base_pkgs} ${cypress_deps} ${meteor_deps}
    sudo apt-get -y clean
  elif [[ "$os" == "MacOS" ]]
  then
    # Use homebrew to install os packages
    local brew_bin="$(which brew 2> /dev/null || true)"
    # list of base packages to install
    local base_pkgs="gcc python3"
    # list of packages that are required to meet specific dependencies
    local cypress_deps=""
    local meteor_deps="pkg-config cairo pango libpng jpeg giflib librsvg pixman python-setuptools"
    if [[ -n "${brew_bin:-}" ]]
    then
      brew update
      brew doctor
    else
      tmpdir=$(mktemp -d 2> /dev/null || mktemp -d -t 'devbox-homebrew')
      log "Using temp directory '$tmpdir'"
      pushd $tmpdir > /dev/null
      curl -L https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o install.sh
      ./install.sh
      popd > /dev/null
      rm -rf $tmpdir
    fi
    # now use homebrew to install base packages
    brew install ${base_pkgs} ${cypress_deps} ${meteor_deps}
  else
    err "Unknown operating system \"$os\"."
  fi
}

#
# Installs the latest version of git available at time of install, or updates current version if needed.
#
# @param string $1 - the name of the OS (currently either Ubuntu or MacOS)
#
function install_git() {
  local os="$1"

  if [[ "$os" == "Ubuntu" ]]
  then
    sudo apt-get -y install git
  elif [[ "$os" == "MacOS" ]]
  then
    brew install git
    brew install --cask git-credential-manager
  else
    err "Unknown operating system \"$os\"."
  fi
}

#
# Configure existing git install
#
# @globals - reads DEVBOX_GIT_USER_NAME and DEVBOX_GIT_USER_EMAIL
#
function install_git-config() {
  local credential_helper="$(which git-credential-manager 2> /dev/null || true)"
  local i

  # if we did not find the GCM executable we might be on WSL2
  if [[ -z "${credential_helper:-}" ]] && [[ -d "/run/WSL" ]]
  then
    # we are in a wsl2 vm on windows so configure to call the windows GCM binary installed in the default location
    credential_helper="/mnt/c/Program\ Files/git/mingw64/bin/git-credential-manager.exe"
    log "\"git-credential-manager\" was not found but WSL2 detected, setting \"credential.helper\" to \"/mnt/c/Program\ Files/git/mingw64/bin/git-credential-manager.exe\"."
  fi

  # if it is still undefined log it and return error code
  if [[ -z "${credential_helper:-}" ]]
  then
    log "testing \"${credential_helper:-}\""
    log "\"git-credential-manager\" was expected to be installed but was not found. Cannot continue."
    return 1
  fi

  declare -a keys=( user.name user.email push.default core.autocrlf core.eol init.defaultbranch credential.helper )
  declare -a values=( "${DEVBOX_GIT_USER_NAME:-}" "${DEVBOX_GIT_USER_EMAIL:-}" simple false lf main "$credential_helper" )
  local length=${#keys[@]}

  # populate current with the current values read from git config
  for (( i=0; i<${length}; i++ ))
  do
    if [[ "$(git config --global "${keys[$i]}" || true)" != "${values[$i]}" ]]
    then
      git config --global --replace-all "${keys[$i]}" "${values[$i]}"
      log "git config setting '${keys[$i]}' was updated to '${values[$i]}'."
    else
      log "git config setting '${keys[$i]}' is already set to '${values[$i]}', skipping."
    fi
  done
}

#
# Installs dotnet sdk 8, or updates to latest revision if already installed
#
# @param string $1 - the name of the OS (currently either Ubuntu or MacOS)
#
function install_dotnet-sdk() {
  local os="$1"

  if [[ "$os" == "Ubuntu" ]]
  then
    sudo apt-get -y install dotnet-sdk-8.0
  elif [[ "$os" == "MacOS" ]]
  then
    local taps="$(brew tap 2> /dev/null || true)"
    if [[ $(echo "${taps:-}" | grep -q "isen-ng/dotnet-sdk-versions") -eq 0 ]]
    then
      brew tap isen-ng/dotnet-sdk-versions
    fi
    brew install --cask dotnet-sdk8-0-100
  else
    err "Unknown operating system \"$os\"."
  fi
}

#
# Installs openjdk@11, or updates to latest revision if already installed
#
# @param string $1 - the name of the OS (currently either Ubuntu or MacOS)
#
function install_java-jdk() {
  local os="$1"

  if [[ "$os" == "Ubuntu" ]]
  then
    sudo apt-get -y install openjdk-11-jdk-headless
  elif [[ "$os" == "MacOS" ]]
  then
    brew install openjdk@11
  else
    err "Unknown operating system \"$os\"."
  fi
}

#
# Installs aws command line interface v2
#
# @param string $1 - the kernel type of the OS (either Linux or Darwin)
# @param string $2 - the architecture of the machine (either x86_64 or aarch64)
#
function install_aws-cli() {
  local kernel="$1"
  local arch="$2"
  local aws_bin="$(which aws 2> /dev/null || true)"
  local tmpdir

  if [[ -n "${aws_bin:-}" ]]
  then
    log "aws-cli is already installed."
  else
    if [[ "$kernel" == "Linux" ]]
    then
      tmpdir=$(mktemp -d 2> /dev/null || mktemp -d -t 'devbox-awscli')
      log "Using temp directory '$tmpdir'"
      pushd $tmpdir > /dev/null
      curl -L https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip -o awscliv2.zip
      unzip -q awscliv2.zip
      sudo ./aws/install
      popd > /dev/null
      rm -rf $tmpdir
    elif [[ "$kernel" == "Darwin" ]]
    then
      brew install awscli
    else
      err "Unknown kernel \"$kernel\"."
    fi
  fi
}

#
# Install fnm (fast node manager)
#
# @param string $1 - the path to the profile file to update. If ommitted profile update is skipped
#
function install_fnm() {
  local profile="${1:-}"
  local install_dir="$HOME/.local/share/fnm"
  local fnm_bin="$(which fnm 2> /dev/null || true)"
  local tmpdir

  if [[ -n "${fnm_bin:-}" ]]
  then
    log "fnm is already installed."
  else
    tmpdir=$(mktemp -d 2> /dev/null || mktemp -d -t 'devbox-fnm')
    log "Using temp directory '$tmpdir'"
    pushd $tmpdir > /dev/null
    curl -L https://fnm.vercel.app/install -o install.sh
    chmod +x install.sh
    ./install.sh --install-dir "$install_dir" --skip-shell
    popd > /dev/null
    rm -rf $tmpdir
  fi

  # update profile if it is not already updated
  if [[ -n "$profile" ]]
  then
    log "Profile is \"$profile\"."
    if cat "$profile" | grep -q 'eval "`fnm env[^`]*`"'; then
      log "Profile is already set to load fnm. Skipping."
    else
      log "Adding fnm to profile."
      {
        echo ''
        echo '# fnm'
        echo 'FNM_PATH="'"$install_dir"'"'
        echo 'if [ -d "$FNM_PATH" ]; then'
        echo '  export PATH="'$install_dir':$PATH"'
        echo '  eval "`fnm env`"'
        echo 'fi'
      } | tee -a "$profile"

      # tell devbox to report that environment needs reload
      return 90
    fi
  fi
}

#
# Install node using fnm (must already be installed by homebrew or other means)
#
# @param string $1 - version to install
#
function install_node() {
  local version="$1"
  local fnm_bin="$(which fnm 2> /dev/null || true)"

  # if fnm bin was not found on path then try and find it
  if [[ -z "${fnm_bin:-}" ]]
  then
    if [[ -x "$HOME/.local/share/fnm/fnm" ]]
    then
      fnm_bin="$HOME/.local/share/fnm/fnm"
    fi
  fi

  # now use fnm to see if the requested node version needs to be installed
  if eval "$fnm_bin list" | grep -q "* v$version default"; then
    log "fnm reports that 'node v$version' is already installed and is the default, skipping."
  else
    # install requested node version and make it default
    eval "$fnm_bin install v$version"
    log "fnm was used to install 'node v$version'."
    eval "$fnm_bin default v$version"
    log "fnm was used to set the default node version to 'node v$version'."
  fi
}

#
# Install nawsso using npm (must already be installed by fnm or other means)
#
# @param string $1 - version to install
#
function install_nawsso() {
  local version="$1"
  local npm_list
  local fnm_bin="$(which fnm 2> /dev/null || true)"

  # if fnm bin was not found on path then try and find it
  if [[ -z "${fnm_bin:-}" ]]
  then
    if [[ -x "$HOME/.local/share/fnm/fnm" ]]
    then
      fnm_bin="$HOME/.local/share/fnm/fnm"
    fi
  fi

  # if FNM_DIR is defined then fnm has been sourced, otherwise source it
  if [[ -z "${FNM_DIR:-}" ]]
  then
    eval "`$fnm_bin env`"
  fi

  # now we can use npm to check for globally installed modules
  npm_list="$(npm list -g --depth=0 --no-update-notifier)"

  # check npm_list for the requested version of nawsso
  if echo "$npm_list" | grep -q "@heathprovost/nawsso@$version"; then
    log "npm reports that '@heathprovost/nawsso@$version' is already installed, skipping."
  else
    # install nawsso
    npm install -g @heathprovost/nawsso@$version --no-update-notifier
    log "npm was used to install '@heathprovost/nawsso@$version' globally."
  fi
}

#=============================================================================#
# Main Setup
#=============================================================================#

#
# Execute a series of installer functions sequentially and report results
#
function setup() {
  local completion_report_output

  # call init
  devbox_init

  # run all the installers one at a time
  install 'common-packages' "$DEVBOX_OS_NAME"
  install 'git' "$DEVBOX_OS_NAME"
  install 'git-config'
  install 'dotnet-sdk' "$DEVBOX_OS_NAME"
  install 'java-jdk' "$DEVBOX_OS_NAME"
  install 'aws-cli' "$DEVBOX_OS_KERNEL" "$DEVBOX_OS_ARCH"
  install 'fnm' "$DEVBOX_PROFILE_FILE"
  install 'node' '20.18.0'
  install 'nawsso' '1.8.5'

  # capture output of completion report and perform cleanup
  completion_report_output="$(completion_report && cleanup)"

  printf "$completion_report_output\n"
}

# only run when called directly and not sourced from another script (works in bash and zsh)
if [[ "${0}" == "bash" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]] || echo "${ZSH_EVAL_CONTEXT+}" | grep -q "file"
then
  resolve_sudo
  setup
fi

} # this ensures that the entire script is downloaded #
