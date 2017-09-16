#!/bin/sh

docker_host=$(echo "$1" | base64 -d); shift
volume=$(echo "$1" | base64 -d); shift

export DOCKER_HOST=$docker_host

rm -rf /work/volumes/$volume
result=$(/usr/local/bin/docker volume rm "$volume")
code=$?

result=$(echo "$result" | base64)
echo '{"result": "'$result'", "code": '$code'}'
