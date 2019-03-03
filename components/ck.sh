#!/bin/bash

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
  git commit -m "Commit in $(date +'%Y/%m/%d - %H:%M:%S')" --quiet
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