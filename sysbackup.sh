#!/usr/bin/env bash
#
# Copyright (c) 2020 Garri Djavadyan
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


TARGETS="/ /home /usr /var"		# Filesystems to backup
EXCLUDE[1]="/mnt"			# First exclude expression. See tar(1) for details.
BACKUP_DIR="/backup/server1"		# Full path to directory contining system and mysql subdirs
BACKUP_DST="local"			# Backup destination (local, remote)
COMPRESS_TYPE="gzip"			# Valid values are gzip, bzip2, xz and gpg (for encryption)

# E-mail reports configuration
MAIL_CMD="/usr/bin/mail"		# Full path to mail process
CONTACT="recipient@example.com"		# E-mail address to send notification

# Remote backup configuration
REMOTE_USER="sysbackup"			# Remote SSH user
REMOTE_HOST="192.168.1.1"		# Remote host IP address or hostname
REMOTE_PORT="22"			# SSH port used to connect to remote backup service

# GPG options
GPG_RCPT[1]="recipient1@example.com"	# First GPG recipient
#GPG_RCPT[2]="recipient2@example.com"

# MySQL backup configuration
DB_OPTS="--single-transaction"		# Options for mysqldump
DB_USER="username"			# User with backup rights on database
DB_PASS="password"			# Password for that user
DB_NAME[1]="first"			# First database to backup
DB_NAME[2]="second"			# Second, third, ... database, if required

# Postgresql backup config
PG_USER="postgres"
PG_DB_NAME[1]="first"
PG_DB_NAME[2]="second"

# The code below is not intended for direct modification.
# Change it only if you are sure it is needed.

print_usage() {
  echo "Usage: $0 [--type=system|mysql|pgsql] [--notify=yes|no] [--dateformat=weekday|monthday|month]"
  exit 1
}

# Check local or remote file size in MB
check_size() {
    if [ ${BACKUP_DST} = "remote" ]; then
	ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "du -m ${BACKUP_DIR}/system/${BACKUP_FILE}.${EXT}" | cut -f 1
    else
	du -m ${BACKUP_DIR}/system/${BACKUP_FILE}.${EXT} | cut -f 1
    fi
}

send_email() {
    [ -x ${MAIL_CMD} ] || { echo "Mail utility not installed. Skip email sending."; return 1; }
    echo -e "Date: $(date)\nBackup Type: ${6}\nHost: ${1}\nFile: ${2}\nSize (MB): ${3}\nDuration (sec): ${4}\nDestination Host: ${5}\n\n---\nArchive created using SysBackup-${VERSION}" | ${MAIL_CMD} -s "SysBackup completed on ${1}" ${CONTACT}
    echo "E-mail sent to ${CONTACT}."
}

main() {
  if [ -f ${LOCK_FILE} ]; then
    echo -e "SysBackup already started. Abort.\nIf you are sure it is not true, please remove file ${LOCK_FILE} manually."
    exit 1
  else
    starttime=$(date +%s)
    touch ${LOCK_FILE}
    trap "rm -f ${LOCK_FILE}; echo -e '\nOperation Abored!'; exit 1" SIGINT SIGTERM
    ${BACKUP_TYPE} || { rm -f ${LOCK_FILE}; echo -e "SysBackup failed."; exit 1; }
    [[ "${BACKUP_DST}" == "remote" ]] && destination="${REMOTE_HOST}" || destination="localhost"
    duration=$(( $(date +%s) - $starttime ))
    if [[ "${NOTIFY}" == "yes" ]]; then
      if [[ "${BACKUP_TYPE}" == "system" ]]; then
        send_email $(hostname) ${BACKUP_FILE}.${EXT} $(check_size) ${duration} ${destination} ${BACKUP_TYPE}
      else
        send_email $(hostname) unknown unknown ${duration} ${destination} ${BACKUP_TYPE}
      fi
    fi
    rm -f ${LOCK_FILE}
    echo "SysBackup completed without errors."
    exit 0
  fi
}

system() {
  [ -n "$(which tar)" ] || { echo "Tar archiver is not installed."; return 1; } 
  if [ ${BACKUP_DST} = "remote" ]; then
    tar -cvf - --one-file-system --xattrs ${EXCLUDE[@]} ${TARGETS} | ${COMPRESSOR} | \
      ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "cat > ${BACKUP_DIR}/system/${BACKUP_FILE}.${EXT}"
  else
    tar -cvf - --one-file-system --xattrs ${EXCLUDE[@]} ${TARGETS} | \
    ${COMPRESSOR} > ${BACKUP_DIR}/system/${BACKUP_FILE}.${EXT}
  fi
}

