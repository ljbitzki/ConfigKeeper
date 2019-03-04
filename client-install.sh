#!/bin/bash

if [ "$(whoami)" != "root" ]; then
  echo "You need to run this script as root!"
  exit 1
fi

echo "Entre the IP address or full DNS name of the \"ConfigKeeper\" server:"
read -r SERVER
echo -e "Is \e[33m${SERVER}\e[0m correct? (y/N)"
read ISC
case "${ISC}" in
  y|Y)
      echo "Let's go!"
      ;;
    *)
      echo -e "\e[31m--------- ERROR ---------> \e[0mYou need to enter a valid answer!"
      exit 1
      ;;
esac
# Some vars for the setup
LOGFILE="/var/log/configkeeper.log"
HOSTNAME=$( awk -F'.' '{print $1}' "/etc/hostname" )
APPS="/etc/configkeeper/conf.d/apps.conf"
TEMPLATE="/etc/configkeeper/base/template.app"
MAINFILE="/etc/configkeeper/ck.sh"
APPS_MON="/etc/configkeeper/monitors/apps.mon"
MONDIR="/etc/configkeeper/monitors"
PERMDIR="/etc/configkeeper/permissions"
INITD="/etc/init.d/configkeeper"
FLF="/usr/share/figlet/3d.flf"

# Installing dependencies...
echo -e "\e[32m-----------------> \e[96mInstalling dependencies...\e[0m"
apt update
apt install wget gawk figlet openssh-client inotify-tools git -y
if [[ ! -f "${FLF}" ]]; then
	wget ""https://raw.githubusercontent.com/xero/figlet-fonts/master/3d.flf"" -O "${FLF}"
fi
echo -e "\e[32m-----------------> \e[96mCreating some directories, files and stuff...\e[0m"
# Logfile and directories
touch "/var/log/configkeeper.log"
chmod 644 "/var/log/configkeeper.log"
chown root:root "/var/log/configkeeper.log"
mkdir -p "/var/lock/configkeeper/"
mkdir -p /etc/configkeeper/{permissions,base,monitors,conf.d}

echo -e "\e[32m-----------------> \e[96mIf \"$(whoami)\" don't have a ssh keypair, generate it.\e[0m"
# ssh root key generation
if [[ ! -f "/root/.ssh/id_rsa.pub" ]]; then
  ssh-keygen
  echo -e "\e[33m--------- WARNING ---------> \e[0mYou need to copy your \"$(whoami)\"\e[0m public key to \"configkeeper\" user (SSH Keys form at GitLab Admin Panel) \e[33m at ${SERVER}\e[0m. After that, \e[36mrun again this install script\e[0m."
  cat /root/.ssh/id_rsa.pub
  exit 1
else
  if [ "$( ssh -T git@${SERVER} | grep -ci 'configkeeper' )" -ne "1" ]; then
  echo -e "\e[33m--------- WARNING ---------> \e[0mYou need to copy your \"$(whoami)\"\e[0m public key to \"configkeeper\" user (SSH Keys form at GitLab Admin Panel) \e[33m ${SERVER}\e[0m. After that, \e[36mrun again this install script\e[0m."
    cat /root/.ssh/id_rsa.pub
    exit 1
  fi
fi
echo -e "\e[32m-----------------> \e[96mCreating important files...\e[0m"
# Apps to be monitored
if [[ ! -f "${APPS}" ]]; then
cat <<'EOF' > "${APPS}"
#### Create one "system" per line, with a blank space or tab of separation, where: "app /full/path/to/application/" (ended with "/")
#### e.g.: apache2 /etc/apache2/
#### Change this file when any adjustments are needed. Please, don't remove this instructions.
#### Some sugestions... Just uncomment some other or add more.
#### "/etc/default/", "/etc/rsyslog.d/", "/etc/logrotate.d/" e "/etc/ssh/" will be monitored by default.
etc_default /etc/default/
#webserver /var/www/
#nginx /etc/nginx/
#apache2 /etc/apache2/
#dovecot /etc/dovecot/
#postfix /etc/postfix/
#amavis /etc/amavis/
#clamav /etc/clamav/
#fail2ban /etc/fail2ban/
#spamassassin /etc/spamassassin/
rsyslog /etc/rsyslog.d/
logrotate /etc/logrotate.d/
#netplan /etc/netplan/
#ssl_certs /etc/ssl/
ssh /etc/ssh/
EOF
fi

