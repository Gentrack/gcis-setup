#!/bin/bash
GREEN_COLOR="\e[0;32m"
YELLOW_COLOR="\e[1;33m"
RED_COLOR="\e[0;31m"
RESET_COLOR="\e[0m"

warn() {
  echo -e >&2 "$@"
}

die() {
  echo >&2 "$@"
  exit 1
}

# add additional prompt(s) here
FORM_FIELDS=(
  "Enter data sovereignty region AU or UK ${YELLOW_COLOR}*${RESET_COLOR}"
  "Enter Gateway Host Name - Fully qualified domain name of the Data Gateway server. This will be used for certificates that are automatically generated ${YELLOW_COLOR}*${RESET_COLOR}"
  "Will you be using a private CA signed certificiate yes or no"
  "Enter path CA signed .pem file"
  "Enter node_extra_ca_certs path"
  "Will you be using a self signed certificate in Core systems"
  "Enable Sumologic collectors yes or no"
  "Enter Sumologic Access Id"
  "Enter Sumologic Access Key"
  "Enter Sumologic Collector Name"
  "Enable Datadog yes or no"
  "Enter Datadog API Key"
  "Enter Datadog Hostname"
)

# add additional prompt(s) here
# a hashmap/associative array to get the value of FORM_FIELD_VALUES by variable name enum
declare -A FORM_FIELD_ENUM=(
  [region]=0
  [gateway_dns]=1
  [is_private_ca]=2
  [path_ca]=3
  [node_extra_ca_certs]=4
  [is_self_signed]=5
  [is_sumologic]=6
  [sumologic_access_id]=7
  [sumologic_access_key]=8
  [sumologic_collector_name]=9
  [is_datadog]=10
  [datadog_api_key]=11
  [datadog_hostname]=12
)

# creates hashmap/associative array where the key is the index of FORM_FIELDS and stores the user inputs
declare -A FORM_FIELD_VALUES
for form_field_key in ${!FORM_FIELDS[@]}; do
  FORM_FIELD_VALUES[$form_field_key]=""
done

# use stored variables, if exists.
STORE_FORM_FIELD_VALUES_FILE="setup-gateway-variables.txt"
source "${STORE_FORM_FIELD_VALUES_FILE}" 2> /dev/null
STORE_LOGS="setup-gateway-logs.txt"

#######################################
# Retrieves the value by using variable names defined in FORM_FIELD_ENUM
# Globals:
#   FORM_FIELD_ENUM
#   FORM_FIELD_VALUES
# Arguments:
#   String variable name
# Outputs:
#   String value
#######################################
function get_form_value_by_var() {
  echo "${FORM_FIELD_VALUES[${FORM_FIELD_ENUM[$1]}]}"
}

