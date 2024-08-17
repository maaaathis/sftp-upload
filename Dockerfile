FROM alpine:latest

RUN chmod 777 entrypoint.sh

RUN apk add --no-cache git git-lfs openssh

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]