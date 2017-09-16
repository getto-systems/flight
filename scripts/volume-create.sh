#!/bin/sh

docker_host=$(echo "$1" | base64 -d); shift

export DOCKER_HOST=$docker_host

result=$(/usr/local/bin/docker volume create)
code=$?

result=$(echo "$result" | base64)
echo '{"result": "'$result'", "code": '$code'}'
