FileCluster

Набор скриптов для управления контентом по верх файловой системы
Уровень регистрации в базе - файл или папка


Принцип работы

Информация о файлах/папках записывается в базу данных (mysql)
Демон на основе записей в базе данных приводит соответствие файлов списку зарегистрированных файлов/папок


Компоненты

filecluster - deamon/manager (ruby)
mysql -  мета информация
sshd + rsync  - транспорт



Быстрый запуск тестов

первый запуск mysql -

docker-compose run --rm filecluster-db

Окончание инициализации можно будет увидеть по сообщению о готовности к работе mysql
CTRL+C

Запуск тестов

docker-compose  run --rm filecluser1 rake



Быстрый старт:

Шаг 1 
/app/bin/fc-manage storages add

Name: quickstart #
DC: QS 
Path: /data 
Url: http://filecluster1-http/
URL weight: 1
Write weight: 1
Auto size (y/n)?: n
Size limit: 20G
Copy storages: filecluster1

Шаг 2
/app/bin/fc-manage policies add

Policy
  Name:                 images
  Create storages:      quickstart
  Copies:               1
  Delete deferred time: 0
Continue? (y/n) y
