#!/bin/sh

docker_host=$1; shift
path=$1; shift
auth=$1; shift
data=$1; shift

log=/usr/local/openresty/nginx/logs/error.log

routes=/apps/flight/routes

shell_container=alpine
auth_container=getto/flight-auth-phoenix:0.0.0-pre5

export DOCKER_HOST=$docker_host

containers_path=$routes$path/_containers
env_path=$routes$path/_env
auth_key_path=$routes$path/_auth_key
require_roles_path=$routes$path/_require_roles
error_json_path=$routes$path/_error.json
not_found_json_path=$routes$path/_not_found.json
unauthorized_json_path=$routes$path/_unauthorized.json
forbidden_json_path=$routes$path/_forbidden.json
result_json_path=$routes$path/_result.json
result_file_name_path=$routes$path/_result_file_name
cors_domain_path=$routes$path/_cors_domain

flight_main(){
  if [ ! -f $containers_path ]; then
    flight_error 404 "no route matches"
    return
  fi

  if [ -f $auth_key_path ]; then
    case `echo $auth | base64 -d` in
      Get*)
        token=${auth#Get }
        expire=600
        ;;
      Bearer*)
        token=${auth#Bearer }
        expire=86400
        ;;
    esac

    if [ -z "$token" ]; then
      flight_error 401 "unauthorized" $unauthorized_json_path 'realm=\"token_required\"'
      return
    fi

    auth_key=`cat $auth_key_path`
    role=`docker run --rm --cap-drop=all -u 1000:1000 $auth_container flight_auth verify "$auth_key" --token "$token" --expire "$expire"`
    if [ -z "$role" ]; then
      flight_error 401 "unauthorized" $unauthorized_json_path 'error=\"invalid_token\"'
      return
    fi
    if [ -f $require_roles_path ]; then
      role_matches=`grep "$role" $require_roles_path`
      if [ -z "$role_matches" ]; then
        flight_error 403 "forbidden" $forbidden_json_path 'error=\"insufficient_role\"'
        return
      fi
    fi
  fi

  volume=`docker volume create`
  work=/flight-work

  if [ ! -f $env_path ]; then
    env_param=""
  else
    env_param="--env-file $env_path"
  fi

  docker run --rm --cap-drop=all -u 1000:1000 -v ${volume}:${work} -w ${work} $shell_container /bin/sh -c 'echo '"$data"' | base64 -d > data.json'

  cat $containers_path | while read line; do
    docker run --rm --cap-drop=all -u 1000:1000 -v ${volume}:${work} -w ${work} $env_param $line > $log
    if [ "$?" != 0 ]; then
      exit 1
    fi
  done
  if [ "$?" != 0 ]; then
    flight_error 500 "server error" $error_json_path
    return
  fi

  if [ ! -f $result_file_name_path ]; then
    result_file=data.json
  else
    result_file=`cat $result_file_name_path`
  fi

  body=`docker run --rm --cap-drop=all -u 1000:1000 -v ${volume}:${work} -w ${work} $shell_container /bin/sh -c "if [ -f $result_file ]; then cat $result_file; fi" | base64`
  if [ -z "$body" ]; then
    flight_error 404 "not found" $not_found_json_path
    return
  fi

  if [ ! -f $result_json_path ]; then
    echo '{'
  else
    json=`cat $result_json_path`
    echo "${json%\}},"
  fi

  if [ -f $cors_domain_path ]; then
    echo '"access-control-allow-origin": "'`cat $cors_domain_path`'",'
  fi
  echo '"body": "'"$body"'"}'
}
flight_error(){
  status=$1; shift
  message=$1; shift
  file=$1; shift
  auth=$1; shift

  if [ -n "$auth" ]; then
    auth_param='"www-authenticate": "Bearer '$auth'",'
  fi

  if [ -f "$file" ]; then
    cat "$file"
  else
    case $path in
      /api/*)
        body=`echo '{"message": "'$message'"}' | base64`
        echo '{"status": '$status', '$auth_param' "body": "'$body'"}'
        ;;
      *)
        body=`echo "$message" | base64`
        echo '{"status": '$status', '$auth_param' "content-type": "text/plain", "body": "'$body'"}'
        ;;
    esac
  fi
}
flight_cleanup(){
  if [ -n "$volume" ]; then
    docker volume rm $volume > /dev/null
  fi
}

flight_main
flight_cleanup
