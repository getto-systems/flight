#!/bin/bash

docker_host=$(echo "$1" | base64 -d); shift
data=$(echo "$1" | base64 -d); shift
json=$(echo "$1" | base64 -d); shift

export DOCKER_HOST=$docker_host

image=$(echo "$json" | jq ".image" -r)

result=$(/usr/local/bin/docker run --rm --cap-drop=all -u 1000:1000 -e FLIGHT_DATA="$data" "$image" flight_auth verify "$json")
code=$?

result=$(echo "$result" | base64)
echo '{"result": "'$result'", "code": '$code'}'
