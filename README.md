docker network create nginx-reverse-proxy

docker network connect nginx-reverse-proxy {CONTAINER_NAME}


0 0 */89 0 0 docker run --rm -it --name certbot -v
"/docker-volumes/data/letsencrypt:/data/letsencrypt" -v
"/docker-volumes/etc/letsencrypt:/etc/letsencrypt" -v
"/docker-volumes/var/lib/letsencrypt:/var/lib/letsencrypt" -v
"/docker-volumes/var/log/letsencrypt:/var/log/letsencrypt" certbot/certbot renew --webroot -w
/data/letsencrypt --quiet && docker kill --signal=HUP production-nginx-container