if [[ ! -f "${APPS_MON}" ]]; then
cat <<'EOF' > "${APPS_MON}"
#!/bin/bash
if [[ ! -d "/tmp/configkeeper/" ]]; then
  mkdir -p "/tmp/configkeeper/"
fi
PID=$$
echo "${PID}" > "/tmp/configkeeper/${PID}.pid"
HOSTNAME=$( awk -F'.' '{print $1}' "/etc/hostname" )
PERMDIR="/etc/configkeeper/permissions/"
LOGFILE="/var/log/configkeeper.log"
LOCKDIR="/var/lock/configkeeper"
CK="/etc/configkeeper/ck.sh"
MONDIR="/etc/configkeeper/monitors"
APPS="/etc/configkeeper/conf.d/apps.conf"

function LOCK() {
  echo '1' > "${LOCKDIR}/${MFILE}.lock"
  sleep 4
  if [[ -f "${LOCKDIR}/${MFILE}.lock" ]]; then
    rm -f "${LOCKDIR}/${MFILE}.lock"
  fi
}

function APP_MONITOR() {
  sleep 2
  if [[ -f "${LOCKDIR}/${MFILE}.lock" ]]; then
    if [ "$( cat "${LOCKDIR}/${MFILE}.lock" )" -eq "0" ]; then
    echo -e "$(date +'%b %d %H:%M:%S') ${HOSTNAME} APPS_MONITORED: Modified!\t\t\"${FULLPATH}\"" >> "${LOGFILE}"
    "${CK}" "APP_MONITOR" &
    while read -r GITAPP GITDIR; do
      "${CK}" "COMMIT" "${GITAPP}" "${MFILE}" "${GITDIR}"
      sleep 1
    done < <( grep -Ev '^#|^$' "${APPS}" | sort )
      sleep 1
      "${CK}" "COMMIT" "Permissions" "PERM_FILES" "${PERMDIR}"
      if [[ -f "${LOCKDIR}/${MFILE}.lock" ]]; then
        rm -f "${LOCKDIR}/${MFILE}.lock"
      fi
    fi
  fi
}

while read EVENT FULLPATH; do
MFILE=${FULLPATH##*/}
  case "${EVENT}" in
    CREATE)
      if [[ ! -f "${LOCKDIR}/${MFILE}" ]]; then
        echo '0' > "${LOCKDIR}/${MFILE}.lock"
      fi
      ;;
    CLOSE*)
      if [ "$( cat "${LOCKDIR}/${MFILE}.lock" )" -eq "0" ]; then
        APP_MONITOR &
      fi
      ;;
    DELETE)
      if [[ -f "${LOCKDIR}/${MFILE}.lock" ]]; then
        if [ "$( cat "${LOCKDIR}/${MFILE}.lock" )" -eq "0" ]; then
          LOCK &
          APP_MONITOR &
        fi
      else
        echo '0' > "${LOCKDIR}/${MFILE}.lock"
        APP_MONITOR &
      fi
      ;;
  esac
done < <( inotifywait -q -mr --format "%e %w%f" "/etc/configkeeper/conf.d/" -e create -e close_write -e delete --excludei '.*(\..*\.sw.$|\.swp$|.*\.swp\..*|\.swp.$|\~$|\.tmp$|^\.\/)' )
EOF
fi
chmod +x "${APPS_MON}"

if [[ ! -f "${TEMPLATE}" ]]; then
cat <<'EOF' > "${TEMPLATE}"
#!/bin/bash
if [[ ! -d "/tmp/configkeeper/" ]]; then
  mkdir -p "/tmp/configkeeper/"
fi
PID=$$
echo "${PID}" > "/tmp/configkeeper/${PID}.pid"

HOSTNAME=$( awk -F'.' '{print $1}' "/etc/hostname" )
LOGFILE="/var/log/configkeeper.log"
LOCKDIR="/var/lock/configkeeper"
CK="/etc/configkeeper/ck.sh"
MAPP="APH"

