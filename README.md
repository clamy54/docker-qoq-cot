# QoQ-Cot 

This container provides a fully fonctional [QoQ-Cot](https://sourcesup.renater.fr/wiki/qoq-cot/presentation_generale) server (WebUI & Coq server)

This build is based on php:7.2-fpm-alpine and QoQ-Cot v5.0_mac_bec.

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

You can now access the WebUI at https://my-server-ip:8080/ using the credentials issued by the  ___docker container logs___ command.

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


##  Environment variables

* TZONE : (Optionnal) timezone value to put in php.ini

## Source repository 

Sources can be found at :
https://github.com/clamy54/docker-qoq-cot

