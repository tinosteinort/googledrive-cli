#!/usr/bin/env bash

set -eu

CONFIG_DIR=~/.googledrive-cli
CONFIG_FILE="$CONFIG_DIR/.configrc"
REFRESH_TOKEN_FILE="$CONFIG_DIR/.refresh_token"
CLIENT_ID=${CLIENT_ID:-""}
CLIENT_SECRET=${CLIENT_SECRET:-""}
ACCESS_TOKEN=""
FILE_NOT_EXIST="-"

source $CONFIG_FILE

function main() {
  COMMAND=${1:-""}
  if [[ -z $COMMAND ]]
  then
    gdrive_help
    exit 1
  fi

  FUNCTION="gdrive_$COMMAND"

  "$FUNCTION" "${@:2}"
}

function gdrive_login() {
  ensure_config
  store_refresh_token
}

function gdrive_logout() {
  delete_refresh_token
}

function gdrive_upload() {
  file_to_upload="$1"

  ensure_config
  ensure_refresh_token

  fileid=$(get_fileid_by_filename "$file_to_upload")
  if [[ $fileid == "$FILE_NOT_EXIST" ]]
  then
    echo "create file"
    create_file "$file_to_upload"
  else
    echo "update file"
    update_file "$file_to_upload" "$fileid"
  fi
}

function gdrive_list() {

  ensure_config
  ensure_refresh_token

  access_token=$(get_access_token)

  curl -X GET -sSL \
    -H "Authorization: Bearer $access_token" \
    "https://www.googleapis.com/drive/v3/files"
}

function gdrive_help() {
  echo "Usage:"
  echo "  gdrive <Command>"
  echo ""
  echo "Commands:"
  echo "  login"
  echo "  logout"
  echo "  upload <filename>"
  echo "  list"
  echo "  help"
}

function store_refresh_token() {
  scope="openid%20https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive.file"
  url="https://accounts.google.com/o/oauth2/v2/auth?client_id=$CLIENT_ID&response_type=code&scope=$scope&access_type=offline&redirect_uri=urn:ietf:wg:oauth:2.0:oob"
  echo "open in browser and get auth code:"
  echo "$url"

  echo -n "enter auth code: "
  read -r auth_code

  token_response=$(curl -fsSL \
      -d client_id="$CLIENT_ID" \
      -d client_secret="$CLIENT_SECRET" \
      -d code="$auth_code" \
      -d redirect_uri=urn:ietf:wg:oauth:2.0:oob \
      -d grant_type=authorization_code \
      https://oauth2.googleapis.com/token)

  refresh_token=$(echo "$token_response" | jq -r '.refresh_token')
  echo "$refresh_token" > "$REFRESH_TOKEN_FILE"
}

function delete_refresh_token() {
  if [[ -f $REFRESH_TOKEN_FILE ]]
  then
    rm "$REFRESH_TOKEN_FILE"
  fi
}

function get_access_token() {
  if [[ -z $ACCESS_TOKEN ]]
  then
    ACCESS_TOKEN=$(retrieve_access_token)
  fi
  echo "$ACCESS_TOKEN"
}

function retrieve_access_token() {
  refresh_token=$(<"$REFRESH_TOKEN_FILE")

  token_response=$(curl -sSL \
    -d client_id="$CLIENT_ID" \
    -d client_secret="$CLIENT_SECRET" \
    -d refresh_token="$refresh_token" \
    -d grant_type="refresh_token" \
    https://oauth2.googleapis.com/token)

  echo "$token_response" | jq -r '.access_token'
}

function create_file() {
  file_to_upload="$1"
  mime_type=$(get_mime_type "$file_to_upload")

  access_token=$(get_access_token)

  curl -X POST -sSL \
    -H "Authorization: Bearer $access_token" \
    -H "Content-Type: multipart/related" \
    -F "metadata={name :'${file_to_upload}'};type=application/json;charset=UTF-8" \
    -F "media=@\"${file_to_upload}\";type=\"$mime_type\"" \
    "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"
}

function update_file() {
  file_to_update="$1"
  id_of_file_to_update="$2"
  mime_type=$(get_mime_type "$file_to_upload")

  access_token=$(get_access_token)

  curl -X PATCH -sSL \
    -H "Authorization: Bearer $access_token" \
    -H "Content-Type: multipart/related" \
    -F "metadata={name :'${file_to_update}'};type=application/json;charset=UTF-8" \
    -F "media=@\"${file_to_update}\";type=\"$mime_type\"" \
    "https://www.googleapis.com/upload/drive/v3/files/$id_of_file_to_update?uploadType=multipart"
}

function get_mime_type() {
  file_to_update="$1"
  file --mime-type "$file_to_upload" | cut -d' ' -f 2
}

function get_fileid_by_filename() {
  name_of_file="$1"

  ensure_config
  ensure_refresh_token

  access_token=$(get_access_token)

  fileid=$(curl -X GET -sSL \
    -H "Authorization: Bearer $access_token" \
    "https://www.googleapis.com/drive/v3/files" | jq -r ".files[] | select (.name=\"$name_of_file\") | .id")

  if [[ $(echo "$fileid" | xargs | wc -w) == "0" ]]
  then
    echo "$FILE_NOT_EXIST"
    return
  elif [[ ! $(echo "$fileid" | xargs | wc -w) == "1" ]]; then
    echo "No or no unique file: $name_of_file. Cannot continue."
    exit 1
  fi

  echo "$fileid"
}

function ensure_config() {
  if [[ -z $CLIENT_ID ]]
  then
    echo "CLIENT_ID not set. Check $CONFIG_FILE"
    exit 1
  fi

  if [[ -z $CLIENT_SECRET ]]
  then
    echo "CLIENT_SECRET not set. Check $CONFIG_FILE"
    exit 1
  fi
}

function ensure_refresh_token() {
  local token
  if [[ -f $REFRESH_TOKEN_FILE ]]
  then
    token=$(<"$REFRESH_TOKEN_FILE")
  else
    token=""
  fi

  if [[ -z $token ]]
  then
    echo "Not logged in. Execute"
    echo " gdrive login"
    exit 1
  fi
}

main "$@"
