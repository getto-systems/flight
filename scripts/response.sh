#!/bin/sh

docker_host=$(echo "$1" | base64 -d); shift
credential=$(echo "$1" | base64 -d); shift
data=$(echo "$1" | base64 -d); shift
line=$(echo "$1" | base64 -d); shift
env_file=$(echo "$1" | base64 -d); shift

export DOCKER_HOST=$docker_host

if [ -f "$env_file" ]; then
  env_param="--env-file $env_file"
fi

result=$(/usr/local/bin/docker run --rm --cap-drop=all -u 1000:1000 $env_param -e FLIGHT_CREDENTIAL="$credential" -e FLIGHT_DATA="$data" $line)
code=$?

result=$(echo "$result" | base64)
echo '{"result": "'$result'", "code": '$code'}'
