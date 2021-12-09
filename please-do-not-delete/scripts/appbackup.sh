#!/bin/bash
# set -e

################################################################################
# Help                                                                         #
################################################################################
help()
{
   # Display Help
   echo "Backup apps directory"
   echo
   echo "Syntax:./appbackup.sh"
   echo 
   echo "Find APP_LOCATION var and set your app directories accordingly"
}

## Show help if input is -h or --help
main() {
    if [[ "$1" == "-h" || "$1" == '--help' ]] ; then
      help
      exit 0
    fi
}

# FOLDER_DATE_FORMAT
[[ -n "$(./get_env.sh APP_BACKUP_FOLDER_DATE_FORMAT)" ]] && FOLDER_DATE_FORMAT="$($(./get_env.sh APP_BACKUP_FOLDER_DATE_FORMAT))" || FOLDER_DATE_FORMAT="$(date +%F)"

# FILE_DATE_FORMAT
[[ -n "$(./get_env.sh APP_BACKUP_FILE_DATE_FORMAT)" ]] && FILE_DATE_FORMAT="$($(./get_env.sh APP_BACKUP_FILE_DATE_FORMAT))" || FILE_DATE_FORMAT="$(date +%H-%M-%S)"

# Source App Location
APP_LOCATION=("$(./get_env.sh APP_APP_LOCATION)")

getAppName() {
	IFS='/' read -ra ADDR <<< "${1}"	
	echo ${ADDR[-1]}
}

exclude_flags=""
excludeDirectory() {
	exclude=("$(./get_env.sh APP_APP_EXCLUDE_DIR)")

	for i in ${exclude[@]}; do
		exclude_flags="${exclude_flags} --exclude=$i"
	done

}


purgeOldBackups() {
	### Delete all backups older than "APP_MAX_BACKUP_DAYS" 
	# older_backups="find ${APP_BACKUP_PATH} -maxdepth 1 -type d -mtime +${APP_MAX_BACKUP_DAYS}"

	APP_BACKUP_PATH="$1/*"
	[[ -n "$(./get_env.sh APP_MAX_BACKUP_DAYS)" ]] && APP_MAX_BACKUP_DAYS="$(./get_env.sh APP_MAX_BACKUP_DAYS)" || APP_MAX_BACKUP_DAYS="15"

	find_exp="find ${APP_BACKUP_PATH} -maxdepth 1 -type d"
	total_backups="$($find_exp | wc -l)" 			# total backup count
	older_backups="$find_exp -mtime +${APP_MAX_BACKUP_DAYS}"		# older than X days
	older_backups_count="$($(echo "${older_backups}") | wc -l)"
	newer_backups_count="$($(echo "$find_exp -mtime -${APP_MAX_BACKUP_DAYS}") | wc -l)"

	# remaining(newer) backups must be equal or greater than max_backup days
	if [[ "${newer_backups_count}" -ge ${APP_MAX_BACKUP_DAYS} ]]; then
		echo "Deleting $older_backups older backups";
		$(echo "${older_backups}") | xargs rm -rf
	else
		echo "Older backups can not be deleted to preserve existing backups. Please try again."
	fi
	
}

uploadToAws() {
	# Backup if enabled
	if [[ -n "$(./get_env.sh APP_S3_BACKUP)" && $(./get_env.sh APP_S3_BACKUP) == "true" ]]; then

		FILE_NAME="$(echo $1 | rev | cut -d "/" -f1-3 | rev | sed -e 's/\//_/g')"
		FOLDER_PATH="$(echo $1 | rev | cut -d "/" -f2- | cut -d "/" -f1-2 | rev)"
		FILE_PATH=$1

		s3cmd put "${FILE_PATH}" s3://"$(./get_env.sh APP_S3_LOCATION)"/${FOLDER_PATH}/
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

sendSlackNotification() {
	BACKUP_STATUS=$1		# Here backup status means backup or upload status
	TYPE=$2
	MESSAGE=$3
	DATE=$4

	# Send if enabled
	if [[ -n "$(./get_env.sh APP_SLACK_NOTIF)" && $(./get_env.sh APP_SLACK_NOTIF) == "true" ]]; then

		# Check whether to send a notification for success event
		if [[ "$BACKUP_STATUS" -eq 0 ]]; then

			if [[ -z "$(./get_env.sh APP_HIDE_SUCCESS_SLACK_NOTIF)" || "$(./get_env.sh APP_HIDE_SUCCESS_SLACK_NOTIF)" != "true" ]]; then
				./slackhook.sh "${BACKUP_STATUS}" "${TYPE}" "${MESSAGE}" "${DATE}"
			fi

		else

			./slackhook.sh "${BACKUP_STATUS}" "${TYPE}" "${MESSAGE}" "${DATE}"

		fi
	
	fi
}

main "$@"

excludeDirectory

for i in ${APP_LOCATION[@]}; do
	app_name=$(getAppName $i)	# get App Name (Last name of full path)

	b=$(./get_env.sh APP_BACKUP_LOCATION)/${app_name}  	# This contains backup path with app name
	BACKUP_LOCATION=$b/${FOLDER_DATE_FORMAT}			# This contains backup path with app name and folder 
	mkdir -p ${BACKUP_LOCATION}

	BACKUP_LOCATION_WITH_FILE="${BACKUP_LOCATION}/${FILE_DATE_FORMAT}.tar.gz";
	FILE_NAME="$(echo ${BACKUP_LOCATION_WITH_FILE} | rev | cut -d "/" -f1-3 | rev | sed -e 's/\//_/g')"
	
	tar -czvf ${BACKUP_LOCATION_WITH_FILE} ${exclude_flags} -C $i .		# tar as relative path
	BACKUP_STATUS=$?

	MESSAGE=""
	if [[ ${BACKUP_STATUS} -eq 0 ]]; then
		MESSAGE="${FILE_NAME} successully backed up";
	else
		MESSAGE="Failed to backup ${FILE_NAME}";
	fi
	sendSlackNotification "${BACKUP_STATUS}" "app" "${MESSAGE}" ""

	if [[ ${BACKUP_STATUS} -eq 0 ]]; then
		uploadToAws "${BACKUP_LOCATION_WITH_FILE}"
	fi

	purgeOldBackups "$b"
done
