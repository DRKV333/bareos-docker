#!/bin/bash

export CONF_PATH="${CONF_PATH:-/etc/bareos/bareos-dir.d/env/env.conf}"
mkdir -p $(dirname "$CONF_PATH")

if [ -z "$CONF_NO_DEFAULTS" ]; then
    source conf-defaults.sh
    
    export DIR_QUERY_FILE="${DIR_QUERY_FILE:-/etc/bareos/query.sql}"
    export DIR_MESSAGES="${DIR_MESSAGES:-Stdout}"

    export CAT_NAME="${CAT_NAME:-Catalog}"
    export CAT_DB_DRIVER="${CAT_DB_DRIVER:-postgresql}"
    export CAT_DB_NAME="${CAT_DB_NAME:-bareos}"

    export JOB99_NAME="${JOB99_NAME:-Restore}"
    export JOB99_TYPE="${JOB99_TYPE:-Restore}"
    export JOB99_MESSAGES="${JOB99_MESSAGES:-Director}"
    export JOB99_POOL="${JOB99_POOL:-$PL1_NAME}"
    if [ -z "$JOB99_POOL" ]; then
        echo "Pool not specified for restore job, please set PL1_NAME or JOB99_POOL."
    fi
    export JOB99_CLIENT="${JOB99_CLIENT:-$CLI1_NAME}"
    if [ -z "$JOB99_CLIENT" ]; then
        echo "Client not specified for restore job, please set CLI1_NAME or JOB99_CLIENT."
    fi
    export JOB99_FILE_SET="${JOB99_FILE_SET:-$FS1_NAME}"
    if [ -z "$JOB99_FILE_SET" ]; then
        echo "File set not specified for restore job, please set FS1_NAME or JOB99_FILE_SET."
    fi
fi

if [ -z "$CONF_NO_ENV" ]; then
    echo "Creating config..."

    perl conf-builder.pl \
        "(Director:DIR){}" \
        "(Job:JOB)+{}" \
        "(JobDefs:JOBD)+{}" \
        "(Schedule:SCH)+{}" \
        "(FileSet:FS)+{(Include:INC),(Options:INC->OPT),(Exclude:EXC)}" \
        "(Client:CLI)+{}" \
        "(Storage:STO)+{}" \
        "(Pool:PL)+{}" \
        "(Catalog:CAT){}" \
        "(Console:CON)+{}" \
        "(User:USR){}+" \
        "(Profile:PROF)+{}" \
        "(Counter:CNT)+{}" \
        "(Messages:MSG)+{}" \
        >$CONF_PATH
fi

if [ -z "$DB_NO_INIT" ]; then
    echo "Initializing database..."

    DB_SCRIPT_PATH="/usr/lib/bareos/scripts"
    DB_DATABASE_NAME=$($DB_SCRIPT_PATH/bareos-config get_database_name bareos)

    if [ ! -f "~/.pgpass" ] && [ -z "$PGPASSFILE" ] && [ -z "$DB_NO_DEFAULTS" ]; then
        export PGPASSWORD="${PGPASSWORD:-$($DB_SCRIPT_PATH/bareos-config get_database_password bareos)}"
        export PGUSER="${PGUSER:-$($DB_SCRIPT_PATH/bareos-config get_database_user bareos)}"
        export PGHOST="${PGHOST:-$CAT_DB_ADDRESS}"
    fi

    until psql -c "select 1" > /dev/null 2>&1; do
        echo "Waiting for database to come online..."
        sleep 1
    done

    if psql -lqt | cut -d \| -f 1 | grep -qw $DB_DATABASE_NAME; then
        echo "Database already exists."
    else
        $DB_SCRIPT_PATH/create_bareos_database
    fi

    if [ "$(psql -qt -d $DB_DATABASE_NAME -c "SELECT COUNT(*) FROM pg_catalog.pg_tables WHERE schemaname = 'public';")" -eq 0 ]; then
        $DB_SCRIPT_PATH/make_bareos_tables
    else
        echo "Tables already exist."
        $DB_SCRIPT_PATH/update_bareos_tables
    fi

    $DB_SCRIPT_PATH/grant_bareos_privileges
fi

echo "Starting cron..."

cron

echo "Running start command..."

exec "$@"
