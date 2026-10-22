# QoQ-Cot 

This container provides a fully fonctional [QoQ-Cot](https://sourcesup.renater.fr/wiki/qoq-cot/presentation_generale) server (WebUI & Coq server)

This build is based on php:8.4-fpm-alpine (MariaDB 11.8) and QoQ-Cot v5.0_mac_bec.

QoQ-Cot was written for PHP 7. The patches under `files/patches/` are applied at build time so that it runs on PHP 8.4 :

* `01-dao-php8.patch` : `Dao::getTableConnexions()` is declared static, PDO keeps its PHP 7 behaviour (silent SQL errors, values fetched as strings), and adds `Dao::unserializeListe()`
* `02-pchart-setgrapharea-sans-dataset.patch` : fixes `Attempt to modify property "Data" on null` in pChart (duration graphs)
* `03-cumulduree-periode-inclusive.patch` : fixes `DivisionByZeroError` when the start and end dates are the same day, and the presence percentages of the cumulated duration graph
* `04-unserialize-listes-url.patch` : stricter handling of the room and working day lists used by the graphs
* `05-bonne-annee-pdo-php7.patch` : PHP 7 PDO behaviour for `bonne_annee.php`

## Security

The additional patches under `files/patches/` harden the web application and the server configuration. Users of previous versions of this image should upgrade.

`setup.php`, `export_salles_to_csv.php` and `bonne_annee.php` can no longer be opened from a browser. Run them with `docker container exec`, for example :
```shell
docker container exec qoq-cot php /var/www/localhost/htdocs/bonne_annee.php
```

*This isn't an official build and it comes with no warranty  ...*

## How to run

Create a ___www___ and a ___db___ directories then run,

```shell
docker container run --name qoq-cot  -p 8080:8080 -p 9900:9900  -v ./www:/var/www/localhost/htdocs  -v ./db:/var/lib/mysql -d clamy54/qoq-cot:latest
```

You can get mariadb passwords and webui admin password using the following command :
```shell
docker container logs qoq-cot 
```

You now have to prepare a csv file according to the [qoq-cot official documentation](https://sourcesup.renater.fr/wiki/qoq-cot/installation_v5.0_mac_bec).
For example, let's use the following test.csv file :
```
"Room-1-01","Room 1","My Entity","2024-01-01","2030-12-31"
"Room-1-02","Room 1","My Entity","2024-01-01","2030-12-31"
"Room-1-03","Room 1","My Entity","2024-01-01","2030-12-31"
"Room-1-04","Room 1","My Entity","2024-01-01","2030-12-31"

```
Then put the csv file under the ./www/csv directory.

Now execute the following command :
```shell
docker container exec qoq-cot php /var/www/localhost/htdocs/setup.php /var/www/localhost/htdocs/csv/test.csv
docker container exec qoq-cot php /var/www/localhost/htdocs/setup.php -c
```

You can now access the WebUI at http://my-server-ip:8080/ using the credentials issued by the  ___docker container logs___ command.

The Coq server is running at my-server-ip:9900.

## Adding other WebUI users

You can add WebUI users using the following command :
```shell
docker container exec qoq-cot htpasswd -b /var/www/localhost/htdocs/.htpasswd <user_login> <user_password>   
```

Then add <user_login> under the admin tab on the WebUI.

You can manually modify the .www/.htaccess file to use another type of authentication

##  Volumes

To persist data, theses volumes are exposed and can be mounted to the local filesystem by adding -v option in the command line :

* `/var/www/localhost/htdocs` - Apache DocumentRoot
* `/var/lib/mysql` - MariaDB database files


When the image changes, the QoQ-Cot code in `/var/www/localhost/htdocs` is updated at startup. `config.php`, `.htaccess`, `.htpasswd`, `csv/` and `config-coq/` are kept.

##  Environment variables

* TZONE : (Optionnal) timezone value to put in php.ini

## Upgrading from the PHP 7.2 image

The previous image (php:7.2-fpm-alpine, MariaDB 10.4) never stopped MariaDB cleanly. MariaDB 11.8 refuses to upgrade such a database, so stop it cleanly with the previous image first :

```shell
docker container exec qoq-cot sh -c 'kill $(pidof mysqld); while pidof mysqld >/dev/null; do sleep 1; done'
docker container logs qoq-cot 2>&1 | grep "Shutdown complete"
docker container stop qoq-cot
docker container rm qoq-cot
```

Backup the ___www___ and ___db___ directories, then start the new image with the same `docker container run` command as before. The database is upgraded on the first start and all passwords are kept. If the new image prints that the database was not shut down cleanly, start the previous image (`clamy54/qoq-cot:1.2`) again on the same directories and repeat the steps above.

## Building

```shell
docker build -t qoq-cot .
```

The QoQ-Cot archive is downloaded from SourceSup. When SourceSup is unavailable, put `QoQ-CoT_v5.0_Mac_Bec.tgz` under `files/qoq-src/` and it will be used instead. The `QOQ_URL` and `QOQ_SHA256` build arguments change the download URL and check the archive checksum.

## Source repository 

Sources can be found at :
https://github.com/clamy54/docker-qoq-cot

