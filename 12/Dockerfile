FROM hammermc/postgis-docker:12 as buildstage

ENV BUMP 20.06.19.1

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install \
        apache2 \
        build-essential \
        cmake \
        curl \
        g++ \
        git \
        libapache2-mod-php \
        libboost-all-dev \
        libboost-dev \
        libboost-filesystem-dev \
        libboost-system-dev \
        libbz2-dev \
        libexpat1-dev \
        libgeos++-dev \
        libgeos-dev \
        libpq-dev \
        libproj-dev \
        libxml2-dev \
        php \
        php-cli \
        php-dev \
        php-intl \
        php-pgsql \
        postgresql-12-postgis-3 \
        postgresql-12-postgis-3-scripts \
        postgresql-contrib \
        postgresql-server-dev-12 \
        python3-dev \
        python3-pip \
        zlib1g-dev

RUN git clone --depth 1 --branch master --single-branch https://github.com/openstreetmap/Nominatim.git && \
    cd Nominatim && \
    git submodule update --recursive --init

RUN cd Nominatim && \
    mkdir -p build && \
    cd build && \
    cmake .. && \
    make && \
    make install

FROM hammermc/postgis-docker:12 as runstage
COPY --from=buildstage /usr/local/ /usr/local/
COPY --from=buildstage /Nominatim /Nominatim

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install \
        apache2 \
        ca-certificates \
        curl \
        gosu \
        libapache2-mod-php \
        libboost-filesystem1.67.0 \
        libboost-python1.67.0 \
        libboost-system1.67.0 \
        libproj13 \
        php-cli \
        php-db \
        php-intl \
        php-pgsql \
        postgresql-12-postgis-3 \
        postgresql-12-postgis-3-scripts \
        postgresql-client-12 \
        postgresql-contrib \
        python3 \
        python3-pip && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /src

RUN set -ex; \
	\
    apt-get update; \
	DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
	    build-essential \
	    libpq5 \
	    libpq-dev \
	    python3-dev; \
	python3 -m pip install wheel setuptools; \
	python3 -m pip install osmium psycopg2 pytidylib; \
	apt-get purge -y \
	    build-essential \
	    libpq-dev \
	    python3-dev; \
    apt-get autoremove --purge -y; \
    rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash osm
RUN chown postgres /Nominatim/build
RUN mkfifo -m 600 /Nominatim/build/logpipe && \
    chown www-data /Nominatim/build/logpipe

COPY nominatim-docker-entrypoint.sh /usr/local/bin/
COPY osm-config.sh /usr/local/etc/

EXPOSE 5432
EXPOSE 80

WORKDIR /Nominatim/build

ENTRYPOINT ["nominatim-docker-entrypoint.sh"]
