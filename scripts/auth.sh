#!/bin/sh

docker_host=$(echo "$1" | base64 -d): shift
data=$(echo "$1" | base64 -d); shift
container=$(echo "$1" | base64 -d); shift
key=$(echo "$1" | base64 -d); shift
expire=$(echo "$1" | base64 -d); shift

export DOCKER_HOST=$docker_host

result=$(/usr/local/bin/docker run --rm --cap-drop=all -u 1000:1000 -e FLIGHT_DATA="$data" "$container" flight_auth verify "$key" --expire "$expire")
code=$?

result=$(echo "$result" | base64)
echo '{"result": "'$result'", "code": '$code'}'