function LOCK() {
  FFILE="${1}"
  echo '1' > "${LOCKDIR}/${FFILE}.lock"
  echo -e "$(date +'%b %d %H:%M:%S') ${HOSTNAME} ${MAPP}: Locked!\t\"${LOCKDIR}/${FFILE}.lock\"" >> "${LOGFILE}"
  sleep 3
  if [[ -f "${LOCKDIR}/${FFILE}.lock" ]]; then
    rm -f "${LOCKDIR}/${FFILE}.lock"
  fi
  echo -e "$(date +'%b %d %H:%M:%S') ${HOSTNAME} ${MAPP}: Unlocked!\t\"${LOCKDIR}/${FFILE}.lock\"" >> "${LOGFILE}"
}

function COMMITF() {
  FFILE="${1}"
  FDIR="${2}"
  EVENT="${3}"
  sleep 2
  if [[ -f "${LOCKDIR}/${FFILE}.lock" ]]; then
    if [ "$( cat "${LOCKDIR}/${FFILE}.lock" )" -eq "0" ]; then
      "${CK}" "COMMIT" "${MAPP}" "${FFILE}" "${FDIR}"
      echo -e "$(date +'%b %d %H:%M:%S') ${HOSTNAME} ${MAPP}: (COMMITF) Commited! (${EVENT})\t\t\"${FULLPATH}\"" >> "${LOGFILE}"
        if [[ -f "${LOCKDIR}/${FFILE}.lock" ]]; then
          rm -f "${LOCKDIR}/${FFILE}.lock"
        fi
    fi
  fi
}

function COMMITD() {
  FFILE="${1}"
  FDIR="${2}"
  EVENT="${3}"
  sleep 1
  "${CK}" "COMMIT" "${MAPP}" "${FFILE}" "${FDIR}"
  echo -e "$(date +'%b %d %H:%M:%S') ${HOSTNAME} ${MAPP}: (COMMITD) Commited! (${EVENT})\t\t\"${FULLPATH}\"" >> "${LOGFILE}"
}

while read -r EVENT FULLPATH; do
FFILE=${FULLPATH##*/}
  case "${EVENT}" in
    CREATE)
      if [[ ! -f "${LOCKDIR}/${FFILE}.lock" ]]; then
        echo '0' > "${LOCKDIR}/${FFILE}.lock"
      fi
      ;;
    CLOSE*)
      if [[ ! -f "${LOCKDIR}/${FFILE}.lock" ]]; then
        echo '0' > "${LOCKDIR}/${FFILE}.lock"
      fi
      if [ "$( cat "${LOCKDIR}/${FFILE}.lock" )" -eq "0" ]; then
        COMMITF "${FFILE}" "${FULLPATH}" "${EVENT}" &
      fi
      ;;
    DELETE)
      if [[ -f "${LOCKDIR}/${FFILE}.lock" ]]; then
        if [ "$( cat "${LOCKDIR}/${FFILE}.lock" )" -eq "0" ]; then
          LOCK "${FFILE}" &
          COMMITF "${FFILE}" "${FULLPATH}" "${EVENT}" &
        fi
      else
        echo '0' > "${LOCKDIR}/${FFILE}.lock"
        COMMITF "${FFILE}" "${FULLPATH}" "${EVENT}" &
      fi
      ;;
    CREATE,ISDIR|MOVED_FROM,ISDIR|MOVED_TO,ISDIR|DELETE,ISDIR)
      COMMITD "${FULLPATH}" "${FULLPATH}" "${EVENT}" &
      ;;
    MOVED_FROM|MOVED_TO)
      COMMITF "${FULLPATH}" "${FULLPATH}" "${EVENT}" &
      ;;
  esac
done < <( inotifywait -q -mr --format "%e %w%f" DPH -e create -e close_write -e delete -e move --excludei '.*(\..*\.sw.$|\.swp$|.*\.swp\..*|\.swp.$|\~$|\.tmp$|^\.\/)' )
EOF
fi

