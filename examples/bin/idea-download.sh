#!/usr/bin/env bash

###
### Script which helps updating to IntelliJ Idea versions from the command line.
###
### * The script requires to run as root (at least for some commands)
### * Installation will be done to /opt/idea
### * Suggestion to place this script:
###    * put it into /opt/idea/bin
###    * add a soft-link /usr/local/bin/idea-download which points to this script to make it
###      available directly from the command-line
###

set -o nounset
set -o pipefail
set -o errexit
### Uncomment to enable debugging
#set -o xtrace

###
### Try to find the best fitting version of readlink.
###
function safe_readlink() {
  $(type -p greadlink readlink | head -1) "${@}"
}

###
### Identify me.
###

declare -r MY_CMD="$(safe_readlink -f "${0}")"
declare -r MY_DIR="$(dirname "${MY_CMD}")"
declare -r MY_REALNAME="$(basename "${MY_CMD}")"
### In help texts we might want to show the name the user used to call this script rather than
### its real name.
declare -r MY_NAME="$(basename "${0}")"

###
### Where to place desktop shortcuts for Ubuntu
###

declare -r SYS_USR_LOCAL="/usr/local"
declare -r SYS_APPLICATIONS="${SYS_USR_LOCAL}/share/applications"

###
### Locations at Jetbrains to contact for download
###

declare -r INTELLIJ_REPOSITORY_URL="https://www.jetbrains.com/intellij-repository/releases"
declare -r INTELLIJ_BUILD_URL="${INTELLIJ_REPOSITORY_URL}/com/jetbrains/intellij/idea/BUILD"
declare -r INTELLIJ_DOWNLOAD_URL="https://download.jetbrains.com/idea"

###
### Places where the downloads will go to
###

declare -r IDEA_INSTALL_ROOT="/opt/idea"
### Unused right now, might be the place for e. g. this script. Might also be used to add links for executing
### IntelliJ Idea via shell.
declare -r IDEA_BIN="${IDEA_INSTALL_ROOT}/bin"
### All installed versions will go here.
declare -r IDEA_VERSION_ROOT="${IDEA_INSTALL_ROOT}/version"
###
declare -r IDEA_DESKTOP_ROOT="${IDEA_INSTALL_ROOT}/desktop"
declare -r IDEA_DOWNLOAD_DIR="${IDEA_INSTALL_ROOT}/download"

###
### Exit States
###

declare -ri EXIT_OK=0
declare -ri EXIT_GENERAL_FAILURE=10
declare -ri EXIT_ILLEGAL_OPTION=11
declare -ri EXIT_ILLEGAL_COMMAND=12
declare -ri EXIT_ILLEGAL_STATE=13

###
### Output formatting
###

declare -ri COLUMNS=$(tput cols)
declare -ri FORMAT_COLUMNS=$((${COLUMNS}>120?120:${COLUMNS}<40?20:${COLUMNS}))
declare -r BOLD="$(tput bold)"
declare -r DIM="$(tput dim)"
declare -r NORMAL="$(tput sgr0)"
declare -r SMUL="$(tput smul)"
declare -r RMUL="$(tput rmul)"
declare -r LRED="${BOLD}$(tput setaf 1)"

###
### Parsed arguments
###

declare arg_version
declare arg_label
declare arg_dryrun=false
declare arg_edition="community"
declare arg_help=false
declare arg_quiet=false
declare arg_action

###
### Result properties
###

declare quiet_output
declare idea_version
declare idea_install_dir

function main() {
  parse_cli "${@}"
  do_action
}

###
### Tell before start if this is a dry-run or not. Much more feasible than doing this for every command.
###
function signal_dryrun() {
  [[ "${arg_dryrun}" == "true" ]] && echo -e "${BOLD}Dry Run${NORMAL}" | info || true
}

###
### Echo result in quiet mode. This result is meant to be used by for example subsequent scripts to
### use it for example to start IntelliJ Idea.
###
function output_quiet_result() {
  [[ "${arg_quiet}" == "true" ]] && [[ -n "${quiet_output:-}" ]] && echo "${quiet_output}" || true
}