#######################################
# Bash user interface for Gateway Setup
# Globals:
#   FORM_FIELD_VALUES
# Arguments:
#   None
# Outputs:
#   None
#######################################
function user_interface() {
  #######################################
  # Form with no restrictions.
  # Globals:
  #   FORM_FIELD_VALUES
  # Arguments:
  #   String prompt
  #   Number index
  # Outputs:
  #   User's input text
  #######################################
  function free_form_input() {
    while true; do
      read -p "$(echo -e "$1 (Q/q Quit): ")" user_input_free_form_field
      case $user_input_free_form_field in
        Q | q) 
          echo "${FORM_FIELD_VALUES["$2"]}"
          break;;
        *)
          echo "$user_input_free_form_field"
          break;;
      esac
    done
  }
  
  #######################################
  # Region form only accepting AU or UK regions.
  # Globals:
  #   FORM_FIELD_VALUES
  # Arguments:
  #   String prompt
  #   Number index
  # Outputs:
  #   User's input text in lowercase
  #######################################
  function region_input() {
    while true; do
      read -p "$(echo -e "$1 (AU/au/Uk/uk) (Q/q Quit): ")" user_input_region 
      user_input_region=$(echo "$user_input_region" | tr '[:upper:]' '[:lower:]') # converts input to lowercase
      case $user_input_region in
        uk | au) 
          echo "https://api-${user_input_region}.integration.gentrack.cloud"
          break;;
        q) 
          echo "${FORM_FIELD_VALUES["$2"]}"
          break;;
        *) warn "${YELLOW_COLOR}Please enter a valid region (AU or UK)${RESET_COLOR}" ;;
      esac
    done
  }
  
  #######################################
  # Region form that only accepts AU or UK regions.
  # Globals:
  #   FORM_FIELD_VALUES
  # Arguments:
  #   String prompt
  #   Number index
  # Outputs:
  #   User's input text
  #######################################
  function yes_no_input() {
    while true; do
      read -p "$1 (y/N) (Q/q Quit): " user_input_yes_no
      user_input_yes_no=$(echo "$user_input_yes_no" | tr '[:upper:]' '[:lower:]') # converts input to lowercase
      case $user_input_yes_no in
        yes | y )
          echo "true"
          break;;
        no | n | "")
          echo "false"
          break;;
        q) 
          echo "${FORM_FIELD_VALUES["$2"]}"
          break;;
        *) warn "${YELLOW_COLOR}Please enter a yes or no${RESET_COLOR}" ;;
      esac
    done
  }
  
  #######################################
  # CA path form that only accepts directories with *.pem or *.crt files
  # Globals:
  #   FORM_FIELD_VALUES
  # Arguments:
  #   String prompt
  #   Number index
  # Outputs:
  #   User's input text in lowercase
  #######################################
  function path_ca_input() {
    local variableType=$(get_index "$2")
    local requiredFileType
    case "$variableType" in
      path_ca) requiredFileType='.pem';;
      node_extra_ca_certs) requiredFileType='.crt';;
    esac
    if [ "$(get_form_value_by_var is_private_ca)" == false ] || [ -z "$(get_form_value_by_var is_private_ca)" ]; then
      return
    fi
    while true; do
      read -p "$1 (*$requiredFileType) (Q/q Quit): " user_input_path_ca
      case $user_input_path_ca in
        q) 
          echo "${FORM_FIELD_VALUES["$2"]}"
          break
  	;;
        *)
          if [[ $user_input_path_ca != *$requiredFileType* ]]; then
            warn "Only ${YELLOW_COLOR}$requiredFileType${RESET_COLOR} is a valid filetype."
            continue
          fi
          if [ -f "$user_input_path_ca" ]; then
            echo "$user_input_path_ca"
            break
          else
            warn "${YELLOW_COLOR}$user_input_path_ca does not exist.${RESET_COLOR}"
          fi
          ;;
      esac
    done
  }
  
  #######################################
  # used for required sumologic fields
  # Globals:
  #   FORM_FIELD_VALUES
  # Arguments:
  #   String prompt
  #   Number index
  # Outputs:
  #   User's input text
  #######################################
  function sumologic_required_input() {
    if [ "$(get_form_value_by_var is_sumologic)" == false ] || [ -z "$(get_form_value_by_var is_sumologic)" ]; then
      return
    fi
    echo $(free_form_input "$1" "$2")
  }
  
  #######################################
  # used for required datadog fields
  # Globals:
  #   FORM_FIELD_VALUES
  # Arguments:
  #   String prompt
  #   Number index
  # Outputs:
  #   User's input text
  #######################################
  function datadog_required_input() {
    if [ "$(get_form_value_by_var is_datadog)" == false ] || [ -z "$(get_form_value_by_var is_datadog)" ]; then
      return
    fi
    echo $(free_form_input "$1" "$2")
  }
  
  #######################################
  # Returns the index given a value
  # Globals:
  #   FORM_FIELD_VALUES
  # Arguments:
  #   String value
  #   Array value
  # Outputs:
  #   Index
  #######################################
  function get_index() {
    local array=("$@")
    for i in "${!FORM_FIELD_ENUM[@]}"; do
       if [[ "${FORM_FIELD_ENUM[$i]}" = "$1" ]]; then
           echo "${i}";
       fi
    done
  }

  #######################################
  # Main form loop
  # Globals:
  #   GREEN_COLOR
  #   YELLOW_COLOR
  #   RESET_COLOR
  #   FORM_FIELDS
  #   FORM_FIELD_ENUM
  #   FORM_FIELD_VALUES
  #   STORE_FORM_FIELD_VALUES_FILE
  # Arguments:
  #   None
  # Outputs:
  #   None
  #######################################
  function form_loop() {
    # add additional prompt(s) here
    local form_functions=(
      region_input
      free_form_input
      yes_no_input
      path_ca_input 
      path_ca_input
      yes_no_input
      yes_no_input
      sumologic_required_input
      sumologic_required_input
      sumologic_required_input
      yes_no_input
      datadog_required_input
      datadog_required_input
    )

    #######################################
    # Set form field value by key/index
    # Globals:
    #   FORM_FIELDS
    #   FORM_FIELD_VALUES
    # Locals:
    #   form_functions
    # Arguments:
    #   key/index of FORM_FIELD_VALUES
    # Outputs:
    #   None
    #######################################
    function set_form_field_by_key() {
      FORM_FIELD_VALUES["$1"]=$(${form_functions["$1"]} "${FORM_FIELDS["$1"]}" "$1")
    }

    while true ; do
      clear -x
      echo
      echo "Gentrack Data Gateway Summary"
      echo -e "Fields tagged with ${YELLOW_COLOR}*${RESET_COLOR} are required"
      for form_field_key in ${!FORM_FIELDS[@]}; do
        # do not show the fields that dependant on whether the user selected no
        if [ "$(get_form_value_by_var is_private_ca)" == "false" ] || [ -z "$(get_form_value_by_var path_ca)" ] ; then
          case $form_field_key in 
            ${FORM_FIELD_ENUM[path_ca]}) continue ;;
            ${FORM_FIELD_ENUM[node_extra_ca_certs]}) continue ;;
          esac
        fi
        if [ "$(get_form_value_by_var is_sumologic)" == "false" ] || [ -z "$(get_form_value_by_var is_sumologic)" ] ; then
          case $form_field_key in
            ${FORM_FIELD_ENUM[sumologic_access_id]}) continue ;; 
            ${FORM_FIELD_ENUM[sumologic_access_key]}) continue ;;
            ${FORM_FIELD_ENUM[sumologic_collector_name]}) continue ;; 
          esac
        fi
        if [ "$(get_form_value_by_var is_datadog)" == "false" ] || [ -z "$(get_form_value_by_var is_datadog)" ] ; then
          case $form_field_key in
            ${FORM_FIELD_ENUM[datadog_api_key]}) continue ;; 
            ${FORM_FIELD_ENUM[datadog_hostname]}) continue ;;
          esac
        fi
        echo -e "${FORM_FIELDS[$form_field_key]} ($form_field_key) ${GREEN_COLOR}${FORM_FIELD_VALUES[$form_field_key]}${RESET_COLOR}"
      done
      echo -e "Type '${GREEN_COLOR}confirm${RESET_COLOR}' to proceed"
      echo
      read -p "To edit all fields, press ENTER or select a field to edit using the corresponding number: " user_input
      echo
      case $user_input in
        "")
          for form_function_index in ${!form_functions[@]}; do
            set_form_field_by_key $form_function_index
          done
          ;;
        [0-9]*)
          FORM_FIELD_VALUES["$user_input"]=$(${form_functions["$user_input"]} "${FORM_FIELDS["$user_input"]}" "$user_input")
          # shows required fields of yes selection for continuity
          local form_field_key
          if [[ $(get_form_value_by_var is_private_ca) == "true" && ${FORM_FIELD_ENUM[is_private_ca]} == "$user_input" ]]; then
            form_field_key=${FORM_FIELD_ENUM[path_ca]}
            set_form_field_by_key $form_field_key
            form_field_key=${FORM_FIELD_ENUM[node_extra_ca_certs]}
            set_form_field_by_key $form_field_key
          fi
          if [[ $(get_form_value_by_var is_sumologic) == "true" && ${FORM_FIELD_ENUM[is_sumologic]} == "$user_input" ]]; then
            form_field_key=${FORM_FIELD_ENUM[sumologic_access_id]}
            set_form_field_by_key $form_field_key
            form_field_key=${FORM_FIELD_ENUM[sumologic_access_key]}
            set_form_field_by_key $form_field_key
            form_field_key=${FORM_FIELD_ENUM[sumologic_collector_name]}
            set_form_field_by_key $form_field_key
          fi
          if [[ $(get_form_value_by_var is_datadog) == "true" && ${FORM_FIELD_ENUM[is_datadog]} == "$user_input" ]]; then
            form_field_key=${FORM_FIELD_ENUM[datadog_api_key]}
            set_form_field_by_key $form_field_key
            form_field_key=${FORM_FIELD_ENUM[datadog_hostname]}
            set_form_field_by_key $form_field_key
          fi
          ;;
        confirm)
          if [[ ! -z $(get_form_value_by_var region) ]] && \
          [[ ! -z $(get_form_value_by_var gateway_dns) ]] && \
          [[ $(get_form_value_by_var is_private_ca) == "false" || -z $(get_form_value_by_var is_private_ca) || $(get_form_value_by_var is_private_ca) == "true" && ! -z $(get_form_value_by_var path_ca) && ! -z $(get_form_value_by_var node_extra_ca_certs) ]] && \
          [[ $(get_form_value_by_var is_sumologic) == "false" || -z $(get_form_value_by_var is_sumologic) || $(get_form_value_by_var is_sumologic) == "true" && ! -z $(get_form_value_by_var sumologic_access_id) && ! -z $(get_form_value_by_var sumologic_access_key) ]] && \
          [[ $(get_form_value_by_var is_datadog) == "false" || -z $(get_form_value_by_var is_datadog) || $(get_form_value_by_var is_datadog) == "true" && ! -z $(get_form_value_by_var datadog_api_key) && ! -z $(get_form_value_by_var datadog_hostname) ]]; then
            declare -p FORM_FIELD_VALUES > "${STORE_FORM_FIELD_VALUES_FILE}"
            echo $(date) >> "${STORE_LOGS}"
            echo -e "Storing field values into ${GREEN_COLOR}${STORE_FORM_FIELD_VALUES_FILE}${RESET_COLOR}"
            cat "${STORE_FORM_FIELD_VALUES_FILE}" >> "${STORE_LOGS}"
            break
          else
            warn "${YELLOW_COLOR}Some fields are missing. Please fill in the remaining field(s).${RESET_COLOR} (Press ENTER to continue)"
            read
          fi
          ;;
      esac
    done
  }
  
  form_loop
  
  #######################################
  # Edits the docker compose file using the form values
  # Globals:
  #   GREEN_COLOR
  #   YELLOW_COLOR
  #   RESET_COLOR
  #   FORM_FIELD_VALUES
  # Arguments:
  #   None
  # Outputs:
  #   None
  #######################################
  function edit_docker_compose() {
    local file_name="docker-compose.yml"
    if [[ -f "$(dirname "$(readlink -f $0)")/$file_name" ]]; then
      echo -e "Found ${GREEN_COLOR}$file_name${RESET_COLOR}" >> "${STORE_LOGS}"
    else
      echo -e "${YELLOW_COLOR}$file_name${RESET_COLOR} does not exist. Downloading..." >> "${STORE_LOGS}"
      curl -s https://raw.githubusercontent.com/Gentrack/gcis-setup/master/docker-compose.yml -o "$file_name"
    fi
    
    echo -e "Editing ${GREEN_COLOR}$file_name${RESET_COLOR}..." >> "${STORE_LOGS}"
    local tag_locations=(
      "index.docker.io/gentrackio/gateway:"
      "index.docker.io/gentrackio/rabbitmq:"
      "index.docker.io/gentrackio/vault:"
      "index.docker.io/gentrackio/redis:"
    )
    
    local tag
    if [[ "$(get_form_value_by_var region)" == "https://api-uk.integration.gentrack.cloud" ]]; then
      tag="PROD-UK"
    else
      tag="PROD-AU"
    fi
    for tag_location in "${tag_locations[@]}"; do
      local old_tag=$(grep -e "$tag_location" "$file_name" | sed -e "s#.*$tag_location##")
      if [[ "$old_tag" == "$tag" ]]; then
        echo -e "Tag: $tag is unchanged" >> "${STORE_LOGS}"
        break
      fi
      sed -i "s#$tag_location.*#$tag_location$tag#" "$file_name"
      local new_tag="$(grep -e "$tag_location" "$file_name" | sed -e "s#.*$tag_location##")"
      echo -e "Changing $tag_location${RED_COLOR}$old_tag${RESET_COLOR} to $tag_location${GREEN_COLOR}$new_tag${RESET_COLOR}" >> "${STORE_LOGS}"
    done
  
    # Private CA signed certificate
    if [[ "$(get_form_value_by_var is_private_ca)" == "true" ]] ; then
      local existing_bundle_ca=$(grep -e "-\ .*.pem:.*.crt:ro" "$file_name" | xargs echo)
      local node_extra_ca_certs=$(get_form_value_by_var node_extra_ca_certs)
      local path_ca=$(get_form_value_by_var path_ca)
      local bundle_ca="- $path_ca:$node_extra_ca_certs:ro"
      if [[ "$existing_bundle_ca" ]]; then
        if [[ "$existing_bundle_ca" == "$bundle_ca" ]]; then
          echo -e "CA Path: $existing_bundle_ca remains unchanged" >> "${STORE_LOGS}"
        else
          # insert user changes
          sed -i "s#-\ .*.pem:.*.crt:ro#$bundle_ca#" "$file_name"
          local old_node_extra_ca_certs=$(echo $existing_bundle_ca | sed 's#.*:\(.*\):ro.*#\1#')
          local old_path_ca=$(echo $existing_bundle_ca | sed 's#.*- \(.*\):.*:ro#\1#')
          # show the user's changes with color
          if [[ "$old_node_extra_ca_certs" != "$node_extra_ca_certs" && "$old_path_ca" != "$path_ca" ]]; then
            echo -e "Changing - ${RED_COLOR}$old_path_ca${RESET_COLOR}:${RED_COLOR}$old_node_extra_ca_certs${RESET_COLOR}:ro to - ${GREEN_COLOR}$path_ca${RESET_COLOR}:${GREEN_COLOR}$node_extra_ca_certs${RESET_COLOR}:ro" >> "${STORE_LOGS}"
          elif [[ $old_node_extra_ca_certs != $node_extra_ca_certs ]]; then
            echo -e "Changing - $old_path_ca:${RED_COLOR}$old_node_extra_ca_certs${RESET_COLOR}:ro to - $path_ca:${GREEN_COLOR}$node_extra_ca_certs${RESET_COLOR}:ro" >> "${STORE_LOGS}"
          else #[[ $old_path_ca != $path_ca ]]
            echo -e "Changing - ${RED_COLOR}$old_path_ca${RESET_COLOR}:$old_node_extra_ca_certs:ro to - ${GREEN_COLOR}$path_ca${RESET_COLOR}:$node_extra_ca_certs:ro" >> "${STORE_LOGS}"
          fi
        fi
      else
        # insert a new line
        local line_no=$(expr $(grep -n "GatewayData:/data:rw" "$file_name" | cut -f1 -d:) + 1)
        sed -i "$line_no i \      $bundle_ca" "$file_name"
        echo -e "Inserting ${GREEN_COLOR}$bundle_ca${RESET_COLOR} to ${GREEN_COLOR}line: $line_no${RESET_COLOR}" >> "${STORE_LOGS}"
      fi
      
      local existing_node_extra_ca_certs=$(grep -e "-\ node_extra_ca_certs=.*" "$file_name" | xargs echo)
      if [[ "$existing_node_extra_ca_certs" ]]; then
        if [[ "$existing_node_extra_ca_certs" == "- node_extra_ca_certs=$node_extra_ca_certs" ]]; then
          echo -e "node_extra_ca_certs: $existing_node_extra_ca_certs remains unchanged" >> "${STORE_LOGS}"
        else
          sed -i "s#-\ node_extra_ca_certs=.*.crt#- node_extra_ca_certs=$node_extra_ca_certs#" "$file_name"
          echo -e "Changing - node_extra_ca_certs=${RED_COLOR}$old_node_extra_ca_certs${RESET_COLOR} to - node_extra_ca_certs=${GREEN_COLOR}$node_extra_ca_certs${RESET_COLOR}" >> "${STORE_LOGS}"
        fi
      else
        local line_no=$(expr $(grep -n "NODE_ENV=production" "$file_name" | cut -f1 -d:) + 1)
        sed -i "$line_no i \      - node_extra_ca_certs=$node_extra_ca_certs" "$file_name"
        echo -e "Inserting ${GREEN_COLOR}- node_extra_ca_certs=$node_extra_ca_certs${RESET_COLOR} to ${GREEN_COLOR}line: $line_no${RESET_COLOR}" >> "${STORE_LOGS}"
      fi
    fi
  
    # Self signed certificate
    if [[ "$(get_form_value_by_var is_self_signed)" == "true" ]]; then
      # checks for commented line
      if [[ $(grep -e '- NODE_TLS_REJECT_UNAUTHORIZED' "$file_name" | grep -e '#') ]] ; then
        sed -i "s|#\ -\ NODE_TLS_REJECT_UNAUTHORIZED=0|- NODE_TLS_REJECT_UNAUTHORIZED=0|" "$file_name"
        echo -e "Changing ${RED_COLOR}#${RESET_COLOR} - NODE_TLS_REJECT_UNAUTHORIZED=0 to - NODE_TLS_REJECT_UNAUTHORIZED=0" >> "${STORE_LOGS}"
      fi
    else
      # check for uncommented line
      if [[ "$(grep -e '- NODE_TLS_REJECT_UNAUTHORIZED' "$file_name" | grep -v '#')" ]] ; then
        sed -i "s|-\ NODE_TLS_REJECT_UNAUTHORIZED=0|# - NODE_TLS_REJECT_UNAUTHORIZED=0|" "$file_name"
        echo -e "Changing - NODE_TLS_REJECT_UNAUTHORIZED=0 to ${GREEN_COLOR}#${RESET_COLOR} - NODE_TLS_REJECT_UNAUTHORIZED=0" >> "${STORE_LOGS}"
      fi
    fi
  
    # Sumologic monitoring service
    local line_no=$(grep -n "sumologic:" "$file_name" | cut -f1 -d:)
    local line_no_ending=$(expr $(grep -n "datadog:" "$file_name" | cut -f1 -d:) - 1)
    if [[ "$(get_form_value_by_var is_sumologic)" == "true" ]]; then
      # Uncommenting lines
      sed -i "$line_no,$line_no_ending s|.*#\(.*\)| \1|" "$file_name"
      #     - SUMO_ACCESS_ID=[insert API ID here]
      #     - SUMO_ACCESS_KEY=[insert API key here]
      #     - SUMO_COLLECTOR_NAME=GCIS Data Gateway - [insert name here]
      local old_sumologic_access_id=$(sed "s/SUMO_ACCESS_ID=\(.*\)/\1/" "$file_name")
      local old_sumologic_access_key=$(sed "s/SUMO_ACCESS_KEY=\(.*\)/\1/" "$file_name")
      local old_sumologic_collector_name=$(sed "s/SUMO_COLLECTOR_NAME=\(.*\)/\1/" "$file_name")
      # inserts changes
      sed -i "s/SUMO_ACCESS_ID=\(.*\)/SUMO_ACCESS_ID=$(get_form_value_by_var sumologic_access_id)/" "$file_name"
      sed -i "s/SUMO_ACCESS_KEY=\(.*\)/SUMO_ACCESS_KEY=$(get_form_value_by_var sumologic_access_key)/" "$file_name"
      sed -i "s/SUMO_COLLECTOR_NAME=GCIS Data Gateway - \(.*\)/SUMO_COLLECTOR_NAME=GCIS Data Gateway - $(get_form_value_by_var sumologic_collector_name)/" "$file_name"
      # display changes
      sed -n "$line_no,$line_no_ending p" "$file_name" \
        | sed "s/SUMO_ACCESS_ID=\(.*\)/SUMO_ACCESS_ID=$(printf ${GREEN_COLOR})\1$(printf ${RESET_COLOR})/" \
        | sed "s/SUMO_ACCESS_KEY=\(.*\)/SUMO_ACCESS_KEY=$(printf ${GREEN_COLOR})\1$(printf ${RESET_COLOR})/" \
        | sed "s/SUMO_COLLECTOR_NAME=GCIS Data Gateway - \(.*\)/SUMO_COLLECTOR_NAME=GCIS Data Gateway - $(printf ${GREEN_COLOR})\1$(printf ${RESET_COLOR})/ >> "${STORE_LOGS}"" 
    else
      # Checks for uncommented lines
      if [[ "$(sed -n "$line_no,$line_no_ending p" "$file_name" | grep -v "#")" ]] ; then
        sed -i "$line_no,$line_no_ending s|^ \(.*\)|  #\1|" "$file_name"
        sed -n "$line_no,$line_no_ending p" "$file_name"
      fi
    fi
    
    # Datadog
    local line_no=$(grep -n "datadog:" "$file_name" | cut -f1 -d:)
    local line_no_ending=$(grep -n "DD_HOSTNAME=" "$file_name" | cut -f1 -d:)
    if [[ "$(get_form_value_by_var is_datadog)" == "true" ]]; then
      # Uncommenting lines
      sed -i "$line_no,$line_no_ending s|.*#\(.*\)| \1|" "$file_name"
      #     - DD_API_KEY=[insert API key here]
      #     - DD_HOSTNAME=[insert name here]
      local old_datadog_api_key=$(sed "s/DD_API_KEY=\(.*\)/\1/" "$file_name")
      local old_datadog_hostname=$(sed "s/DD_HOSTNAME=\(.*\)/\1/" "$file_name")
      # inserts changes
      sed -i "s/DD_API_KEY=\(.*\)/DD_API_KEY=$(get_form_value_by_var datadog_api_key)/" "$file_name"
      sed -i "s/DD_HOSTNAME=\(.*\)/DD_HOSTNAME=$(get_form_value_by_var datadog_hostname)/" "$file_name"
      # display changes
      sed -n "$line_no,$line_no_ending p" "$file_name" \
        | sed "s/DD_API_KEY=\(.*\)/DD_API_KEY=$(printf ${GREEN_COLOR})\1$(printf ${RESET_COLOR})/" \
        | sed "s/DD_HOSTNAME=\(.*\)/DD_HOSTNAME=$(printf ${GREEN_COLOR})\1$(printf ${RESET_COLOR})/ >> "${STORE_LOGS}""
    else
      # Checks for uncommented lines
      if [[ "$(sed -n "$line_no,$line_no_ending p" "$file_name" | grep -v "#")"  ]] ; then
        sed -i "$line_no,$line_no_ending s|^ \(.*\)|  #\1|" "$file_name"
        sed -n "$line_no,$line_no_ending p" "$file_name"
      fi
    fi

    echo -e "Logging changes into ${GREEN_COLOR}${STORE_LOGS}${RESET_COLOR}"
    echo >> "${STORE_LOGS}"
  }

  edit_docker_compose

  echo
  read -p "$(echo -e "Ready to install a GCIS Data Gateway. Press ${GREEN_COLOR}ENTER${RESET_COLOR} to continue or ${YELLOW_COLOR}CTRL + C${RESET_COLOR} to quit.")" 
  echo
}

user_interface

# Install a GCIS Data Gateway on a Linux server
# Prerequisites:
# - The docker engine and docker-compose have been installed
# - A sudoer user has been set up to perform the installation
# - The user gatewayuser has been created
# - The user gatewayuser has logged in to the docker hub with a correct credentials
#
# For example, the following commands will set up the prerequisites and install a Data Gateway on an Amazon Linux 2 system
# sudo yum install docker -y
# sudo systemctl enable docker
# sudo systemctl start docker
# sudo curl -L https://github.com/docker/compose/releases/download/1.24.1/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
# sudo chmod +x /usr/local/bin/docker-compose
# sudo adduser gatewayuser --system -g docker
# sudo su - gatewayuser -c "docker login"
# sudo ./setup-gateway.sh https://api-uk.integration.gentrack.cloud gw-energise.integration.gentrack.cloud ./docker-compose.yml
#
#PLATFORM_URL=https://api-uk.integration.gentrack.cloud
#GATEWAY_DNS=gw-energise.integration.gentrack.cloud
PLATFORM_URL=$(get_form_value_by_var region)
GATEWAY_DNS=$(get_form_value_by_var gateway_dns)
DOCKER_COMPOSE_SRC="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/docker-compose.yml"
[ -f "$DOCKER_COMPOSE_SRC" ] || die "File $DOCKER_COMPOSE_SRC does not exist"

GATEWAY_USER=gatewayuser
GATEWAY_USER_HOME=/home/$GATEWAY_USER
INSTALL_DIR=$GATEWAY_USER_HOME/platform
DOCKER_COMPOSE=$INSTALL_DIR/docker-compose.yml

RABBITMQ_DEFAULT_USER=rabbitmq
# Generate a 32-character long random password for RabbitMQ
RABBITMQ_DEFAULT_PASS=$(tr </dev/urandom -dc _A-Z-a-z-0-9 | head -c32)
if [ "${#RABBITMQ_DEFAULT_PASS}" -ne "32" ]; then
  die "Failed to generate password for RabbitMQ"
fi
MESSAGE_QUEUE_URL=$RABBITMQ_DEFAULT_USER:$RABBITMQ_DEFAULT_PASS@mq
# Check to make sure the compose file has expected format
grep -E "^(\s|\t)*RABBITMQ_DEFAULT_USER:.*$" $DOCKER_COMPOSE_SRC >/dev/null || die "Couldn't find RABBITMQ_DEFAULT_USER in $DOCKER_COMPOSE_SRC"
grep -E "^(\s|\t)*RABBITMQ_DEFAULT_PASS:.*$" $DOCKER_COMPOSE_SRC >/dev/null || die "Couldn't find RABBITMQ_DEFAULT_PASS in $DOCKER_COMPOSE_SRC"
grep -E "^(\s|\t)*- MESSAGE_QUEUE=.*$" $DOCKER_COMPOSE_SRC >/dev/null || die "Couldn't find MESSAGE_QUEUE in $DOCKER_COMPOSE_SRC"
(
  # Remove dependency between docker engine and gentrack-gateway-docker if exists.
  # So gentrack-gateway-docker wouldn't auto restart after being stopped
  if [ -f /etc/systemd/system/docker.service.d/override.conf ]; then
    rm -f /etc/systemd/system/docker.service.d/override.conf
    systemctl daemon-reload
    systemctl stop docker
  fi
  systemctl start docker
  # stop and remove containers - ignore any errors
  usermod -a -G docker $(id -u -n) || die "Failed to add user to docker group"
  docker stop $(docker ps -aq) >/dev/null 2>&1
  docker rm $(docker ps -aq) >/dev/null 2>&1
  docker volume prune -f >/dev/null 2>&1
) || die "Failed to clean up dockers"

IMAGE_TAG="PROD-AU"
if [ "$PLATFORM_URL" == "https://api-uk.integration.gentrack.cloud" ]; then
  IMAGE_TAG="PROD-UK"
elif [ "$PLATFORM_URL" == "https://api-au.integration.gentrack.cloud" ]; then
  IMAGE_TAG="PROD-AU"
fi

(
  rm -rf $INSTALL_DIR &&
    mkdir -p $INSTALL_DIR &&
    cp $DOCKER_COMPOSE_SRC $DOCKER_COMPOSE &&
    sed -i "s/<tag>/${IMAGE_TAG}/g" $DOCKER_COMPOSE &&
    sed -i "s/- MESSAGE_QUEUE=.*\$/- MESSAGE_QUEUE=amqp:\/\/$MESSAGE_QUEUE_URL/g" $DOCKER_COMPOSE &&
    sed -i "s/RABBITMQ_DEFAULT_USER:.*\$/RABBITMQ_DEFAULT_USER: $RABBITMQ_DEFAULT_USER/g" $DOCKER_COMPOSE &&
    sed -i "s/RABBITMQ_DEFAULT_PASS:.*\$/RABBITMQ_DEFAULT_PASS: $RABBITMQ_DEFAULT_PASS/g" $DOCKER_COMPOSE &&
    chown $GATEWAY_USER $DOCKER_COMPOSE &&
    touch $INSTALL_DIR/http_check.yaml &&
    touch $INSTALL_DIR/key.txt &&
    # up and down to initialise named volumes
    su - $GATEWAY_USER -c "docker-compose -f $DOCKER_COMPOSE up -d" &&
    su - $GATEWAY_USER -c "docker-compose -f $DOCKER_COMPOSE down"
) || die "Failed to initialise volumes"

VAULT_CONFIG='{
  "backend": {"file": {"path": "/data/vault/file"}},
  "listener": {"tcp": {"address": "0.0.0.0:8200", "tls_cert_file": "/data/vault/cert/vault.crt", "tls_key_file": "/data/vault/cert/vault.key"}},
  "default_lease_ttl": "168h",
  "max_lease_ttl": "720h"
}'
CERT_SUBJ='/C=NZ/ST=Auckland/L=Auckland/O=Gentrack Ltd/OU=Platform/CN=integration.gentrack.cloud/emailAddress=noreply@integration.gentrack.cloud'
INSTALL_TMP=$(mktemp /tmp/platform.XXXXXXXXXX)
(
  rm $INSTALL_TMP &&
    mkdir -p $INSTALL_TMP/config &&
    tr </dev/urandom -dc 'A-Za-z0-9!"#$%&'\''()*+,-./:;<=>?@[\]^_`{|}~' | head -c 64 >$INSTALL_TMP/key.txt &&
    (
      echo platformUrl: $PLATFORM_URL
      echo hostname: $GATEWAY_DNS
    ) >$INSTALL_TMP/default.yml &&
    echo $VAULT_CONFIG >$INSTALL_TMP/config/vault.json &&
    CERT_PATH="$INSTALL_TMP/vault/cert" &&
    mkdir -p $CERT_PATH &&
    $(openssl req -x509 -nodes -newkey rsa:4096 -keyout "$CERT_PATH/vault.key" -out "$CERT_PATH/vault.crt" -days 3650 -subj "$CERT_SUBJ")
) || die "Failed to create gateway configuration"
(
  GATEWAY_CONFIG_VOL=$(docker volume ls | grep GatewayConfig | rev | cut -d ' ' -f 1 | rev) &&
    GATEWAY_CONFIG_PATH=$(docker volume inspect --format '{{ .Mountpoint }}' $GATEWAY_CONFIG_VOL) &&
    VAULT_DATA_VOL=$(docker volume ls | grep VaultData | rev | cut -d ' ' -f 1 | rev) &&
    VAULT_DATA_PATH=$(docker volume inspect --format '{{ .Mountpoint }}' $VAULT_DATA_VOL) &&
    cp $INSTALL_TMP/key.txt $INSTALL_DIR &&
    cp $INSTALL_TMP/default.yml $GATEWAY_CONFIG_PATH &&
    cp -r $INSTALL_TMP/config $VAULT_DATA_PATH/ &&
    cp -r $INSTALL_TMP/vault $VAULT_DATA_PATH/ && rm -rf $INSTALL_TMP
) || die "Failed to apply gateway configuration"

# daily job to automatically cleanup old Docker images and volumes
(
  GATEWAY_DOCKER_CLEANUP='/etc/cron.daily/docker-cleanup' &&
    echo "#!/bin/sh" | tee $GATEWAY_DOCKER_CLEANUP >/dev/null &&
    echo "docker rmi \$(docker images -qf dangling=true); true" | sudo tee -a $GATEWAY_DOCKER_CLEANUP >/dev/null &&
    chmod 700 $GATEWAY_DOCKER_CLEANUP && echo "Added daily job to automatically cleanup old Docker images"
) || die "Failed to add daily job to automatically cleanup old Docker images"

# daily job to delete old gateway logs
(
  GATEWAY_LOG_CLEANUP='/etc/cron.daily/gateway-log-cleanup' &&
    echo "#!/bin/sh" | tee $GATEWAY_LOG_CLEANUP >/dev/null &&
    echo "find /var/lib/docker/volumes/platform_GatewayData/_data/logs -name \"*.log\" -mtime +6 -exec rm {} \;" | sudo tee -a $GATEWAY_LOG_CLEANUP >/dev/null &&
    chmod 700 $GATEWAY_LOG_CLEANUP && echo "Added daily job to delete old gateway logs"
) || die "Failed to add daily job to delete old gateway logs"

# Generate http_check.yaml in platform directory for Datadog:
(
  HTTP_CHECK=$INSTALL_DIR/http_check.yaml &&
    cat >$HTTP_CHECK <<EOL
init_config:
instances:
 - name: Gentrack Data Gateway
   url: https://app:3000
   tls_ignore_warning: true
   check_certificate_expiration: true
   days_warning: 7
   days_critical: 3
   timeout: 1
EOL
) || die "Failed to generate http_check.yaml in platform directory for Datadog"

# Configure gentrack-gateway-docker.service:
(
  SYSTEMD_PATH='/etc/systemd/system'
  if [ ! -d $SYSTEMD_PATH ]; then
    echo "Unable to configure gentrack-gateway-docker.service because Systemd not exists, run docker-compose instead." &&
      su - $GATEWAY_USER -c "docker-compose -f $DOCKER_COMPOSE up -d" && echo "Success"

  else
    # docker.service override
    /bin/mkdir -p /etc/systemd/system/docker.service.d/
    DOCKER_SERVICE_OVERRIDE='/etc/systemd/system/docker.service.d/override.conf' &&
      cat >$DOCKER_SERVICE_OVERRIDE <<EOL
[Unit]
Before=gentrack-gateway-docker.service
Requires=gentrack-gateway-docker.service
EOL
    systemctl daemon-reload && echo "systemctl daemon reloaded" &&
      # gateway docker service
      GATEWAY_DOCKER_SERVICE='/etc/systemd/system/gentrack-gateway-docker.service' &&
      cat >$GATEWAY_DOCKER_SERVICE <<EOL
[Unit]
Description=Gentrack Data Gateway
After=docker.service proc-sys-fs-binfmt_misc.mount proc-sys-fs-binfmt_misc.automount
Requires=docker.service proc-sys-fs-binfmt_misc.mount proc-sys-fs-binfmt_misc.automount

[Service]
Type=simple
User=gatewayuser
Group=docker
Restart=always
ExecStart=/usr/local/bin/docker-compose -f $INSTALL_DIR/docker-compose.yml up
ExecStop=/usr/local/bin/docker-compose -f $INSTALL_DIR/docker-compose.yml down

[Install]
WantedBy=multi-user.target
EOL
    systemctl enable gentrack-gateway-docker && echo "gentrack-gateway-docker.service enabled" &&
      systemctl start gentrack-gateway-docker && echo "gentrack-gateway-docker.service started"
  fi
) || die "Failed at configuring gentrack-gateway-docker.service"