if [[ ! -f "${MAINFILE}" ]]; then
cat <<'EOF' > "${MAINFILE}"
#!/bin/bash
LOGFILE="/var/log/configkeeper.log"
FUNCTION_CALL="${1}"
GITAPP=${2}
GITFILE="${3}"
GITDIR=$( echo ${4%/*} | sed 's|$|\/|' | sed 's|//|/|g' )
CK="/etc/configkeeper/ck.sh"

function COMMIT() {
HOSTNAME=$( awk -F'.' '{print $1}' "/etc/hostname" )
GITAPP="${1}"
GITFILE="${2##*/}"
GITDIR="${3}"
GITCON="/tmp/configkeeper/${GITAPP}.con"
GITLST="/tmp/configkeeper/${GITAPP}.lst"

if [[ ! -f "${GITCON}" ]]; then
  echo "$(date +%s) ${GITDIR}" >> "${GITLST}"
  cat <<'EOF2' > "${GITCON}"
#!/bin/bash
HOSTNAME=$( awk -F'.' '{print $1}' "/etc/hostname" )
function AUTODESTROY() {
  sleep 1
  if [[ -f "/tmp/configkeeper/${GITAPP}.con" ]]; then
    rm -f "/tmp/configkeeper/${GITAPP}.con"
  fi
}
LOGFILE="/var/log/configkeeper.log"
GITAPP="${1}"
GITDIR="${2}"
GITLST="/tmp/configkeeper/${GITAPP}.lst"
if [[ -f "${GITLST}" ]]; then
DIFF="0"
  while [ "${DIFF}" -lt 5 ]; do
    sleep 1
    NOW=$( date +%s )
    LAST=$( tail -n1 "${GITLST}" | awk '{print $1}' )
    DIFF=$((NOW-LAST))
  done
  git add -f "${GITDIR}"
  rm -f "${GITLST}"
  cd "${GITDIR}" || exit 0
  git commit -m "Commit in $(date +'%Y/%m/%d - %H:%M:%S')" --quiet &> /dev/null
  git push -u origin master --quiet
  wait
  echo "$(date +'%b %d %H:%M:%S') ${HOSTNAME} CK-COMMIT: ${GITAPP} commited!" >> "${LOGFILE}"
  AUTODESTROY &
  exit 0
fi
EOF2
  chmod +x "${GITCON}"
  "${GITCON}" "${GITAPP}" "${GITDIR}" &
else
  echo "$(date +%s) ${TOGIT}" >> "${GITLST}"
fi
exit
}

