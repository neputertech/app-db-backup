#!/bin/bash

# set -e
# set -o pipefail

################################################################################
# Help                                                                         #
################################################################################
help()
{
   # Display Help
   echo "Backup database"
   echo
   echo "Syntax:./dbbackup.sh"
   echo 
}

## Show help if input is -h or --help
main() {
    if [[ "$1" == "-h" || "$1" == '--help' ]] ; then
      help
      exit 0
    fi
}

# FOLDER_DATE_FORMAT
[[ -n "$(./get_env.sh DB_BACKUP_FOLDER_DATE_FORMAT)" ]] && FOLDER_DATE_FORMAT="$($(./get_env.sh DB_BACKUP_FOLDER_DATE_FORMAT))" || FOLDER_DATE_FORMAT="$(date +%F)"

# FILE_DATE_FORMAT
[[ -n "$(./get_env.sh DB_BACKUP_FILE_DATE_FORMAT)" ]] && FILE_DATE_FORMAT="$($(./get_env.sh DB_BACKUP_FILE_DATE_FORMAT))" || FILE_DATE_FORMAT="$(date +%H-%M-%S)"


sendSlackNotification() {
	BACKUP_STATUS=$1		# Here backup status means backup or upload status
	TYPE=$2
	MESSAGE=$3
	DATE=$4

	# Send if enabled
	if [[ -n "$(./get_env.sh DB_SLACK_NOTIF)" && $(./get_env.sh DB_SLACK_NOTIF) == "true" ]]; then

		# Check whether to send a notification for success event
		if [[ "$BACKUP_STATUS" -eq 0 ]]; then

			if [[ -z "$(./get_env.sh DB_HIDE_SUCCESS_SLACK_NOTIF)" || "$(./get_env.sh DB_HIDE_SUCCESS_SLACK_NOTIF)" != "true" ]]; then
				./slackhook.sh "${BACKUP_STATUS}" "${TYPE}" "${MESSAGE}" "${DATE}"
			fi

		else

			./slackhook.sh "${BACKUP_STATUS}" "${TYPE}" "${MESSAGE}" "${DATE}"

		fi
		
	fi
}

dumpDb() {
	DBNAME=$1

	b=$(./get_env.sh DB_BACKUP_LOCATION)/${DBNAME}  	# This contains backup path with database name
	BACKUP_LOCATION=$b/${FOLDER_DATE_FORMAT}			# This contains backup path with database name and folder 
	mkdir -p ${BACKUP_LOCATION}

	BACKUP_LOCATION_WITH_FILE="${BACKUP_LOCATION}/${FILE_DATE_FORMAT}.sql.gz";
	FILE_NAME="$(echo ${BACKUP_LOCATION_WITH_FILE} | rev | cut -d "/" -f1-3 | rev | sed -e 's/\//_/g')"

	# Start dumping 
	if [[ -n "$(./get_env.sh DB_UNIX_SOCKET)" && "$(./get_env.sh DB_UNIX_SOCKET)" == "true" ]]; then
		sudo mysqldump -v ${DBNAME} | gzip > ${BACKUP_LOCATION_WITH_FILE}
	else
		mysqldump --defaults-file='./.mysqldumpcred' -v ${DBNAME} | gzip > ${BACKUP_LOCATION_WITH_FILE}
	fi

	BACKUP_STATUS=${PIPESTATUS[0]}

	MESSAGE=""
	if [[ ${BACKUP_STATUS} -eq 0 ]]; then
		MESSAGE="$FILE_NAME successully dumped";
	else
		MESSAGE="Failed to dump $FILE_NAME";
	fi
	sendSlackNotification "${BACKUP_STATUS}" "database" "$MESSAGE" ""
	# ./slackhook.sh ${BACKUP_STATUS} "database" "${MESSAGE}" ""	

	# Upload to AWS
	if [[ ${BACKUP_STATUS} -eq 0 ]]; then
		uploadToAws "$BACKUP_LOCATION_WITH_FILE"
	fi

	purgeOldDbBackups $b

}

dumpAllDb() {

	DAYOFWEEK="$(date +%u)"		# Start: 1 [1 is Monday]

	# We'll dump all db on every Saturday
	if [[ "${DAYOFWEEK}" -eq 6 ]]; then

		b=$(./get_env.sh DB_BACKUP_LOCATION)/"all_db"  		# This contains backup path with database name (i,e, all_db)
		BACKUP_LOCATION=$b/${FOLDER_DATE_FORMAT}			# This contains backup path with database name and folder 
		mkdir -p ${BACKUP_LOCATION}

		BACKUP_LOCATION_WITH_FILE="${BACKUP_LOCATION}/${FILE_DATE_FORMAT}.sql.gz";
		FILE_NAME="$(echo ${BACKUP_LOCATION_WITH_FILE} | rev | cut -d "/" -f1-3 | rev | sed -e 's/\//_/g')"

		# Check if older db exists today (Max 1 is allowed per day)
		if [[ "$(find $BACKUP_LOCATION/* -type f | wc -l)" -ge 1 ]]; then
			echo "Max 1 \"all_db\" backups allowed in a day"
		else 

			# Start dumping 
			if [[ -n "$(./get_env.sh DB_UNIX_SOCKET)" && "$(./get_env.sh DB_UNIX_SOCKET)" == "true" ]]; then
				sudo mysqldump -v --all-databases | gzip > ${BACKUP_LOCATION_WITH_FILE}
			else
				mysqldump --defaults-file='./.mysqldumpcred' -v --all-databases | gzip > ${BACKUP_LOCATION_WITH_FILE}
			fi

			BACKUP_STATUS=${PIPESTATUS[0]}

			MESSAGE=""
			if [[ ${BACKUP_STATUS} -eq 0 ]]; then
				MESSAGE="$FILE_NAME successully dumped";
			else
				MESSAGE="Failed to dump $FILE_NAME";
			fi
			sendSlackNotification "${BACKUP_STATUS}" "database" "$MESSAGE" ""

			# Upload to AWS
			if [[ ${BACKUP_STATUS} -eq 0 ]]; then
				uploadToAws "$BACKUP_LOCATION_WITH_FILE"
			fi

			####### Purge Old "all_db"
			purgeOldAllDbBackups "$b"

		fi
		
	fi
}