###
### Perform the requested actions.
###
function do_action() {
  if [[ "${arg_help}" == "true" ]]; then
    do_help
    exit ${EXIT_OK}
  fi
  case "${arg_action:-}" in
    clean)
      signal_dryrun ; do_clean ;;
    install)
      signal_dryrun ; do_install ;;
    remove)
      signal_dryrun ; do_remove ;;
    repair)
      signal_dryrun ; do_remove ; do_install ;;
    status)
      do_status ;;
    '')
      do_help; exit ${EXIT_OK} ;;
    *)
      echo "Internal error: Do not know how to handle action ${arg_action}." | error
      exit ${EXIT_ILLEGAL_COMMAND}
      ;;
  esac
  output_quiet_result
  exit ${EXIT_OK}
}

### Outputs an Error Message
###
### Usage:
###   echo "Message" | error
###   cat <<HERE | error
###     Long Message
###   HERE
function error() {
  local msg

  IFS= read -r msg
  echo "[ERROR] ${msg}" | fmt --width=${FORMAT_COLUMNS} --tagged-paragraph 1>&2
}

### Outputs a Warn Message. Suppresses output if arg_quiet is true.
###
### Usage:
###   echo "Message" | warn
###   cat <<HERE | info
###     Long Message
###   HERE
function warn() {
  local msg

  IFS= read -r msg
  if [[ "${arg_quiet}" != "true" ]]; then
    echo "[WARN] ${msg}" | fmt --width=${FORMAT_COLUMNS}  --tagged-paragraph
  fi
}

### Outputs an Info Message. Suppresses output if arg_quiet is true.
###
### Usage:
###   echo "Message" | info
###   cat <<HERE | info
###     Long Message
###   HERE
function info() {
  local msg

  IFS= read -r msg
  if [[ "${arg_quiet}" != "true" ]]; then
    echo "[INFO] ${msg}" | fmt --width=${FORMAT_COLUMNS}  --tagged-paragraph
  fi
}

###
### Parses command line arguments using getopt to also support long options.
###
function parse_cli() {
  local opts
  # opts=$(getopt --options v:scunml:qh --longoptions version:,stable,community,ultimate,make-current,label:,dry-run,dryrun,quiet,help --name "${MY_NAME}" -- "$@" || echo "failure")
  opts=$(getopt --options v:scunml:qh --longoptions version:,stable,community,ultimate,make-current,label:,dry-run,dryrun,quiet,help --name "${MY_NAME}" -- "$@" || echo "failure")

  if [[ "${opts}" =~ "failure" ]]; then
    echo "${FUNCNAME}: Failed to parse options. Skip options or use --help to get usage information." | error
    exit ${EXIT_ILLEGAL_OPTION}
  fi

  eval set -- "${opts}"

  while true ; do
    case "$1" in
      -v|--version)
        ### Quoted, so the user does not have to deal with escaping regular expressions.
        arg_version="\\Q${2}\\E"; shift ;;
      -s|--stable)
        ### Pattern to locate stable releases.
        arg_version="([0-9]{2}|[0-9]{4})\\." ;;
      -c|--community)
        arg_edition="community" ;;
      -u|--ultimate)
        arg_edition="ultimate" ;;
      -n|--dry-run|--dryrun)
        arg_dryrun=true ;;
      -m|--make-current)
        arg_label="current" ;;
      -l|--label)
        arg_label="${2}"; shift ;;
      -q|--quiet)
        arg_quiet=true ;;
      -h|--help)
        arg_help=true ;;
      --)
        shift; break ;;
      *)
        echo "${FUNCNAME}: Illegal argument ${1}. Remaining arguments: ${@}" || error
        exit ${EXIT_ILLEGAL_OPTION}
        ;;
    esac
    shift
  done

  for arg do
    case "${1}" in
      install|remove|repair|status|clean)
        ### accepted
        ;;
      *)
        echo "${FUNCNAME}: Unknown command '${1}'. Please choose either install, remove, repair or status." | error
        exit ${EXIT_ILLEGAL_COMMAND}
    esac
    if [[ -n "${arg_action:-}" ]]; then
      echo "${FUNCNAME}: Already chosen action: '${arg_action}'. Cannot perform additional action: '${1}'." | error
      exit ${EXIT_ILLEGAL_COMMAND}
    fi
    arg_action="${1}"
    shift
  done
}

