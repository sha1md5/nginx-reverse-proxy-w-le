docker network create nginx-reverse-proxy

docker network connect nginx-reverse-proxy {CONTAINER_NAME}


0 0 */89 0 0 docker run --rm -it --name certbot -v
"/docker-volumes/data/letsencrypt:/data/letsencrypt" -v
"/docker-volumes/etc/letsencrypt:/etc/letsencrypt" -v
"/docker-volumes/var/lib/letsencrypt:/var/lib/letsencrypt" -v
"/docker-volumes/var/log/letsencrypt:/var/log/letsencrypt" certbot/certbot renew --webroot -w
/data/letsencrypt --quiet && docker kill --signal=HUP production-nginx-container

https://gist.github.com/erangaeb/a2d1c34222cf2493b89f540f1397161e
https://eff-certbot.readthedocs.io/en/stable/using.html#manual-renewal
https://eff-certbot.readthedocs.io/en/stable/using.html#hooks
https://community.letsencrypt.org/t/dns-providers-who-easily-integrate-with-lets-encrypt-dns-validation/86438
https://serverfault.com/questions/1125933/automate-renewal-of-lets-encrypt-acme-dns-challenge-with-unbound
https://security.stackexchange.com/questions/256920/what-does-it-mean-to-create-a-lets-encrypt-certificate-automatically-rather-t/256924#256924
https://www.reddit.com/r/docker/comments/nebu08/ssl_certs_automatically_created_for_all_my/