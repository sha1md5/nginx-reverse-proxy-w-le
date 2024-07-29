#!/bin/bash

### Checking System Reqs ###
if ! [ -x "$(command -v docker compose)" ]; then
  echo 'Error: docker compose is not installed.' >&2
  exit 1
fi

if  ! dpkg -s "python3" >/dev/null 2>&1 || ! dpkg -s "python3-tldextract" >/dev/null 2>&1 ; then
  echo 'Error: python3 and/or python3-tldextract is not installed.' >&2
  exit 1
fi

if [ "$(docker ps | grep 'nginx-reverse-proxy')" == "" ]; then
  echo 'Error: container nginx-reverse-proxy is not running.' >&2
  exit 1
fi

### Configuration ###
domains=({DOMAIN.TLD} www.{DOMAIN.TLD} sub.{DOMAIN.TLD})
# OR domains=({DOMAIN.TLD} *.{DOMAIN.TLD})
rsa_key_size=4096
data_path="./letsencrypt"
container_data_path="/etc/letsencrypt"
email="" # Adding a valid address is strongly recommended
testing=1 # Set to 1 if you're testing your setup to avoid hitting request limits
main_domains=()
for domain in "${domains[@]}"; do
  main_domain=$(python3 get-main-domain.py "$domain")
  if [[ " ${main_domains[*]} " =~ [[:space:]]${main_domain}[[:space:]] ]]; then
    continue
  else
    main_domains+=("$main_domain")
  fi
done

