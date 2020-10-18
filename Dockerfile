# syntax=docker/dockerfile:experimental

########
# base #
########
FROM debian:10-slim AS base

ARG REPO=http://download.bareos.org/bareos/release/latest/Debian_10

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

RUN rm -f /etc/apt/apt.conf.d/docker-clean \
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt --mount=type=cache,target=/var/cache/debconf \
    apt-get update && apt-get upgrade -y && apt-get install --no-install-recommends -y \
    curl lsb-base

RUN echo "deb ${REPO} /" > /etc/apt/sources.list.d/bareos.list \
    && curl -LR "${REPO}/Release.key" -o /etc/apt/trusted.gpg.d/bareos.gpg.asc

##########
# common #
##########
FROM base AS common

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt --mount=type=cache,target=/var/cache/debconf \
    apt-get update && apt-get install --no-install-recommends -y \
    bareos-common lsof

ADD scripts/common/* .

##############
# bareos-dir #
##############
FROM common AS dir

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt --mount=type=cache,target=/var/cache/debconf \
    echo "bareos-database-common bareos-database-common/dbconfig-install boolean false" | debconf-set-selections \
    && apt-get update && apt-get install --no-install-recommends -y \
    bareos-director bareos-database-postgresql \
    && rm -rf /etc/bareos/bareos-dir.d/*

EXPOSE 9101

ADD scripts/dir/* .
ENTRYPOINT [ "./entrypoint.sh" ]
CMD [ "bareos-dir", "-u", "bareos", "-g", "bareos", "-f", "-m" ]

#############
# bareos-sd #
#############
FROM common AS sd

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt --mount=type=cache,target=/var/cache/debconf \
    apt-get update && apt-get install --no-install-recommends -y \
    bareos-storage \
    && rm -rf /etc/bareos/bareos-sd.d/*

VOLUME [ "/var/lib/bareos/storage" ]

EXPOSE 9103

ADD scripts/sd/* .
ENTRYPOINT [ "./entrypoint.sh" ]
CMD [ "bareos-sd", "-u", "bareos", "-g", "bareos", "-f", "-m" ]

###################
# bareos-bconsole #
###################
FROM common AS bconsole

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt --mount=type=cache,target=/var/cache/debconf \
    apt-get update && apt-get install --no-install-recommends -y \
    bareos-bconsole \
    && rm -rf /etc/bareos/bconsole.conf

ADD scripts/bconsole/* .
ENTRYPOINT [ "./entrypoint.sh" ]
CMD [ "bconsole" ]

#########
# webui #
#########
FROM base AS webui

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt --mount=type=cache,target=/var/cache/debconf \
    apt-get update && apt-get install --no-install-recommends -y \
    bareos-webui

EXPOSE 80

ADD scripts/webui-sites/* /etc/apache2/sites-available
RUN a2dissite 000-default.conf && a2ensite webui.conf

ADD scripts/webui/* .
ENTRYPOINT [ "./entrypoint.sh" ]
CMD [ "apachectl", "-D", "FOREGROUND" ]