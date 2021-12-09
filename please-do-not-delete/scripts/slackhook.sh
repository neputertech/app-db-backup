#!/bin/bash

################################################################################
# Help                                                                         #
################################################################################
help()
{
   # Display Help
   echo "Easily notify to slack channels"
   echo
   echo "Syntax:./slackhook.sh 0 database 'Backup Notification' 'date'"
   echo "Arguments:"
   echo "\$1   status (0,1) [0=success, 1=failed] Default: 0"
   echo "\$2   type (database,app,aws) Default: database"
   echo "\$3   message Default: Backup Notification"
   echo "\$4   Date Default: current"
}

## Show help if input is -h or --help
main() {
    if [[ "$1" == "-h" || "$1" == '--help' ]] ; then
      help
      exit 0
    fi
}

STATUS=$(if [[ ${1} -eq 0 ]]; then echo "Complete"; else echo "Incomplete"; fi)
DATE=${4:-$(date '+%b %d, %k:%M')}
case "$2" in

  database)
    TYPE="Database"
    ;;

  app)
    TYPE="App"
    ;;

  aws)
    TYPE="Aws"
    ;;

  alert)
    TYPE="Alert!!!"
    ;;

  *)
    TYPE="Database"
    ;;
esac

MESSAGE="${3:-"Backup Notifcation"}"
HOOK="$(./get_env.sh SLACK_HOOK)"

replaceWhiteSpace() {
    echo $1 | sed 's|[[:space:]]|\\\\n|g';   
}

createSedExpression() {

    declare -a keys;
    keys+=( "{{MESSAGE}}")
    keys+=( "{{HOST}}")
    keys+=( "{{STATUS}}" )
    keys+=( "{{TYPE}}" )
    keys+=( "{{DATE}}" )

    declare -A values;      
    values["{{MESSAGE}}"]=$(replaceWhiteSpace "${MESSAGE}"); 
    values["{{HOST}}"]=$(replaceWhiteSpace "$(./get_hostname.sh hostname) \[$(./get_hostname.sh pub)\]"); 
    values["{{STATUS}}"]="$(replaceWhiteSpace "${STATUS}")"; 
    values["{{TYPE}}"]="$(replaceWhiteSpace "${TYPE}")"; 
    values["{{DATE}}"]="$(replaceWhiteSpace "${DATE}")"; 

    for i in "${keys[@]}"
    do
        sed_flags="${sed_flags} -e s/${i}/${values[$i]}/g"
    done

    echo ${sed_flags}
}

payload=$(<slackpayload.json)
FINAL="$(echo ${payload} | sed -e $(createSedExpression))"
payload="$(echo ${FINAL})"

main "$@"
  
curl -X POST -H 'Content-type: application/json' -d "${payload}" ${HOOK}

#find ./ -name "*.sh" -exec chmod +x {} \;
# curl -X POST -H 'Content-type: application/json' -d @slackpayload.json ${HOOK}
