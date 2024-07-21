#!/bin/bash

if ! [ -x "$(command -v docker compose)" ]; then
  echo 'Error: docker compose is not installed.' >&2
  exit 1
fi

#domains=({DOMAIN.TLD} *.{DOMAIN.TLD})
domains=({DOMAIN.TLD} www.{DOMAIN.TLD} sub.{DOMAIN.TLD})
rsa_key_size=4096
data_path="./letsencrypt"
container_data_path="/etc/letsencrypt"
email=""  # Adding a valid address is strongly recommended
testing=0 # Set to 1 if you're testing your setup to avoid hitting request limits

if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
  echo "### Downloading recommended TLS parameters ..."
  mkdir -p "$data_path/conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf >"$data_path/conf/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem >"$data_path/conf/ssl-dhparams.pem"
  echo
fi

if ! [ -f "$data_path/dhparam.pem" ]; then
  docker compose run --rm --entrypoint "\
  openssl dhparam \
    -out '$container_data_path/dhparam.pem' \
    $rsa_key_size" certbot
  echo
fi

echo "### Requesting Let's Encrypt certificate for $domains ..."
domain_args=""
for domain in "${domains[@]}"; do
  domain_args="$domain_args -d $domain"
done

if echo "${domain_args}" | grep -q '\*'; then
  domain_args="${domain_args} --manual --preferred-challenges dns"
else
  domain_args="${domain_args} --webroot -w /var/www/certbot"
fi

case "$email" in
"") email_arg="--register-unsafely-without-email" ;;
*) email_arg="--email $email" ;;
esac

if [ "$email_arg" != "--register-unsafely-without-email" ]; then
  read -p "Do you wish to share your email with the Electronic Frontier Foundation (EFF)? (y/N) " decision
  if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
    email_arg="${email_arg} --no-eff-email"
  fi
fi

testing_arg=""
if [ $testing != "0" ]; then testing_arg="--dry-run"; fi

docker compose run --rm --entrypoint "\
  certbot certonly \
    $testing_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot
echo

echo "### Reloading nginx ..."
docker compose exec nginx-reverse-proxy nginx -s reload