mysql() {
  [ -n "$(which mysqldump)" ] || { echo "Mysqldump is not installed."; return 1; } 
  if [ ${BACKUP_DST} = "remote" ]; then
    for i in ${DB_NAME[@]}; do
      mysqldump ${DB_OPTS} -u ${DB_USER} -p${DB_PASS} ${i} | ${COMPRESSOR} | \
        ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "cat > ${BACKUP_DIR}/mysql/${i}-${DATEFORMAT}.sql.${EXT}"
    done
  else
    for i in ${DB_NAME[@]}; do
      mysqldump ${DB_OPTS} -u ${DB_USER} -p${DB_PASS} ${i} | ${COMPRESSOR} > ${BACKUP_DIR}/mysql/${i}-${DATEFORMAT}.sql.${EXT}
    done
  fi
}

pgsql() {
  [ -n "$(which pg_dump)" ] || { echo "pg_dump is not installed."; return 1; }
  if [ ${BACKUP_DST} = "remote" ]; then
    for i in ${PG_DB_NAME[@]}; do
      sudo -iu ${PG_USER} pg_dump $i | ${COMPRESSOR} | \
        ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "cat > ${BACKUP_DIR}/pgsql/${i}-${DATEFORMAT}.sql.${EXT}"
    done
  else
    for i in ${DB_NAME[@]}; do
      sudo -iu ${PG_USER} pg_dump $i | ${COMPRESSOR} > ${BACKUP_DIR}/pgsql/${i}-${DATEFORMAT}.sql.${EXT}
    done
  fi
}


# Parse CLI options
for CMD_ARG; do
  case ${CMD_ARG} in
    --type=system)
      BACKUP_TYPE="system"
      ;;
    --type=mysql)
      BACKUP_TYPE="mysql"
      ;;
    --type=pgsql)
      BACKUP_TYPE="pgsql"
      ;;
    --type=*)
      echo "Specified backup type is not supported. Using default 'system'."
      ;;
    --notify=yes)
      NOTIFY="yes"
      ;;
    --notify=no)
      NOTIFY="no"
      ;;
    --dateformat=weekday)
      DATEFORMAT=$(date +%A)
      ;;
    --dateformat=monthday)
      DATEFORMAT=$(date +%d)
      ;;
    --dateformat=month)
      DATEFORMAT=$(date +%B)
      ;;
    --dateformat=*)
      echo "Specified date format is not supported. Using default 'monthday'."
      ;;
    *)
      print_usage
      ;;
  esac
done


# Set defaults
VERSION="0.73"
HOME="/root/"
PATH="${PATH}:/usr/local/bin:/usr/local/sbin"
LOCK_FILE=/tmp/sysbackup.lock
BACKUP_TYPE=${BACKUP_TYPE:-"system"}
NOTIFY=${NOTIFY:-"no"}
DATEFORMAT=${DATEFORMAT:-$(date +%d)}
BACKUP_FILE="sysbackup-${DATEFORMAT}.tar"

# Form a string of GPG recepients
if [[ ${#GPG_RCPT[@]} -gt 0 ]]; then
  for (( i=1; i<=${#GPG_RCPT[@]}; i++)); do
    GPG_RCPT[$i]="-r ${GPG_RCPT[$i]}"
  done
fi

# Adapt command and file extension for compression type
case ${COMPRESS_TYPE} in
  gpg)
    COMPRESSOR="gpg ${GPG_RCPT[@]} -e"
    EXT="gpg"
    ;;
  bzip2)
    COMPRESSOR="bzip2"
    EXT="bz2"
    ;;
  xz)
    COMPRESSOR="xz"
    EXT="xz"
    ;;
  gzip)
    COMPRESSOR="gzip"
    EXT="gz"
    ;;
  *)
    echo "Specified compression is not supported. Valid types are: gzip, bzip2, xz and gpg."
    exit 1
esac

# Aggregate --exclude expressions
if [[ ${#EXCLUDE[@]} -gt 0 ]]; then
  for (( i=1; i<=${#EXCLUDE[@]}; i++)); do
    EXCLUDE[$i]="--exclude=${EXCLUDE[$i]}"
  done
fi

# Call main function
main
