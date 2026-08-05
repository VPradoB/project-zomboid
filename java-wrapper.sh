#!/bin/sh
exec "${BOX64_BIN:-/usr/bin/box64}" /opt/zomboid-server/jre64/bin/java "$@"