###
### Require to be run as root. If not running as root this will exit. For dry-run it will just signal that
### root access will be required but does not exit.
###
### See http://stackoverflow.com/questions/18215973/how-to-check-if-running-as-root-in-a-bash-script
function require_root() {
  if (( $EUID != 0 )); then
      echo "Must be run in sudo session." | error
      [[ "${arg_dryrun}" == "true" ]] || exit ${EXIT_ILLEGAL_STATE}
  fi
}

###
### Determine the status of the currently installed versions. Only those versions are taken into account
### which match the specified version pattern.
###
function status_installed() {
  local versions=$([[ -d "${IDEA_VERSION_ROOT}" ]] && find "${IDEA_VERSION_ROOT}/" -mindepth 1 -maxdepth 1 -type d | grep --perl-regexp --only-matching "(?<=${IDEA_VERSION_ROOT}/)ideaI.-${arg_version:-}[^/]+" || true)
  local version
  local version_path
  local symlink

  echo "Available installed versions at ${IDEA_VERSION_ROOT}:" | info
  echo "" | info
  for version in ${versions[@]}; do
    version_path="${IDEA_VERSION_ROOT}/${version}"
    symlink="$(ls -l "${IDEA_DESKTOP_ROOT}" | grep --perl-regexp --only-matching --max-count 1 "[^ ]+(?= -> \\Q${version_path}\\E)" || true)"
    if [[ -z "${symlink}" ]]; then
      symlink="${LRED}unreferenced${NORMAL}"
    fi
    echo -e "    * ${version} (${symlink})" | info
  done
  echo "" | info
}

###
### Determine which download version matches the requested version pattern.
###
function locate_download() {
  idea_version="$(curl --silent "${INTELLIJ_REPOSITORY_URL}" | grep --perl-regexp --only-matching --max-count 1 "(?<=${INTELLIJ_BUILD_URL}/)${arg_version:-}[^/]*(?=/)" || true)"

  if [[ -z "${idea_version}" ]]; then
    echo "No version matching ${arg_version:-<undefined>} available." | error
    exit ${EXIT_GENERAL_FAILURE}
  fi
}

###
### List which possible download files exist matching the given pattern.
###
function status_download() {
  local count="${1:-10}"
  local versions=$(curl --silent "${INTELLIJ_REPOSITORY_URL}" | grep --perl-regexp --only-matching --max-count ${count} "(?<=${INTELLIJ_BUILD_URL}/)${arg_version:-}[^/]*(?=/)" || true)
  local version

  echo "Available ${count} most recent versions at ${INTELLIJ_REPOSITORY_URL}:" | info
  echo "" | info
  for version in ${versions[@]}; do
    echo "    * ${version}" | info
  done
}

###
### Clean any unreferenced IntelliJ Idea installations.
###
function do_clean() {
  require_root

  local versions=$([[ -d "${IDEA_VERSION_ROOT}" ]] && find "${IDEA_VERSION_ROOT}/" -mindepth 1 -maxdepth 1 -type d | grep --perl-regexp --only-matching "(?<=${IDEA_VERSION_ROOT}/)ideaI.-${arg_version:-}[^/]+" || true)
  local version
  local version_path
  local symlink
  local cleaned=false

  for version in ${versions[@]}; do
    version_path="${IDEA_VERSION_ROOT}/${version}"
    symlink="$(ls -l "${IDEA_DESKTOP_ROOT}" | grep --perl-regexp --only-matching --max-count 1 "[^ ]+(?= -> \\Q${version_path}\\E)" || true)"
    if [[ -z "${symlink}" ]]; then
      [[ "${arg_dryrun}" == "true" ]] || rm --force --recursive -- "${version_path}"
      echo "Removed unreferenced ${version} at ${version_path}." | info
      cleaned=true
    fi
  done

  if [[ "${cleaned}" != "true" ]]; then
    echo "Nothing to clean up." | info
  else
    echo "" | info
    echo "Cleanup Done." | info
  fi
}

