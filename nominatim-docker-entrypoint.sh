#!/bin/bash

echo "starting $@"

: ${OSM_PBF_URL:=http://download.geofabrik.de/australia-oceania/australia-latest.osm.pbf}
: ${OSM_PBF:=$(basename "$OSM_PBF_URL")}
: ${OSM_PBF_BASENAME:=$(basename "$OSM_PBF" .osm.pbf)}
: ${OSM2PGSQLCACHE:=1000}

if [ ! -f /home/postgres/.pgpass ]; then
    mkdir -p /home/postgres && \
        touch /home/postgres/.pgpass && \
        chmod 600 /home/postgres/.pgpass && \
        chown -R postgres: /home/postgres && \
        echo "$POSTGRES_HOST:$POSTGRES_PORT:*:$POSTGRES_USER:$POSTGRES_PASSWORD" >> /home/postgres/.pgpass
fi

if [ "$1" == "nominatim-apache2" ]; then
    shift

    . /etc/apache2/envvars

    if [ ! -z "$APACHE_LOG_DIR" ]; then
        cd ${APACHE_LOG_DIR} && \
            ln -sf /dev/stdout access.log && \
            ln -sf /dev/stdout error.log
    fi

    if [ ! -d /data/nominatim ]; then
        mkdir /data/nominatim
        chown postgres: /data/nominatim
    fi

    touch /data/nominatim/nominatim.log && \
        chgrp www-data /data/nominatim/nominatim.log && \
        chmod g+wr /data/nominatim/nominatim.log

    cd /

    mkdir -p "$APACHE_RUN_DIR" && \
        rm -f $APACHE_PID_FILE && \
        exec /usr/sbin/apache2 -DFOREGROUND "$@"
fi

if [ "$1" == "nominatim-initdb" ]; then
    shift
    # if nominatim-initdv.init exists then the previous initdb didn't complete
    if [ -f /data/nominatim-initdb.init ]; then
        REDOWNLOAD=1
    fi
    touch /data/nominatim-initdb.init

    until echo select 1 | gosu postgres psql template1 &> /dev/null ; do
            echo "Waiting for postgres"
            sleep 5
    done

    gosu postgres createuser www-data &> /dev/null || true

    if [ ! -f /data/nominatim/country_name.sql ]; then
        cd /Nominatim && \
            mkdir -p /data/nominatim && \
            cp -a data/* /data/nominatim && \
            chown -R postgres: /data/nominatim
            touch /data/nominatim/nominatim.log && \
            chgrp www-data /data/nominatim/nominatim.log && \
            chmod g+wr /data/nominatim/nominatim.log
    fi

    cd /Nominatim && \
        rm -rf data && \
        ln -s /data/nominatim data && \

    if ! $(echo select 1 | gosu postgres psql nominatim &> /dev/null) || [ "$REDOWNLOAD" ];then
        gosu postgres curl -L -z /Nominatim/data/country_osm_grid.sql.gz -o /Nominatim/data/country_osm_grid.sql.gz \
            https://www.nominatim.org/data/country_grid.sql.gz
        gosu postgres curl -L -z /data/nominatim/wikipedia_article.sql.bin -o /data/nominatim/wikipedia_article.sql.bin https://www.nominatim.org/data/wikipedia_article.sql.bin
        gosu postgres curl -L -z /data/nominatim/wikipedia_redirect.sql.bin -o /data/nominatim/wikipedia_redirect.sql.bin https://www.nominatim.org/data/wikipedia_redirect.sql.bin

        # this is a noop for a standalone nominatim container, it's used in
        # https://github.com/chesty/maps-docker-compose
        until ! test -f /data/renderd-initdb.init; do
            echo waiting on renderd-initdb
            sleep 5
        done

        if [ "$REDOWNLOAD" -o ! -f /data/"$OSM_PBF" -a "$OSM_PBF_URL" ]; then
            curl -L -z /data/"$OSM_PBF" -o /data/"$OSM_PBF" "$OSM_PBF_URL"
            curl -o /data/"$OSM_PBF".md5 "$OSM_PBF_URL".md5
            cd /data && \
                md5sum -c "$OSM_PBF".md5 || { rm -f /data/"$OSM_PBF"; exit 1; }
        fi
        REINITDB=1
    fi

    if ! $(echo select 1 | gosu postgres psql nominatim &> /dev/null) || [ "$REINITDB" ];then
        gosu postgres dropdb nominatim &> /dev/null
        cd /Nominatim/build && \
            gosu postgres ./utils/setup.php --osm-file /data/"$OSM_PBF" --all --osm2pgsql-cache "$OSM2PGSQLCACHE" && \
            gosu postgres ./utils/update.php --recompute-word-counts && \
            gosu postgres ./utils/specialphrases.php --wiki-import > /data/nominatim/specialphrases.sql && \
            gosu postgres psql -d nominatim -f /data/nominatim/specialphrases.sql && \
            gosu postgres ./utils/setup.php --create-functions --enable-diff-updates --create-partition-functions && \
            echo "alter function transliteration set search_path to '/Nominatim/build/module';" | gosu postgres psql -d nominatim
            # see http://www.postgresql-archive.org/Autovacuum-analyze-can-t-find-C-based-function-td6030088.html
    fi
    rm -f /data/nominatim-initdb.init
    exit 0
fi

if [ "$1" == "nominatim-updatedb" ]; then
    shift

    until echo select 1 | gosu postgres psql template1 &> /dev/null ; do
            echo "Waiting for postgres"
            sleep 5
    done
    # don't run update during initdb
    if [ ! -f /data/nominatim-initdb.init ]; then
        gosu postgres ./utils/update.php --init-updates
        gosu postgres ./utils/update.php --import-osmosis
        gosu postgres ./utils/update.php --recompute-word-counts
    fi
    exit 0
fi

exec docker-entrypoint.sh "$@"