function FILEDIG() {
HOSTNAME=$( awk -F'.' '{print $1}' "/etc/hostname" )
LOGFILE="/var/log/configkeeper.log"
PERMDIR="/etc/configkeeper/permissions"
GITAPP="${1}"
GITDIR="${2}"
GITTREE="${PERMDIR}/${GITAPP}.perms"
if [[ -f "${GITTREE}" ]]; then
  rm -f "${GITTREE}"
fi
while read FILE; do
  FDSTAT=$( stat "${FILE}" )
  FD=$( echo -e "${FDSTAT}" | grep -E 'File: |Arquivo: ' | awk '{print $NF}' )
  PERM=$( echo -e "${FDSTAT}" | grep -E 'Access: \(|Acesso: \(' | awk -F'(' '{print $2}' | awk -F')' '{print $1}' )
  OWNER=$( echo -e "${FDSTAT}" | grep -E 'Access: \(|Acesso: \(' | awk -F'(' '{print $3}' | awk -F')' '{print $1}' | awk -F'/' '{print $NF}' | tr -d " \t" )
  FDUID=$( echo -e "${FDSTAT}" | grep -E 'Access: \(|Acesso: \(' | awk -F'(' '{print $3}' | awk -F')' '{print $1}' | awk -F'/' '{print $1}'  | tr -d " \t" )
  GROUP=$( echo -e "${FDSTAT}" | grep -E 'Access: \(|Acesso: \(' | awk -F'(' '{print $4}' | awk -F')' '{print $1}' | awk -F'/' '{print $NF}' | tr -d " \t" )
  FDGID=$( echo -e "${FDSTAT}" | grep -E 'Access: \(|Acesso: \(' | awk -F'(' '{print $4}' | awk -F')' '{print $1}' | awk -F'/' '{print $1}'  | tr -d " \t" )
  if [ $( echo ${FD} | wc -c ) -le "8" ]; then
    TAB="\t\t\t\t\t\t\t\t\t\t\t\t\t"
  elif [ $( echo ${FD} | wc -c ) -le "16" ]; then
    TAB="\t\t\t\t\t\t\t\t\t\t\t\t"
  elif [ $( echo ${FD} | wc -c ) -le "24" ]; then
    TAB="\t\t\t\t\t\t\t\t\t\t\t"
  elif [ $( echo ${FD} | wc -c ) -le "32" ]; then
    TAB="\t\t\t\t\t\t\t\t\t\t"
  elif [ $( echo ${FD} | wc -c ) -le "40" ]; then
    TAB="\t\t\t\t\t\t\t\t\t"
  elif [ $( echo ${FD} | wc -c ) -le "48" ]; then
    TAB="\t\t\t\t\t\t\t\t"
  elif [ $( echo ${FD} | wc -c ) -le "56" ]; then
    TAB="\t\t\t\t\t\t\t"
  elif [ $( echo ${FD} | wc -c ) -le "64" ]; then
    TAB="\t\t\t\t\t\t"
  elif [ $( echo ${FD} | wc -c ) -le "72" ]; then
    TAB="\t\t\t\t\t"
  elif [ $( echo ${FD} | wc -c ) -le "80" ]; then
    TAB="\t\t\t\t"
  elif [ $( echo ${FD} | wc -c ) -le "88" ]; then
    TAB="\t\t\t"
  elif [ $( echo ${FD} | wc -c ) -le "96" ]; then
    TAB="\t\t"
  else
    TAB="\t"
  fi
  echo -e "${FD}${TAB}|\tPerm: ${PERM}\t\t|\tOwner/Group: (${OWNER}:${GROUP})\t|\tUid/Gid: (${FDUID}:${FDGID})" >> "${GITTREE}"
done < <( find "${GITDIR}" )
echo "$(date +'%b %d %H:%M:%S') ${HOSTNAME} FILEDIG: Generated! ${GITDIR}" >> "${LOGFILE}"
exit
}

function PERM_TREE() {
HOSTNAME=$( awk -F'.' '{print $1}' "/etc/hostname" )
LOGFILE="/var/log/configkeeper.log"
APPS="/etc/configkeeper/conf.d/apps.conf"
PERMDIR="/etc/configkeeper/permissions"
GITAPP="${1}"
GITDIR="${2}"
TMPAPPS="/tmp/apps.tmp"
grep -Ev '^#|^$' "${APPS}" > "${TMPAPPS}"
GITTREE="${PERMDIR}/${GITAPP}.perms"
if [[ -f "${GITTREE}" ]]; then 
  PERMS_IN_DISK=$( find "${GITDIR}" | sort )
  PERMS_IN_FILE=$( awk '{print $1}' "${GITTREE}" | sort )
    if [ "${PERMS_IN_DISK}" != "${PERMS_IN_FILE}" ]; then
      rm -f "${GITTREE}"
      FILEDIG "${GITAPP}" "${GITDIR}"
      while [[ ! -f "${PERMDIR}/${GITAPP}.perms" ]]; do
        sleep 1
      done
      sleep 2
      echo "$(date +'%b %d %H:%M:%S') ${HOSTNAME} PERM_TREE: Modified! \"${GITTREE}\"" >> "${LOGFILE}"
      COMMIT "${GITAPP}" "${GITTREE}" "${PERMDIR}"
    fi
else
  FILEDIG "${GITAPP}" "${GITDIR}"
  while [[ ! -f "${PERMDIR}/${GITAPP}.perms" ]]; do
    sleep 1
  done
  sleep 2
  echo "$(date +'%b %d %H:%M:%S') ${HOSTNAME} PERM_TREE: Created! \"${GITTREE}\"" >> "${LOGFILE}"
  COMMIT "${GITAPP}" "${GITTREE}" "${PERMDIR}"
fi

while read PDIFFER; do
  if [[ -f "${PERMDIR}/${PDIFFER}.perms" ]]; then
    rm -f "${PERMDIR}/${PDIFFER}.perms"
    COMMIT "${GITAPP}" "${GITTREE}" "${PERMDIR}"
    echo "$(date +'%b %d %H:%M:%S') ${HOSTNAME} PERM_TREE: Removed! ${PERMDIR}/${PDIFFER}.perms" >> "${LOGFILE}"
  fi
done < <( diff <( awk '{print $1}' "${TMPAPPS}" | sort ) <( ls "${PERMDIR}" | grep '.perms' | awk -F'.perms' '{print $1}' | sort ) | grep '>' | awk '{print $NF}' )
exit
}

