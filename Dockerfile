FROM alpine:latest

RUN apk update
RUN apk add --no-cache openssh

COPY entrypoint.sh /entrypoint.sh

RUN chmod 777 entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]