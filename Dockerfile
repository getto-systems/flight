FROM openresty/openresty:alpine

ENV DOCKER_VERSION 17.06.1-ce

RUN apk add --update \
      curl \
      sudo \
      bash \
      jq \
    && \
    adduser nginx -D -H && \
    curl https://download.docker.com/linux/static/stable/x86_64/docker-$DOCKER_VERSION.tgz --output /tmp/docker.tgz && \
    tar -xzf /tmp/docker.tgz -C /tmp && \
    mv /tmp/docker/docker /usr/local/bin && \
    rm -rf /tmp/docker* && \
    :

COPY sudoers.d /etc/sudoers.d
COPY conf /usr/local/openresty/nginx/conf
COPY scripts /app/getto/base/scripts