### CLOUDFLARE ###
cloudflare_bearer="" # Create an API Token only for DNS:Edit!
cloudflare_zone=""
cloudflare_account=""
create_missing_domains=0
current_ip=$(curl -s ipinfo.io/ip)
comment="Added automatically from $current_ip by $(whoami) at $(date +'%Y-%m-%d %H:%M:%S')"
if [ "$cloudflare_bearer" != "" ] && [ "$cloudflare_zone" != "" ] && [ "$cloudflare_account" != "" ]; then
  domains_copy=("${domains[@]}")
  A_records=()
  echo "### Checking existing DNS records with domains configuration ..."
  #https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-list-dns-records
  cloudflare_dns_records=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$cloudflare_zone/dns_records?type=AAAA,A,CNAME" \
    -H "Authorization: Bearer $cloudflare_bearer" \
    -H "Content-Type: application/json" | jq -c '.result[]')
  while IFS= read -r dns_record <&3; do
    dns_record_id=$(echo "$dns_record" | jq -r '.id' | xargs)
    if [ "$dns_record_id" == "" ]; then
      continue
    fi
    dns_record_type=$(echo "$dns_record" | jq -r '.type' | xargs)
    dns_record_name=$(echo "$dns_record" | jq -r '.name' | xargs)
    dns_record_content=$(echo "$dns_record" | jq -r '.content' | xargs)
    dns_record_proxied=$(echo "$dns_record" | jq -r '.proxied' | xargs)
    #dns_record_ttl=$(echo "$dns_record" | jq -r '.ttl' | xargs)

    echo "Found $dns_record_type record for $dns_record_name with $dns_record_content address (proxied: $dns_record_proxied)"
    exec 4<> /dev/tty
    if [ "$dns_record_type" == "A" ] || [ "$dns_record_type" == "AAAA" ]; then
      if [[ " ${domains[*]} " =~ [[:space:]]${dns_record_name}[[:space:]] ]]; then
        A_records+=("$dns_record_name")
        if [ "$current_ip" != "$dns_record_content" ]; then
          echo "IP of $dns_record_type record $dns_record_content different from current $current_ip"
          read -p "Want to change IP address from $dns_record_content to $current_ip? (y/N) " decision <&4
          if [ "$decision" == "Y" ] || [ "$decision" == "y" ]; then
            dns_record=$(echo "$dns_record" | jq -r ".content = \"$current_ip\"")
            dns_record=$(echo "$dns_record" | jq -r '.ttl = 60')
            dns_record=$(echo "$dns_record" | jq -r ".comment = \"$comment\"")
            dns_record=$(echo "$dns_record" | jq -r ".proxied = false")
            echo "$dns_record"
            #https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-patch-dns-record
            curl --request PATCH \
              --url "https://api.cloudflare.com/client/v4/zones/$cloudflare_zone/dns_records/$dns_record_id" \
              -H "Authorization: Bearer $cloudflare_bearer" \
              -H 'Content-Type: application/json' \
              --data "$dns_record"
          fi
        fi
      fi
    elif [ "$dns_record_type" == "CNAME" ]; then
      if [[ " ${domains[*]} " =~ [[:space:]]${dns_record_name}[[:space:]] ]]; then
        domains_copy=($(echo "${domains_copy[@]}" | sed "s/$dns_record_name//"))
        main_domain=$(python3 get-main-domain.py "$dns_record_name")
        if [ "$main_domain" != "$dns_record_content" ]; then
          echo "$dns_record_type record not points to $main_domain"
          read -p "Want to change $dns_record_type record from $dns_record_content to $main_domain? (y/N) " decision <&4
          if [ "$decision" == "Y" ] || [ "$decision" == "y" ]; then
            dns_record=$(echo "$dns_record" | jq -r ".content = \"$main_domain\"")
            dns_record=$(echo "$dns_record" | jq -r '.ttl = 60')
            dns_record=$(echo "$dns_record" | jq -r ".comment = \"$comment\"")
            dns_record=$(echo "$dns_record" | jq -r ".proxied = false")
            echo "$dns_record"
            #https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-create-dns-record
            curl --request PATCH \
              --url "https://api.cloudflare.com/client/v4/zones/$cloudflare_zone/dns_records/$dns_record_id" \
              -H "Authorization: Bearer $cloudflare_bearer" \
              -H 'Content-Type: application/json' \
              --data "$dns_record"
          fi
        fi
      fi
    fi
    exec 4<&-
    exec 4>&-
    echo ""
  done 3<<< "$cloudflare_dns_records"

  for A_record in "${A_records[@]}"; do
    domains_copy=($(echo "${domains_copy[@]}" | sed "s/$A_record//"))
  done

  if [ "$create_missing_domains" != "0" ]; then
    echo "### Creating missing A and CNAME DNS records ..."
    for domain in "${domains_copy[@]}"; do
      json_data="{
        \"content\": \"\",
        \"name\": \"\",
        \"proxied\": false,
        \"type\": \"\",
        \"comment\": \"$comment\",
        \"tags\": [],
        \"ttl\": 60
      }"
      main_domain=$(python3 get-main-domain.py "$domain")
      dns_record_type="A"
      dns_record_name=$main_domain
      dns_record_content=$current_ip
      if [ "$main_domain" != "$domain" ]; then
        dns_record_type="CNAME"
        dns_record_name=$domain
        dns_record_content=$main_domain
      fi
      json_data=$(echo "$json_data" | jq -r ".type = \"$dns_record_type\"")
      json_data=$(echo "$json_data" | jq -r ".name = \"$dns_record_name\"")
      json_data=$(echo "$json_data" | jq -r ".content = \"$dns_record_content\"")
      echo "$json_data"
      read -p "Create DNS record? (y/N) " decision
      if [ "$decision" == "Y" ] || [ "$decision" == "y" ]; then
        curl --request POST \
          --url "https://api.cloudflare.com/client/v4/zones/$cloudflare_zone/dns_records" \
          -H "Authorization: Bearer $cloudflare_bearer" \
          -H 'Content-Type: application/json' \
          --data "$json_data"
      fi
      echo ""
    done

    echo "### Creating missing CAA DNS records for LetsEncrypt ..."
    main_domains_copy=("${main_domains[@]}")
    cloudflare_dns_records=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$cloudflare_zone/dns_records?type=CAA" \
      -H "Authorization: Bearer $cloudflare_bearer" \
      -H "Content-Type: application/json" | jq -c '.result[]')
    while IFS= read -r dns_record ; do
      dns_record_id=$(echo "$dns_record" | jq -r '.id' | xargs)
      if [ "$dns_record_id" == "" ]; then
        continue
      fi
      dns_record_type=$(echo "$dns_record" | jq -r '.type' | xargs)
      dns_record_name=$(echo "$dns_record" | jq -r '.name' | xargs)
      dns_record_content=$(echo "$dns_record" | jq -r '.content' | xargs)
      dns_record_proxied=$(echo "$dns_record" | jq -r '.proxied' | xargs)
      #dns_record_ttl=$(echo "$dns_record" | jq -r '.ttl' | xargs)

      echo "Found $dns_record_type record for $dns_record_name with $dns_record_content"
      if [ "$dns_record_type" == "CAA" ] && [ "$dns_record_content" == "0 issue letsencrypt.org" ]; then
        if [[ " ${main_domains_copy[*]} " =~ [[:space:]]${dns_record_name}[[:space:]] ]]; then
          main_domains_copy=($(echo "${main_domains_copy[@]}" | sed "s/$dns_record_name//"))
        fi
      fi
      echo ""
    done <<< "$cloudflare_dns_records"
    for domain in "${main_domains_copy[@]}"; do
      json_data=$(jq -n \
        --arg name "$domain" \
        --arg content "0 issue \"letsencrypt.org\"" \
        --arg comment "$comment" \
        '{type:"CAA",name:$name,content:$content,ttl:60,comment:$comment,"data":{"flags":0,"tag":"issue","value":"letsencrypt.org"}}')
      echo "$json_data"
      read -p "Create DNS record? (y/N) " decision
      if [ "$decision" == "Y" ] || [ "$decision" == "y" ]; then
        curl --request POST \
          --url "https://api.cloudflare.com/client/v4/zones/$cloudflare_zone/dns_records" \
          -H "Authorization: Bearer $cloudflare_bearer" \
          -H 'Content-Type: application/json' \
          --data "$json_data"
      fi
    done
  fi
fi

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
