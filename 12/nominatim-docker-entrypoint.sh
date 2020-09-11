#!/bin/sh

set -e

. /usr/local/etc/osm-config.sh

if [ ! -d "$DATA_DIR" ]; then
  log "error $DATA_DIR doesn't exist, it's meant to be a volume for persistent storage, exit "
  exit 28
fi

if [ ! -d "$DATA_DIR/nominatim" ]; then
  gosu osm mkdir -p "$DATA_DIR/nominatim"
fi

if [ $# -gt 0 ]; then
  export SUBCOMMAND="$1"
  shift

  ensure_single_unique_container "$@" || exit $?
fi

chown osm: "$DATA_DIR"

log "starting $SUBCOMMAND"

if [ "$SUBCOMMAND" = "postgres" ]; then
  exec docker-entrypoint.sh postgres "$@"
fi

download_nominatim_data() {
  if [ -z "$1" ]; then
    log "$SUBCOMMAND download_nominatim_data <filename>"
    return 1
  fi

  download https://www.nominatim.org/data/"$1" "$DATA_DIR/nominatim/$1" || {
    log "$SUBCOMMAND error downloading https://www.nominatim.org/data/$1"
    return 2
  }
  if [ "$1" = "country_grid.sql.gz" ]; then
    ln -f "$DATA_DIR/nominatim/$1" "$DATA_DIR/nominatim/country_osm_grid.sql.gz" || {
      log "$SUBCOMMAND error setting up $DATA_DIR/nominatim/country_osm_grid.sql.gz"
      return 3
    }
  fi
}

download() {
  URL="$1"
  FILE="$2"
  if [ -z "$URL" ]; then
    log "$SUBCOMMAND download <url> [filename]"
    return 1
  fi
  # this isn't super robust, if the url is http://blah.com FILE will be blah.com
  # if the url is http://blah.com/file/data.bin FILE will be data.bin (which is what we want)
  if [ -z "$FILE" ]; then
    FILE=$(echo "$URL" | sed 's#.*/##')
    if [ -z "$FILE" ]; then
      FILE="index.html"
    fi
  fi
  cd "$DATA_DIR"
  gosu osm flock "$FILE".lock curl --remote-time --location --retry 3 --time-cond "$FILE" \
    --silent --show-error --output "$FILE" "$URL" || {
    log "$SUBCOMMAND error downloading $URL"
    rm -f "$FILE".lock
    return 2
  }
  rm -f "$FILE".lock
}

