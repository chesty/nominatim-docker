#!/bin/sh

set -e

if [ -f /usr/local/etc/osm-config.sh ]; then
    . /usr/local/etc/osm-config.sh
else
    log () {
        echo -n `date "+%Y-%m-%d %H:%M:%S+%Z"` "-- $0: $@"
    }
    log "/usr/local/etc/osm-config.sh not found, $0 might error and exit"
fi

log starting

if [ "$1" = "postgres" ]; then
    exec docker-entrypoint.sh "$@"
fi

check_lockfile () {
    if [ -z "$1" ]; then
        log "check_lockfile <lockfile> [log prefix]"
        return 0
    fi
    LOCKFILE="$1"

    if [ -f "$LOCKFILE" ]; then
        log "$2 $LOCKFILE found, previous run didn't finish successfully, rerunning"
        eval `grep "restartcount=[0-9]\+" "$LOCKFILE"`
        restartcount=$(( $restartcount + 1 ))
        if [ "$restartcount" -gt 2 ]; then
            if [ "$restartcount" -gt 24 ]; then
                restartcount=24
            fi
            log "$2 has failed $restartcount times before, sleeping for $(( $restartcount * 3600 )) seconds"
            sleep $(( $restartcount * 3600 ))
        fi
        echo "restartcount=$restartcount" > "$LOCKFILE"
        return 1
    fi

    echo "restartcount=0" > "$LOCKFILE"
    eval `grep "restartcount=[0-9]\+" "$LOCKFILE"`
    return 0
}

chown osm: /data

# https://github.com/docker/docker/issues/6880
cat <> /Nominatim/build/logpipe 1>&2 &

if [ "$1" = "nominatim-apache2" ]; then
    log "$1 called"
    shift

    . /etc/apache2/envvars

    if [ ! -z "$APACHE_LOG_DIR" ]; then
        cd ${APACHE_LOG_DIR} && \
            ln -sf /dev/stdout access.log && \
            ln -sf /dev/stdout error.log
    fi

    if [ ! -d /data/nominatim ]; then
        gosu osm mkdir -p /data/nominatim
    fi

    cd /

    mkdir -p "$APACHE_RUN_DIR" && \
        rm -f $APACHE_PID_FILE && \
        exec /usr/sbin/apache2 -DFOREGROUND "$@"
fi

if [ "$1" = "nominatim-reinitdb" ]; then
    log "$1 called, reinitializing nominatim"
    REINITDB=1 exec $0 nominatim-initdb
fi

if [ "$1" = "nominatim-redownload" ]; then
    log "$1 called, redownloading files"
    REDOWNLOAD=1 exec $0 nominatim-initdb
fi