###
### Remove all installed IntelliJ Idea versions matching the given version pattern.
###
function do_remove() {
  require_root

  local versions=$([[ -d "${IDEA_VERSION_ROOT}" ]] && find "${IDEA_VERSION_ROOT}/" -mindepth 1 -maxdepth 1 -type d | grep --perl-regexp --only-matching "(?<=${IDEA_VERSION_ROOT}/)ideaI.-${arg_version:-}[^/]+" || true)
  local version
  local version_path
  local symlink
  local symlink_path
  local cleaned=false

  for version in ${versions[@]}; do
    version_path="${IDEA_VERSION_ROOT}/${version}"
    symlink="$(ls -l "${IDEA_DESKTOP_ROOT}" | grep --perl-regexp --only-matching --max-count 1 "[^ ]+(?= -> \\Q${version_path}\\E)" || true)"
    [[ "${arg_dryrun}" == "true" ]] || rm --force --recursive -- "${version_path}"
    echo "Removed ${version} at ${version_path}." | info
    if [[ -n "${symlink}" ]]; then
      symlink_path="${IDEA_DESKTOP_ROOT}/${symlink}"
      if [[ -f "${symlink_path}.desktop" ]]; then
        [[ "${arg_dryrun}" == "true" ]] || rm --force -- "${symlink_path}.desktop"
        echo "Removed ${symlink_path}.desktop." | info
      fi
      if [[ -L "${SYS_APPLICATIONS}/${symlink}.desktop" ]]; then
        [[ "${arg_dryrun}" == "true" ]] || rm --force -- "${SYS_APPLICATIONS}/${symlink}.desktop"
        echo "Removed ${SYS_APPLICATIONS}/${symlink}.desktop" | info
      fi
      [[ "${arg_dryrun}" == "true" ]] || rm --force -- "${symlink_path}"
      echo "Removed ${symlink_path}." | info
    fi
    cleaned=true
  done

  if [[ "${cleaned}" != "true" ]]; then
    echo "Nothing to remove." | info
  else
    echo "" | info
    echo "Removal Done." | info
  fi
}

###
### Generate a status report of the current installation and possible updates available at the server.
###
function do_status() {
  locate_download
  echo "Most recent available version: ${idea_version}." | info
  echo "" | info
  status_installed
  status_download 20

  echo "" | info
  echo "Status Done." | info
}