function APP_MONITOR() {
HOSTNAME=$( awk -F'.' '{print $1}' "/etc/hostname" )
LOGFILE="/var/log/configkeeper.log"
MONDIR="/etc/configkeeper/monitors"
TEMPLATE="/etc/configkeeper/base/template.app"
APPS="/etc/configkeeper/conf.d/apps.conf"
TMPAPPS="/tmp/apps.tmp"
grep -Ev '^#|^$' "${APPS}" > "${TMPAPPS}"

while read -r GITAPP GITDIR; do
  if [[ ! -f "${MONDIR}/${GITAPP}.app" ]]; then
    cp "${TEMPLATE}" "${MONDIR}/${GITAPP}.app"
    sed -i "s|DPH|${GITDIR}|g" "${MONDIR}/${GITAPP}.app"
    sed -i "s|APH|${GITAPP}|g" "${MONDIR}/${GITAPP}.app"
    chmod +x "${MONDIR}/${GITAPP}.app"
    "${MONDIR}/${GITAPP}.app" &
    echo "$(date +'%b %d %H:%M:%S') ${HOSTNAME} APP_MONITOR: File ${MONDIR}/${GITAPP}.app created!" >> "${LOGFILE}"
    "${CK}" "PERM_TREE" "${GITAPP}" "FILE" "${GITDIR}"
  fi
done <"${TMPAPPS}"

while read ADIFFER; do
  if [[ -f "${MONDIR}/${ADIFFER}.app" ]]; then
    rm -f "${MONDIR}/${ADIFFER}.app"
    echo "$(date +'%b %d %H:%M:%S') ${HOSTNAME} APP_MONITOR: File ${MONDIR}/${GITAPP}.app removed!" >> "${LOGFILE}"
  fi
done < <( diff <( awk '{print $1}' "${TMPAPPS}" | sort ) <( ls "${MONDIR}" | grep '.app' | awk -F'.app' '{print $1}' | sort ) | grep '>' | awk '{print $NF}' )
}

case "${FUNCTION_CALL}" in
  COMMIT)
      COMMIT "${GITAPP}" "${GITFILE}" "${GITDIR}"
      ;;
  APP_MONITOR)
      APP_MONITOR
      ;;
  PERM_TREE)
      PERM_TREE "${GITAPP}" "${GITDIR}"
      ;;
  *)
      echo "$(date +'%b %d %H:%M:%S') ${HOSTNAME} ERROR: Something gone wrong!" >> "${LOGFILE}"
      exit 1
      ;;
esac
EOF
fi
chmod +x "${MAINFILE}"

echo -e "\e[32m-----------------> \e[96mInitial push...\e[0m"
# Initial push
TMPAPPS="/tmp/git.apps"
grep -Ev '^#|^$' "${APPS}" > "${TMPAPPS}"

while read -r GITAPP GITDIR; do
  if [[ ! -f "${MONDIR}/${GITAPP}.app" ]]; then
    cp "${TEMPLATE}" "${MONDIR}/${GITAPP}.app"
    sed -i "s|DPH|${GITDIR}|g" "${MONDIR}/${GITAPP}.app"
    sed -i "s|APH|${GITAPP}|g" "${MONDIR}/${GITAPP}.app"
    chmod +x "${MONDIR}/${GITAPP}.app"
    sleep 1
    echo "$(date +'%b %d %H:%M:%S') ${HOSTNAME} FIRST-RUN: Created! ${MONDIR}/${GITAPP}.app" >> "${LOGFILE}"
    "${MAINFILE}" "PERM_TREE" "${GITAPP}" "FILE" "${GITDIR}" 
  fi
