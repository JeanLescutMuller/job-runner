# The boot kick's image (DESIGN §13): alpine and dbus-send (~9 MB), the script baked in.
FROM alpine:3.21.3
RUN apk add --no-cache dbus
COPY kick.sh /kick.sh
CMD ["/bin/sh", "/kick.sh"]
