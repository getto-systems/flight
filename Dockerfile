FROM openresty/openresty:alpine

ENV DOCKER_VERSION 17.06.1-ce

RUN apk add --update \
      curl \
      sudo \
    && \
    adduser nginx -D -H && \
    curl https://download.docker.com/linux/static/stable/x86_64/docker-$DOCKER_VERSION.tgz --output /tmp/docker.tgz && \
    tar -xzf /tmp/docker.tgz -C /tmp && \
    mv /tmp/docker/docker /usr/local/bin && \
    rm -rf /tmp/docker* && \
    echo "nginx ALL=(ALL) NOPASSWD: /apps/getto/base/scripts/auth.sh" >> /etc/sudoers && \
    echo "nginx ALL=(ALL) NOPASSWD: /apps/getto/base/scripts/response.sh" >> /etc/sudoers && \
    :

COPY conf /usr/local/openresty/nginx/conf
COPY scripts /app/getto/base/scripts
