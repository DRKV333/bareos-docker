#!/bin/bash

export CONF_PATH="${CONF_PATH:-/etc/bareos/bareos-sd.d/env/env.conf}"
mkdir -p $(dirname "$CONF_PATH")


if [ -z "$CONF_NO_DEFAULTS" ]; then
    source conf-defaults.sh

    export DEV1_NAME="${DEV1_NAME:-FileStorage}"
    export DEV1_MEDIA_TYPE="${DEV1_MEDIA_TYPE:-File}"
    export DEV1_ARCHIVE_DEVICE="${DEV1_ARCHIVE_DEVICE:-/var/lib/bareos/storage}"
    export DEV1_LABEL_MEDIA="${DEV1_LABEL_MEDIA:-yes}"
    export DEV1_RANDOM_ACCESS="${DEV1_RANDOM_ACCESS:-yes}"
    export DEV1_AUTOMATIC_MOUNT="${DEV1_AUTOMATIC_MOUNT:-yes}"
    export DEV1_REMOVABLE_MEDIA="${DEV1_REMOVABLE_MEDIA:-no}"
    export DEV1_ALWAYS_OPEN="${DEV1_ALWAYS_OPEN:-no}"
fi

if [ -z "$CONF_NO_ENV" ]; then
    echo "Creating config..."
    
    perl conf-builder.pl \
        "(Storage:STO){}" \
        "(Director:DIR)+{}" \
        "(NDMP:NDMP)+{}" \
        "(Device:DEV)+{}" \
        "(Autochanger:ACH)+{}" \
        "(Messages:MSG)+{}" \
        >$CONF_PATH
fi

echo "Running start command..."

exec "$@"