if [ "$1" = "nominatim-initdb" ]; then
    log "$1 called"

    check_lockfile /data/nominatim-initdb.lock "$1" || REDOWNLOAD=1

    until echo select 1 | gosu postgres psql template1 > /dev/null 2>1 ; do
            log "$1 waiting for postgres, sleeping for $WFS_SLEEP seconds"
            sleep "$WFS_SLEEP"
    done

    gosu postgres createuser www-data > /dev/null 2>/dev/null || true
    gosu postgres createuser -s osm > /dev/null 2>/dev/null || true

    if [ ! -f /data/nominatim/country_name.sql ]; then
        log "$1 setting up /data/nominatim"
        cd /Nominatim && \
            gosu osm mkdir -p /data/nominatim && \
            gosu osm cp -a data/* /data/nominatim
    fi

    cd /Nominatim && \
        rm -rf data && \
        ln -s /data/nominatim data

    if [ "$REINITDB" -o "$REDOWNLOAD" ]; then
        log "$1 reinitializing nominatim database, REINITDB=$REINITDB, REDOWNLOAD=$REDOWNLOAD"
        gosu postgres dropdb nominatim > /dev/null 2>&1 || true
    fi

    if ! $(echo "SELECT 'tables already created' FROM pg_catalog.pg_tables where tablename = 'country_osm_grid'" | \
            gosu postgres psql nominatim | grep -q 'tables already created') || [ "$REINITDB" ];then
        log "$1 downlowding wikipedia and country files"
        gosu osm curl -L -z /Nominatim/data/country_osm_grid.sql.gz -o /Nominatim/data/country_osm_grid.sql.gz \
            https://www.nominatim.org/data/country_grid.sql.gz || {
                log "$1 error downloading https://www.nominatim.org/data/country_grid.sql.gz, exit 2"; exit 2; }
        gosu osm curl -L -z /data/nominatim/wikipedia_article.sql.bin -o /data/nominatim/wikipedia_article.sql.bin \
            https://www.nominatim.org/data/wikipedia_article.sql.bin || {
                log "$1 error downloading https://www.nominatim.org/data/wikipedia_article.sql.bin, exit 3"; exit 3; }
        gosu osm curl -L -z /data/nominatim/wikipedia_redirect.sql.bin -o /data/nominatim/wikipedia_redirect.sql.bin \
            https://www.nominatim.org/data/wikipedia_redirect.sql.bin|| {
                log "$1 error downloading https://www.nominatim.org/data/wikipedia_redirect.sql.bin, exit 4"; exit 4; }

        # this is a noop for a standalone nominatim container, it's used in
        # https://github.com/chesty/maps-docker-compose
        until ! test -f /data/renderd-initdb.lock; do
            log "$1 waiting on renderd-initdb, sleeping for $WFS_SLEEP seconds"
            sleep "$WFS_SLEEP"
        done

        if [ "$REDOWNLOAD" -o ! -f /data/"$OSM_PBF" -a "$OSM_PBF_URL" ]; then
            log "$1 downloading $OSM_PBF_URL"
            gosu osm curl -L -z /data/"$OSM_PBF" -o /data/"$OSM_PBF" "$OSM_PBF_URL" || {
                log "$1 error downloading ${OSM_PBF_UPDATE_URL}/state.txt, exit 7"; exit 7; }
            gosu osm curl -o /data/"$OSM_PBF".md5 "$OSM_PBF_URL".md5 || {
                log "$1 error downloading $OSM_PBF_URL, exit 8"; exit 8; }
            ( cd /data && \
                md5sum -c "$OSM_PBF".md5 ) || {
                    log "$1 md5sum mismatch on /data/$OSM_PBF, exit 1"
                    rm -f /data/"$OSM_PBF".md5 /data/"$OSM_PBF"
                    exit 1
                }
        fi
        REINITDB=1
    fi

    if ! $(echo "SELECT 'tables already created' FROM pg_catalog.pg_tables where tablename = 'planet_osm_nodes'" | \
            gosu postgres psql nominatim | grep -q 'tables already created') || [ "$REINITDB" ];then
        log "$1 initialising database"
        cd /Nominatim/build && \
            gosu postgres ./utils/setup.php --osm-file /data/"$OSM_PBF" --all --osm2pgsql-cache "$OSM2PGSQLCACHE" && \
            gosu postgres ./utils/specialphrases.php --wiki-import | gosu osm tee /data/nominatim/specialphrases.sql > /dev/null && \
            gosu postgres psql -d nominatim -f /data/nominatim/specialphrases.sql && \
            gosu postgres ./utils/setup.php --create-functions --enable-diff-updates --create-partition-functions && \
            gosu postgres ./utils/update.php --recompute-word-counts && \
            gosu postgres ./utils/update.php --init-updates || {
                log "$1 error initialising database, exit 5"; exit 5; }
    fi
    rm -f /data/nominatim-initdb.lock
    exit 0
fi

if [ "$1" = "nominatim-updatedb" ]; then
    log "$1 called"

    # give nominatim-initdb time to start and create lock file
    sleep 5

    until echo select 1 | gosu postgres psql template1 > /dev/null 2>1 ; do
            log "$1 waiting for postgres, sleeping for $WFS_SLEEP seconds"
            sleep "$WFS_SLEEP"
    done

    # don't run update during initdb
    until [ ! -f /data/nominatim-initdb.lock ]; do
        log "$1 waiting for nominatim-initdb to finish"
        sleep "$WFS_SLEEP"
    done

    gosu postgres ./utils/update.php --import-osmosis-all

    exit 0
fi

# postgresql container's docker-entrypoint.sh
exec docker-entrypoint.sh "$@"
