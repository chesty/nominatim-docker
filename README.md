# nominatim-docker

nominatim release-v3.1.0

It works as a standalone nominatim docker container and it should 
init to a working install, but it requires some tuning and
configuration changes to suit your environment.

During the first boot it copies config files to various volumes
where you can edit them, then down and up the containers.

It works if you just run `compose-docker up -d`, but it will probably
be a lot quicker if you do something like

```shell
docker-compose up --no-start
docker-compose start postgres
# wait for postgres to finish initialising
docker-compose down
# then edit the postgresql.conf in the postgres-data volume with suitable values for your environment.
docker-compose up -d

```