purgeOldDbBackups() {
	### Delete all backups older than "DB_MAX_BACKUP_DAYS" 
	# older_backups="find ${APP_BACKUP_PATH} -maxdepth 1 -type d -mtime +${DB_MAX_BACKUP_DAYS}"

	DB_BACKUP_PATH="$1/*"
	[[ -n "$(./get_env.sh DB_MAX_BACKUP_DAYS)" ]] && DB_MAX_BACKUP_DAYS="$(./get_env.sh DB_MAX_BACKUP_DAYS)" || DB_MAX_BACKUP_DAYS="15"

	find_exp="find ${DB_BACKUP_PATH} -maxdepth 1 -type d"
	total_backups="$($find_exp | wc -l)" 			# total backup count
	older_backups="$find_exp -mtime +${DB_MAX_BACKUP_DAYS}"		# older than X days
	older_backups_count="$($(echo "${older_backups}") | wc -l)"
	newer_backups_count="$($(echo "$find_exp -mtime -${DB_MAX_BACKUP_DAYS}") | wc -l)"

	# remaining(newer) backups must be equal to max_backups
	if [[ "${newer_backups_count}" -ge ${DB_MAX_BACKUP_DAYS} ]]; then
		echo "Deleting $older_backups_count older backups";
		$(echo "${older_backups}") | xargs rm -rf
	else
		echo "Older backups can not be deleted to preserve existing backups. Please try again."
	fi
	
}

### This will purge older "all_db" databases
purgeOldAllDbBackups() {
	
	DB_BACKUP_PATH="$1/*"
	DB_MAX_BACKUP_DAYS="60"		# 2 months

	find_exp="find ${DB_BACKUP_PATH} -maxdepth 1 -type d"
	total_backups="$($find_exp | wc -l)" 			# total backup count
	older_backups="$find_exp -mtime +${DB_MAX_BACKUP_DAYS}"		# older than X days
	older_backups_count="$($(echo "${older_backups}") | wc -l)"
	newer_backups_count="$($(echo "$find_exp -mtime -${DB_MAX_BACKUP_DAYS}") | wc -l)"

	# remaining(newer) backups must be equal to max_backups
	if [[ "${newer_backups_count}" -ge ${DB_MAX_BACKUP_DAYS} ]]; then
		echo "Deleting $older_backups_count older backups";
		$(echo "${older_backups}") | xargs rm -rf
	else
		echo "Older backups can not be deleted to preserve existing backups. Please try again."
	fi
	
}

getLastName() {
	IFS='/' read -ra ADDR <<< "${1}"	
	echo ${ADDR[-1]}
}

uploadToAws() {
	# Backup if enabled
	if [[ -n "$(./get_env.sh DB_S3_BACKUP)" && $(./get_env.sh DB_S3_BACKUP) == "true" ]]; then

		FILE_NAME="$(echo $1 | rev | cut -d "/" -f1-3 | rev | sed -e 's/\//_/g')"
		FOLDER_PATH="$(echo $1 | rev | cut -d "/" -f2- | cut -d "/" -f1-2 | rev)"
		FILE_PATH=$1

		s3cmd put "${FILE_PATH}" s3://"$(./get_env.sh DB_S3_LOCATION)"/${FOLDER_PATH}/
		UPLOAD_STATUS=$?

		MESSAGE=""
		if [[ ${UPLOAD_STATUS} -eq 0 ]]; then
			MESSAGE="${FILE_NAME} successully uploaded to S3";
		else
			MESSAGE="Failed to upload ${FILE_NAME} to S3";
		fi
		sendSlackNotification "${UPLOAD_STATUS}" "aws" "${MESSAGE}" ""

	fi
}


main "$@"

DB_NAMES=($(./get_env.sh DB_DB_NAMES))
for db in "${DB_NAMES[@]}"; do
	dumpDb "$db"
done


# Dump & Purge All Db
# Backup if enabled
if [[ -n "$(./get_env.sh DB_ALL_DB_BACKUP)" && $(./get_env.sh DB_ALL_DB_BACKUP) == "true" ]]; then
	dumpAllDb
fi
