#!/bin/bash

docker_host=$(echo "$1" | base64 -d); shift
volume=$(echo "$1" | base64 -d); shift
credential=$(echo "$1" | base64 -d); shift
data=$(echo "$1" | base64 -d); shift
json=$(echo "$1" | base64 -d); shift
env_file=$(echo "$1" | base64 -d); shift

export DOCKER_HOST=$docker_host

if [ -f "$env_file" ]; then
  env_param="--env-file $env_file"
fi

image=$(echo "$json" | jq ".image" -r)

_ifs=$IFS
IFS=$'\n'
for arg in $(echo "$json" | jq ".command[]" -rc); do
  IFS=$_ifs
  args[${#args[@]}]="$arg"
done

mount=/work
work=$mount/app

result=$(/usr/local/bin/docker run --rm --cap-drop=all -u 1000:1000 -v $volume:$mount -w $work $env_param -e FLIGHT_CREDENTIAL="$credential" -e FLIGHT_DATA="$data" "$image" "${args[@]}")
code=$?

result=$(echo "$result" | base64)
echo '{"result": "'$result'", "code": '$code'}'
