#!/bin/sh

docker_host=$1: shift
data=$1; shift
container=$1; shift
key=$1; shift
expire=$1; shift

docker_host=$(echo "$docker_host" | base64 -d)
data=$(echo "$data" | base64 -d)
container=$(echo "$container" | base64 -d)
key=$(echo "$key" | base64 -d)
expire=$(echo "$expire" | base64 -d)

export DOCKER_HOST=$docker_host

result=$(/usr/local/bin/docker run --rm --cap-drop=all -u 1000:1000 -e FLIGHT_DATA="$data" "$container" flight_auth verify "$key" --expire "$expire")
code=$?

result=$(echo "$result" | base64)
echo '{"result": "'$result'", "code": '$code'}'
