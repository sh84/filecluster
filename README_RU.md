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
