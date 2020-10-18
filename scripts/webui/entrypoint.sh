#!/bin/bash

if [ -z "$CONF_NO_ENV" ]; then
    echo "Creating config..."
    perl ini-builder.pl "DIR" >/etc/bareos-webui/directors.ini
fi

echo "Running start command..."

exec "$@"
