#!/usr/bin/env bash
#
# Copyright (c) 2017 Garri Djavadyan
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
EXCLUDE="--exclude=/mnt"		# Excluded directories from backup
BACKUP_DIR="/backup/server1"		# Full path to directory contining system and mysql subdirs
BACKUP_TYPE="local"			# Remote or local backup destination (ssh, local)
COMPRESS_TYPE="gzip"			# Valid values are gzip, bzip2, xz and gpg (for encryption)

# E-mail reports configuration
MAIL_CMD="/usr/bin/mail"		# Full path to mail process
CONTACT="recipient@example.com"		# E-mail address to send notification

# Remote backup configuration
REMOTE_USER="sysbackup"			# Remote SSH user
REMOTE_HOST="192.168.1.1"		# Remote host IP address or hostname
REMOTE_PORT="22"			# SSH port used to connect to remote backup service

# GPG options
GPG_RCPT="recipient@example.com"	# GPG recipient

# MySQL backup configuration
DB_OPTS="--single-transaction"		# Options for mysqldump
DB_USER="username"			# User with backup rights on database
DB_PASS="password"			# Password for that user
DB_NAME[1]="first"			# First database to backup
DB_NAME[2]="second"			# Second, third, ... database, if required


# The code below is not intended for direct modification.
# Change it only if you are sure it is needed.

VERSION="0.69"
HOME="/root/"
PATH="${PATH}:/usr/local/bin:/usr/local/sbin"
LOCK_FILE=/tmp/sysbackup.lock
DATE_DOM=`date "+%d"`		# Day of Month
DATE_DOW=`date "+%A"`		# Day of Week
BACKUP_FILE="sysbackup-${DATE_DOM}.tar"

# Adapt command and file extension for compression type
case ${COMPRESS_TYPE} in
  gpg)
    COMPRESSOR="gpg -r ${GPG_RCPT} -e"
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

# Check local or remote file size in MB
check_size() {
    if [ ${BACKUP_TYPE} = "ssh" ]; then
	ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "du -m ${BACKUP_DIR}/system/${BACKUP_FILE}.${EXT}" | cut -f 1
    else
	du -m ${BACKUP_DIR}/system/${BACKUP_FILE}.${EXT} | cut -f 1
    fi
}

# Usage: send_email host file size duration destination backup_type
send_email() {
    [ -x ${MAIL_CMD} ] || { echo "Mail utility not installed. Skip email sending."; return 1; }
    echo -e "Date: $(date)\nBackup Type: ${6}\nHost: ${1}\nFile: ${2}\nSize (MB): ${3}\nDuration (sec): ${4}\nDestination Host: ${5}\n\n---\nArchive created using SysBackup-${VERSION}" | ${MAIL_CMD} -s "SysBackup completed on ${1}" ${CONTACT}
    echo "E-mail sent to ${CONTACT}."
}

common() {
  backup_type=${1}
  if [ -f ${LOCK_FILE} ]; then
    echo -e "SysBackup already started. Abort.\nIf you are sure it is not true, please remove file ${LOCK_FILE} manually."
    exit 1
  else
    starttime=$(date +%s)
    touch ${LOCK_FILE}
    trap "rm -f ${LOCK_FILE}; echo -e '\nOperation Abored!'; exit 1" SIGINT SIGTERM
    ${backup_type} || { rm -f ${LOCK_FILE}; echo -e "SysBackup failed."; exit 1; }
    [ ${BACKUP_TYPE} = "ssh" ] && destination="${REMOTE_HOST}" || destination="localhost"
    duration=$(( $(date +%s) - $starttime ))
    [ "${2}" = "notify" ] && {
      if [ ${backup_type} = "system" ]; then
        send_email $(hostname) ${BACKUP_FILE}.${EXT} $(check_size) ${duration} ${destination} ${backup_type}
      else
        send_email $(hostname) unknown unknown ${duration} ${destination} ${backup_type}
      fi
    }
    rm -f ${LOCK_FILE}
    echo "SysBackup completed without errors."
    exit 0
  fi
}

system() {
  [ -n "$(which tar)" ] || { echo "Tar archiver is not installed."; return 1; } 
  if [ ${BACKUP_TYPE} = "ssh" ]; then
    tar -cvf - --one-file-system ${EXCLUDE} ${TARGETS} | ${COMPRESSOR} | \
      ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "cat > ${BACKUP_DIR}/system/${BACKUP_FILE}.${EXT}"
  else
    tar -cvf - --one-file-system ${EXCLUDE} ${TARGETS} | ${COMPRESSOR} > ${BACKUP_DIR}/system/${BACKUP_FILE}.${EXT}
  fi
}

mysql() {
  [ -n "$(which mysqldump)" ] || { echo "Mysqldump is not installed."; return 1; } 
  if [ ${BACKUP_TYPE} = "ssh" ]; then
    for i in ${DB_NAME[@]}; do
      mysqldump ${DB_OPTS} -u ${DB_USER} -p${DB_PASS} ${i} | ${COMPRESSOR} | \
        ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "cat > ${BACKUP_DIR}/mysql/${i}-${DATE_DOW}.sql.${EXT}"
    done
  else
    for i in ${DB_NAME[@]}; do
      mysqldump ${DB_OPTS} -u ${DB_USER} -p${DB_PASS} ${i} | ${COMPRESSOR} > ${BACKUP_DIR}/mysql/${i}-${DATE_DOW}.sql.${EXT}
    done
  fi
}

case ${1} in
    system)
	common ${1} ${2}
	;;
    mysql)
	common ${1} ${2}
	;;
    *)
	echo "Usage: ${0} {system|mysql} [notify]"
	;;
esac