nominatim_custom_scripts() {
  if [ -d /nominatim-custom.d ]; then
    for SCRIPT in /nominatim-custom.d/*.sh; do
      . "$SCRIPT" "$@"
    done
  fi
}

# https://github.com/docker/docker/issues/6880
cat <>/Nominatim/build/logpipe 1>&2 &

if [ "$SUBCOMMAND" = "nominatim-apache2" ]; then
  log "$SUBCOMMAND called"

  . /etc/apache2/envvars

  if [ ! -z "$APACHE_LOG_DIR" ]; then
    cd ${APACHE_LOG_DIR} &&
      ln -sf /dev/stdout access.log &&
      ln -sf /dev/stdout error.log
  fi

  # Not sure where settings.php comes from, but `php utils/setup.php --setup-website`
  # expects settings-frontend.php otherwise requests to nominatim respond with HTTP 500
  cd /Nominatim/build/settings &&
    ln -s settings.php settings-frontend.php

  cd /

  mkdir -p "$APACHE_RUN_DIR" &&
    rm -f $APACHE_PID_FILE &&
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

if [ "$SUBCOMMAND" = "nominatim-initdb" ]; then
  log "$SUBCOMMAND called"

  # If it fails 3 times sleep for 3 hours to rate limit how often we try to download from the upstream server
  check_lockfile "$LOCKFILE" "$SUBCOMMAND" || rate_limit "$LOCKFILE" "$SUBCOMMAND" || REDOWNLOAD=1

  until echo select 1 | gosu $POSTGRES_USER psql template1 >/dev/null 2>1; do
    log "$SUBCOMMAND waiting for postgres, sleeping for $WFS_SLEEP seconds"
    sleep "$WFS_SLEEP"
  done

  gosu $POSTGRES_USER createuser www-data >/dev/null 2>/dev/null || true
  gosu $POSTGRES_USER createuser -s osm >/dev/null 2>/dev/null || true

  cd /Nominatim
  test -h data ||
    cp -a data/* "$DATA_DIR/nominatim"
  rm -rf data && {
    ln -s "$DATA_DIR/nominatim" data || {
      log "$SUBCOMMAND error setting up $DATA_DIR/nominatim/data, exit 27"
      exit 27
    }
  }

  if [ "$REINITDB" ] || [ -f "/data/nominatim-REINITDB" ] || [ "$REDOWNLOAD" ]; then
    log "$SUBCOMMAND reinitializing nominatim database, REINITDB=$REINITDB, REDOWNLOAD=$REDOWNLOAD"
    gosu $POSTGRES_USER dropdb nominatim >/dev/null 2>&1 || true
  fi

  if ! $(echo "SELECT 'tables already created' FROM pg_catalog.pg_tables where tablename = 'country_osm_grid'" |
    gosu $POSTGRES_USER psql nominatim | grep -q 'tables already created') ||
    [ "$REINITDB" ] || [ -f "/data/nominatim-REINITDB" ] || [ "$REDOWNLOAD" ]; then
    log "$SUBCOMMAND downlowding wikipedia and country files"
    rm -f "/data/nomintaim-REINITDB"
    for file in wikimedia-importance.sql.gz country_grid.sql.gz wikipedia_article.sql.bin wikipedia_redirect.sql.bin gb_postcode_data.sql.gz; do
      download_nominatim_data "$file" || {
        touch "/data/nominatim-REINITDB"
        log "$SUBCOMMAND error downloading wikipedia data, exit 2"
        exit 2
      }
    done

    if [ "$REDOWNLOAD" ] || [ ! -f "$DATA_DIR/$OSM_PBF" ]; then
      log "$SUBCOMMAND downloading $OSM_PBF_URL"
      download "$OSM_PBF_URL" || {
        log "$SUBCOMMAND error downloading $OSM_PBF_URL, exit 8"
        rm -f "$DATA_DIR/$OSM_PBF".md5 "$DATA_DIR/$OSM_PBF"
        exit 8
      }
      download "$OSM_PBF_URL".md5 || {
        log "$SUBCOMMAND error downloading ${OSM_PBF_URL}.md5, exit 9"
        rm -f "$DATA_DIR/$OSM_PBF".md5 "$DATA_DIR/$OSM_PBF"
        exit 9
      }
      (cd "$DATA_DIR" &&
        gosu osm md5sum -c "$OSM_PBF".md5) || {
        rm -f "$DATA_DIR/$OSM_PBF".md5 "$DATA_DIR/$OSM_PBF"
        log "$SUBCOMMAND error md5sum mismatch on $DATA_DIR/$OSM_PBF, exit 4"
        exit 4
      }
      REPROCESS=1
    fi
    REINITDB=1
  fi

  if ! $(echo "SELECT 'tables already created' FROM pg_catalog.pg_tables where tablename = 'planet_osm_nodes'" |
    gosu $POSTGRES_USER psql nominatim | grep -q 'tables already created') ||
    [ "$REINITDB" ] || [ -f "/data/nominatim-REINITDB" ]; then
    log "$SUBCOMMAND initialising database"
    rm -f "/data/nominatim-REINITDB"

    # another container could be downloading "$DATA_DIR/$OSM_PBF", so we'll wait for the lock to release
    gosu osm flock "$DATA_DIR/$OSM_PBF".lock true && rm -f "$DATA_DIR/$OSM_PBF".lock

    cd /Nominatim/build &&
      gosu $POSTGRES_USER ./utils/setup.php --osm-file "$DATA_DIR/$OSM_PBF" --all --osm2pgsql-cache "$OSM2PGSQLCACHE" &&
      gosu $POSTGRES_USER ./utils/specialphrases.php --wiki-import | gosu osm tee "$DATA_DIR/nominatim/specialphrases.sql" >/dev/null &&
      gosu $POSTGRES_USER psql -d nominatim -f "$DATA_DIR/nominatim/specialphrases.sql" &&
      gosu $POSTGRES_USER ./utils/setup.php --create-functions --enable-diff-updates --create-partition-functions &&
      gosu $POSTGRES_USER ./utils/update.php --recompute-word-counts &&
      gosu $POSTGRES_USER ./utils/update.php --init-updates || {
      log "$SUBCOMMAND error initialising database, exit 5"
      touch "/data/nominatim-REINITDB"
      exit 5
    }
  fi

  nominatim_custom_scripts initdb
  rm -f "/data/nominatim-REINITDB"
  # nominatim-updatedb checks $LOCKFILE exists and is 0 bytes before updating
  >"$LOCKFILE"
  exit 0
fi

if [ "$SUBCOMMAND" = "nominatim-updatedb" ]; then
  log "$SUBCOMMAND called"

  # give nominatim-initdb time to start and create lock file
  sleep 5

  until echo select 1 | gosu $POSTGRES_USER psql template1 >/dev/null 2>1; do
    log "$SUBCOMMAND waiting for postgres, sleeping for $WFS_SLEEP seconds"
    sleep "$WFS_SLEEP"
  done

  # the lock file has to exist and be 0 bytes signifying nominatim-initdb has finished before continuing
  until [ -f "$DATA_DIR/$(config_specific_name nominatim-initdb).lock" ] && [ ! -s "$DATA_DIR/$(config_specific_name nominatim-initdb).lock" ]; do
    log "$SUBCOMMAND waiting for nominatim-initdb to finish"
    sleep "$WFS_SLEEP"
  done

  nominatim_custom_scripts updatedb

  gosu $POSTGRES_USER ./utils/update.php --import-osmosis-all

  exit 0
fi

if [ "$SUBCOMMAND" = "nominatim-command" ]; then
  log "$SUBCOMMAND called"
  exec "$@"
fi

# postgresql container's docker-entrypoint.sh
exec docker-entrypoint.sh "$@"
