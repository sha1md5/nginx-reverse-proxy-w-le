# Setup
1.
```shell
docker network create nginx-reverse-proxy
```
2. Configure vhosts based on examples in *./nginx-confs/vhosts/*

# Add other containers to same proxy network
```shell
docker network connect nginx-reverse-proxy {CONTAINER_NAME}
```
Then add vhost configuration

# Reloading nginx to apply new configuration
Simply restart container or run
```shell
docker compose exec nginx-reverse-proxy nginx -s reload
``` 


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



https://dash.cloudflare.com/profile/api-tokens
https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-list-dns-records
https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-dns-record-details
https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-patch-dns-record


WIP - script to update cloudflared A record IP
#!/bin/bash

# Cloudflare API credentials and identifiers
CF_API_KEY="your_cloudflare_api_key"
CF_EMAIL="your_cloudflare_email"
ZONE_ID="your_zone_id"
RECORD_ID="your_record_id"
RECORD_NAME="your_record_name" # e.g., "example.com" or "sub.example.com"

# Get the current public IP address of your machine
CURRENT_IP=$(curl -s http://ipv4.icanhazip.com)

type=TXT&name=$RECORD_NAME
# Fetch the current A record details
RECORD_DETAILS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
     -H "X-Auth-Email: $CF_EMAIL" \
     -H "X-Auth-Key: $CF_API_KEY" \
     -H "Content-Type: application/json")

# Extract the current IP address from the A record details
RECORD_IP=$(echo $RECORD_DETAILS | jq -r '.result.content')

# Check if the current IP address is the same as the record IP
if [ "$CURRENT_IP" = "$RECORD_IP" ]; then
  echo "The IP address has not changed."
else
  # Update the A record with the new IP address
  UPDATE_RESULT=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
       -H "X-Auth-Email: $CF_EMAIL" \
       -H "X-Auth-Key: $CF_API_KEY" \
       -H "Content-Type: application/json" \
       --data "{\"type\":\"A\",\"name\":\"$RECORD_NAME\",\"content\":\"$CURRENT_IP\",\"ttl\":120,\"proxied\":false}")

  if echo $UPDATE_RESULT | grep -q '"success":true'; then
    echo "The DNS record has been updated to $CURRENT_IP."
  else
    echo "Failed to update the DNS record. Response: $UPDATE_RESULT"
  fi
fi
