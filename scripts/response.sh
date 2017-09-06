#!/bin/sh

docker_host=$1: shift
data=$1; shift
line=$1; shift
env_file=$1; shift

docker_host=$(echo "$docker_host" | base64 -d)
data=$(echo "$data" | base64 -d)
line=$(echo "$line" | base64 -d)
env_file=$(echo "$env_file" | base64 -d)

export DOCKER_HOST=$docker_host

if [ -f "$env_file" ]; then
  env_param="--env-file $env_file"
fi

result=$(/usr/local/bin/docker run --rm --cap-drop=all -u 1000:1000 $env_param -e FLIGHT_DATA="$data" $line)
code=$?

result=$(echo "$result" | base64)
echo '{"result": "'$result'", "code": '$code'}'
