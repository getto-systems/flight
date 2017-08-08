docker_wrapper_map flight getto/flight:0.0.0-pre6

docker_wrapper_server_env_flight(){
  docker_wrapper_env -p ${LABO_PORT_PREFIX}81:80 -eDOCKER_HOST=${DOCKER_HOST}
}
