#!/bin/sh

docker_host=$(echo "$1" | base64 -d); shift
volume=$(echo "$1" | base64 -d); shift

export DOCKER_HOST=$docker_host

result=$(/usr/local/bin/docker run --rm -v flight-work:/work -v $volume:/volume busybox:latest /bin/sh -c "cp -a /work/volumes/$volume /volume/app; chown -R 1000:1000 /volume/app")
code=$?

rm -rf /work/volumes/$volume

result=$(echo "$result" | base64)
echo '{"result": "'$result'", "code": '$code'}'
