#!/bin/bash


if [ ! -f /app/bin/db.yml ] ; then
  ./bin/fc-setup-db -h $MYSQL_HOST -u $MYSQL_USER -p $MYSQL_PASSWORD -d $MYSQL_DATABASE -f -i -m
fi

if [ ! -f /home/filecluster/.ssh/id_rsa ]; then
  mkdir /home/filecluster/.ssh -p
  chown filecluster:filecluster /home/filecluster/.ssh
  chmod 0700 /home/filecluster/.ssh
  ssh-keygen -t rsa -b 2048 -N "" -C "filecluster key" -f /home/filecluster/.ssh/id_rsa
  cp /home/filecluster/.ssh/{id_rsa.pub,authorized_keys}
  chown -R filecluster:filecluster /home/filecluster
  echo "ID_RSA - generate"
fi

export HOME=/home/filecluster/
exec  setuid 1000 "$@"