###
### Installs the given IntelliJ Idea version and generates a desktop entry.
###
function do_install() {

  require_root
  locate_download

  local idea_name
  local download_file
  local desktop_title
  local desktop_file
  local install_root_dir
  local install_dir
  local install_required

  case "${arg_edition}" in
    community) idea_name="ideaIC" ;;
    ultimate) idea_name="ideaIU" ;;
    *)
      echo "Internal Error: Do not know how to handle edition ${arg_edition}." | error
      exit ${EXIT_GENERAL_FAILURE}
  esac

  install_root_dir="${IDEA_VERSION_ROOT}/${idea_name}-${idea_version}"
  download_file="${IDEA_DOWNLOAD_DIR}/${idea_name}-${idea_version}.tar.gz"

  local tar_root

  if [[ -f ${download_file} ]]; then
    echo "Using cached download file: ${download_file}" | info
  else
    echo "Downloading IntelliJ Idea (${arg_edition}, ${idea_version})." | info
    [[ "${arg_dryrun}" == "true" ]] || curl --location ${INTELLIJ_DOWNLOAD_URL}/${idea_name}-${idea_version}.tar.gz --output "${download_file}"
  fi

  if [[ "${arg_dryrun}" == "false" ]]; then
    tar_root="$(tar tzf "${download_file}"|awk 'BEGIN{FS="/"};{print $1;exit}'||true)"
  else
    tar_root="dry-run"
  fi

  install_dir="${install_root_dir}/${tar_root}"

  if [[ "${arg_dryrun}" == "false" ]]; then
    install_required=$(test -d "${install_dir}" && echo "false" || echo "true")
  else
    echo "Testing for existance of ${install_root_dir}. Check is less strict in dry-run mode." | info
    install_required=$(test -d "${install_root_dir}" && echo "false" || echo "true")
  fi

  if [[ "${install_required}" == "true" ]]; then
    [[ "${arg_dryrun}" == "true" ]] || mkdir -p "${install_root_dir}"
    echo "Extrating IntelliJ Idea to ${install_root_dir}." | info
    [[ "${arg_dryrun}" == "true" ]] || tar xzf "${download_file}" -C "${install_root_dir}"
  else
    echo "Skipping installation as installation already seems to exist. Use 'repair' if the installation is corrupted." | info
  fi

  if [[ -n "${arg_label:-}" ]]; then
    [[ "${arg_dryrun}" == "true" ]] || mkdir -p "${IDEA_DESKTOP_ROOT}"
    [[ "${arg_dryrun}" == "true" ]] || ln -sfn "${install_dir}" "${IDEA_DESKTOP_ROOT}/${idea_name}-${arg_label}"

    echo "Created soft-link ${IDEA_DESKTOP_ROOT}/${idea_name}-${arg_label}." | info

    desktop_file="${IDEA_DESKTOP_ROOT}/${idea_name}-${arg_label}.desktop"
    desktop_title="IntelliJ IDEA ${idea_version} (${arg_edition^})"

    [[ "${arg_dryrun}" == "true" ]] || cat <<DESKTOP > "${desktop_file}"
[Desktop Entry]
Version=${idea_version}
Encoding=UTF-8
Name=${desktop_title}
Comment=IntelliJ IDEA ${arg_edition^} Edition - ${arg_label}; installed via ${MY_NAME}.
Exec=${IDEA_DESKTOP_ROOT}/${idea_name}-${arg_label}/bin/idea.sh
Icon=${IDEA_DESKTOP_ROOT}/${idea_name}-${arg_label}/bin/idea.png
Terminal=false
StartupNotify=true
Type=Application
Categories=Development;IDE;
StartupWMClass=jetbrains-ide
DESKTOP

    echo "Created desktop file ${desktop_file}." | info

    if [ -d "${SYS_APPLICATIONS}" ]; then
      [[ "${arg_dryrun}" == "true" ]] || ln -sfn "${desktop_file}" "/usr/local/share/applications"
      echo "Created/updated application entry at ${SYS_APPLICATIONS}." | info
      echo "" | info
      echo "Available as: ${desktop_title}." | info
    else
      echo "Shared application directory ${SYS_APPLICATIONS} unavailable: Cannot create shared application entry." | warn
      echo "To add a personal desktop entry copy or link ${desktop_file} to e. g. ~/.local/share/applications/." | warn
    fi

  else
    echo "Installed to: ${install_dir}" | info
  fi

  echo "" | info
  echo "Installation Done." | info

  quiet_output="${install_dir}"
}

