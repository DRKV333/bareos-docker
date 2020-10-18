#!/bin/bash

export CONF_PATH="${CONF_PATH:-/etc/bareos/bconsole.conf}"
mkdir -p $(dirname "$CONF_PATH")

if [ -z "$CONF_NO_ENV" ]; then
    echo "Creating config..."

    perl conf-builder.pl \
        "(Director:DIR)+{}" \
        "(Console:CON)+{}" \
        >$CONF_PATH
fi

echo "Running start command..."

exec "$@"