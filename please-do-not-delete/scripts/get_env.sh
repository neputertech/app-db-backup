#!/bin/bash

################################################################################
# Help                                                                         #
################################################################################
help()
{
   # Display Help
   echo "Get local .env values"
   echo
   echo "Syntax:./get_env.sh"
}

## Show help if input is -h or --help
main() {
    if [[ "$1" == "-h" || "$1" == '--help' ]] ; then
      help
      exit 0
    fi

}

main "$@"

if [[ -e .env ]]; then
  file=$(grep '^'$1'=' .env)
  echo $file | cut -d '=' -f2- | sed -e 's/"//g'
fi 