###
### Output a help text similar to a man page. Paging is triggered automatically if it does not fit on the whole screen.
###
function do_help() {
  cat <<HELP | fmt --width=${FORMAT_COLUMNS} --uniform-spacing | less --quit-if-one-screen --raw-control-chars
${BOLD}NAME${NORMAL}

       ${MY_NAME} - manage IntelliJ Idea installation

${BOLD}SYNOPSIS${NORMAL}

       ${BOLD}${MY_NAME}${NORMAL} ${SMUL}command${RMUL}

       ${BOLD}${MY_NAME}${NORMAL} [${SMUL}options${RMUL}] ${SMUL}command${RMUL}

       ${BOLD}${MY_NAME}${NORMAL} -h | --help

${BOLD}DESCRIPTION${NORMAL}

       ${BOLD}${MY_NAME}${NORMAL} will manage your IntelliJ Idea installation from the command line. It will tell you if
       updates are available and is also able to install these updates.

       In addition to this ${BOLD}${MY_NAME}${NORMAL} might provide a desktop entry for each installed version. To
       create a desktop entry you must either specify the ${BOLD}-m${NORMAL} or ${BOLD}--make-current${NORMAL} option
       or the ${BOLD}-l${NORMAL} or ${BOLD}--label${NORMAL} option. A previous desktop entry with the same label will
       by replaced and thus the prevoius installation might become inaccessible via desktop.

${BOLD}COMMANDS${NORMAL}

       ${BOLD}clean${NORMAL}
              Removes all unreferenced IntelliJ Idea installation.If you specified a version by the
              ${BOLD}-v${NORMAL} or ${BOLD}--version${NORMAL} option, all matching unreferenced versions will
              be removed.

              Requires to be run as root.

       ${BOLD}install${NORMAL}
              Installs IntelliJ Idea. If no version is specified via the ${BOLD}-v${NORMAL} or ${BOLD}--version${NORMAL}
              option, the most recent version will be installed. This is probably not what you want as it possibly
              installs releases not marked as stable yet. So it is recommended to specify a version prefix for stable
              releases, which is for example 2016 for releases in 2016 and 15 for releases in 2015.

              To replace a desktop entry either use the ${BOLD}-m${NORMAL} or ${BOLD}--make-current${NORMAL} option or
              the ${BOLD}-l${NORMAL} or ${BOLD}--label${NORMAL} option.

              Requires to be run as root.

       ${BOLD}remove${NORMAL}
              Removes the IntelliJ Idea installation. Mind that if no ${BOLD}-v${NORMAL} or ${BOLD}--version${NORMAL}
              is specified all versions of IntelliJ Idea are removed. If you specified a version by the
              ${BOLD}-v${NORMAL} or ${BOLD}--version${NORMAL} option, all matching versions will be removed.

              Will also remove any existing desktop entries. To remove all unreferenced installations use
              ${BOLD}clean${NORMAL}.

              Requires to be run as root.

       ${BOLD}repair${NORMAL}
              Will remove the previous installed version of IntelliJ Idea (if available) and install it again. This is
              actually a shortcut to ${BOLD}remove${NORMAL} followed by ${BOLD}install${NORMAL}. Mind that if no
              ${BOLD}-v${NORMAL} or ${BOLD}--version${NORMAL} option is specified this will remove all IntelliJ Idea
              versions and will install the most recent version if IntelliJ Idea. So this might be a good approach if
              you always want to have the latest version installed.

              Requires to be run as root.

       ${BOLD}status${NORMAL}
              Will tell you the currently installed versions of IntelliJ Idea and which of them are dead (thus not
              available as desktop entry). If you specify a version with ${BOLD}-v${NORMAL} or ${BOLD}--version${NORMAL}
              option then the status report will be restricted to versions matching the given prefix.

              ${BOLD}status${NORMAL} will also tell you which recent versions are available at the Jetbrains
              repository

${BOLD}OPTIONS${NORMAL}

       ${BOLD}-c, --community${NORMAL}
              Install the community edition of IntelliJ Idea. This is the default.

       ${BOLD}-n, --dryrun, --dry-run${NORMAL}
              Does not execute anything, just outputs what would have been done. All commands can also be run as
              non-root but will output the error which would prevent execution in non-dry-mode.

       ${BOLD}-h, --help${NORMAL}
              Display help text and exit.  No other output is generated.

       ${BOLD}-l, --label${NORMAL} ${SMUL}name${RMUL}
              Will use the label to create a desktop entry for the given installation. If a version with the same label
              exists, its desktop entry will be replaced rather than another one added. Mind that this does not remove
              the previous version of IntelliJ Idea which might be good to rollback an update but might also lead to
              dead installations, not reachable by any desktop entry.

       ${BOLD}-m, --make-current${NORMAL}
              Marks the installation as current. This is done by labelling the desktop entry as current and thus
              replaces any previous version marked as current.  Using the ${BOLD}-m${NORMAL} or
              ${BOLD}--make-current${NORMAL} option is the same as setting the label to "current" with the
              ${BOLD}-l${NORMAL} or ${BOLD}--label${NORMAL} option.

       ${BOLD}-q, --quiet${NORMAL}
              Disables any output despite errors. When installing a version the only output to stdout will be the
              path to the installed version. This might be used in subsequent commands to start the just installed
              version of IntelliJ Idea.

       ${BOLD}-s, --stable${NORMAL}
              An alternative to specifying the version prefix via the ${BOLD}-v${NORMAL} or ${BOLD}--version${NORMAL}
              option. This will toggle the behavior in that way that only stable releases are accepted.

       ${BOLD}-u, --ultimate${NORMAL}
              Install the ultimate edition of IntelliJ Idea.

       ${BOLD}-v, --version${NORMAL} ${SMUL}prefix${RMUL}
              Specify the version (prefix). The behavior differs for the different commands:

                     ${BOLD}install${NORMAL}
                            Install the most recent matching version.

                     ${BOLD}remove${NORMAL}
                            Remove all matching versions.

                     ${BOLD}repair${NORMAL}
                            Remove all matching versions and install the most recent matching version.

                     ${BOLD}status${NORMAL}
                            Will restrict the status report to the given version.

              If you want to restrict actions to stable versions only it is recommended to use the
              ${BOLD}-s${NORMAL} or ${BOLD}--stable${NORMAL} option instead.

${BOLD}ENVIRONMENT${NORMAL}

       ${BOLD}${IDEA_INSTALL_ROOT}${NORMAL}
              Will contain the IntelliJ Idea data.

       ${BOLD}${IDEA_VERSION_ROOT}${NORMAL}
              Will contain the IntelliJ Idea installations.

       ${BOLD}${IDEA_DESKTOP_ROOT}${NORMAL}
              Will contain the IntelliJ Idea desktop files.

       ${BOLD}${IDEA_DOWNLOAD_DIR}${NORMAL}
              A cache for the IntelliJ Idea downloads. If a cached file is available this one is preferred and
              will not be downloaded from Jetbrains repository.

       ${BOLD}${SYS_APPLICATIONS}${NORMAL}
              Desktop entries will be created here. They are links towards ${BOLD}${IDEA_DESKTOP_ROOT}${NORMAL}.

${BOLD}EXAMPLES${NORMAL}

       ${BOLD}${MY_NAME}${NORMAL}
              Will print this help text. Thus it is the same as calling ${BOLD}${MY_NAME}${NORMAL} with
              ${BOLD}-h${NORMAL} or ${BOLD}--help${NORMAL} option.

       ${BOLD}${MY_NAME} --stable --make-current install${NORMAL}
              Will install the most recent stable version and mark it as current. Thus it will replace the
              desktop entry for the previous version which got marked as current.

       ${BOLD}${MY_NAME} --version 15.0.6 --label 15 install${NORMAL}
              Will install version 15.0.6 and mark it as '15'. Thus it will replace the
              desktop entry for the previous version which got marked as '15'.

       ${BOLD}${MY_NAME} --version 14 install${NORMAL}
              Will install the most recent version 14. No desktop file will be created, so it will not be accessible
              unless you directly call the idea shell script.

       ${BOLD}${MY_NAME} clean${NORMAL}
              Will clean all unreferenced IntelliJ Idea installations such as the one created before. These is
              typically a reminiscent of continuous installations of most recent versions of IntelliJ Idea.

       ${BOLD}${MY_NAME} status --stable${NORMAL}
              Will list all stable versions - installed and those available at Jetbrains repository.

       ${BOLD}${MY_NAME} repair${NORMAL}
              Will remove any previously installed version of IntelliJ Idea and installs the most recent available
              version.

HELP
}

main "${@}"
