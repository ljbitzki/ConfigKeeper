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
done < <( inotifywait -q -q -mr --format "%e %w%f" DPH -e create -e close_write -e delete -e move --excludei '.*(\..*\.sw.$|\.swp$|.*\.swp\..*|\.swp.$|\~$|\.tmp$|^\.\/)' )