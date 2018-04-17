#!/bin/bash


if [ ! -f /app/bin/db.yml ] ; then
  ./bin/fc-setup-db -h $MYSQL_HOST -u $MYSQL_USER -p $MYSQL_PASSWORD -d $MYSQL_DATABASE -f -i -m
fi

echo "run $@"
exec "$@"