done <"${TMPAPPS}"

git config --global user.name "ConfigKeeper"
git config --global user.email "configkeeper@localhost"
cd / || exit 1
git init
echo '*' > .gitignore
git add -f .gitignore
git commit -m "All /" --quiet &> /dev/null
git remote add origin git@${SERVER}:root/"${HOSTNAME}".git
while read -r GITAPP GITDIR; do
  git add -f "${GITDIR}"
done <"${TMPAPPS}"
git add -f "${PERMDIR}"
git commit -m "INITIALPUSH: Commit in $(date +'%Y/%m/%d - %H:%M:%S')" --quiet &> /dev/null
git push -u origin master --quiet

echo -e "\e[32m-----------------> \e[96mCreating init script...\e[0m"
# Init script
if [[ ! -f "${INITD}" ]]; then
cat <<'EOF' > "${INITD}"
#! /bin/bash

### BEGIN INIT INFO
# Provides:          ConfigKeeper
# Required-Start:    $local_fs $network
# Required-Stop:     $local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: ConfigKeeper Service
# Description:       Run ConfigKeeper Service
### END INIT INFO
MONDIR="/etc/configkeeper/monitors/"
PIDSDIR="/tmp/configkeeper/"
case "${1}" in
  start)
    if [ $( ps aux | grep "inotifywait" | wc -l ) -lt 2 ]; then
      echo "Starting ConfigKeeper and loading monitors..."
      while read APPS; do
        "${APPS}" &
      done < <( find "${MONDIR}" -type f )
      echo "ConfigKeeper started!"
      exit 0
    else
      echo "ConfigKeeper is already running!"
      echo "Stop this shit first!"
      exit 1
    fi
    ;;
  stop)
    echo "Stopping ConfigKeeper..."
      killall inotifywait
      wait
      while read PIDS; do
        GITPID="${PIDS##*/}"
        PID=$( echo "${GITPID}" | awk -F'.' '{print $1}' )
        kill -9 "${PID}"
        rm -f "${PIDSDIR}${GITPID}"
      done < <( find "${PIDSDIR}" -type f -name "*.pid" )
      echo "All monitors killed and ConfigKeeper stoped!"
      exit 0
    ;;
  restart|reload)
    echo "Restarting/Reloading ConfigKeeper..."
    "${0}" "stop"
    sleep 1
    "${0}" "start"
    exit 0
    ;;
  *)
    echo "Usage: /etc/init.d/configkeeper {start|stop|restart|reload}"
    exit 1
    ;;
esac
exit 0
EOF
fi
chmod +x "${INITD}"
update-rc.d configkeeper defaults

echo -e "\e[32m-----------------> \e[96mAdding some stuff to crontab...\e[0m"
# Setting up the crontab
sed -i '$ d' "/etc/crontab"
{
echo -e "# Garbage collector from orphan lock files.\n1 0 * * *   root    find /var/lock/configkeeper/ -type f -mtime +1 -delete"
echo -e "# Apps remapping.\n2 0 * * *   root    /etc/configkeeper/ck.sh \"APP_MONITOR\""
echo -e "# Permission remapping.\n3 0 * * *   root    while read GITAPP GITDIR; do /etc/configkeeper/ck.sh PERM_TREE \${GITAPP} \${GITDIR} \${GITDIR}; done < <( grep -Ev '^#|^$' /etc/configkeeper/conf.d/apps.conf )"
echo -e "# Permission commit.\n3 5 * * *   root    cd /etc/configkeeper/permissions/ || exit; /etc/configkeeper/ck.sh COMMIT permissions permissions /etc/configkeeper/permissions/\n#"
} >> "/etc/crontab"

echo -e "\e[32m-----------------> \e[96mInitializing ConfigKeeper...\e[0m"
/etc/init.d/configkeeper start

echo -e "\e[32m-----------------> \e[96mThat's it!\e[0m"
( sleep 3 ; echo -e "ConfigKeeper\ninstalled!" | /usr/bin/figlet -w 1200 -f "${FLF}" ; exit 0 ) &

exit 0
