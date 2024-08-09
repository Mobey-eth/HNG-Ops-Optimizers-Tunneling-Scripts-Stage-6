#!/bin/bash

DOMAIN="mobyme.site"
LOG_FILE="/home/tunnel/tunnel_debug.log"
PORTS_FILE="/home/tunnel/used_ports.txt"
BASE_PORT=10000

echo "$(date): Script started" >> "$LOG_FILE"

function generate_subdomain() {
    cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1
}

function log() {
    echo "$(date): $1" >> "$LOG_FILE"
}

function get_available_port() {
    while true; do
        PORT=$((BASE_PORT + RANDOM % 55535))
        if ! grep -q "^$PORT$" "$PORTS_FILE" 2>/dev/null; then
            echo "$PORT" >> "$PORTS_FILE"
            echo "$PORT"
            return
        fi
    done
}

function remove_port() {
    local port=$1
    sed -i "/^$port$/d" "$PORTS_FILE"
}

function handle_connection() {
    local subdomain=$(generate_subdomain)
    local local_port=$1
    local remote_port=$(get_available_port)

    log "Handling connection: $subdomain.$DOMAIN -> localhost:$local_port (Remote port: $remote_port)"
    echo "Tunnel established: https://$subdomain.$DOMAIN" | tee /home/tunnel/tunnel_url.txt

    # Set up iptables rule for this specific subdomain
    sudo iptables -t nat -A PREROUTING -p tcp -d "$subdomain.$DOMAIN" --dport 80 -j REDIRECT --to-port $remote_port
    sudo iptables -t nat -A PREROUTING -p tcp -d "$subdomain.$DOMAIN" --dport 443 -j REDIRECT --to-port $remote_port

    # Update Nginx configuration
    sudo tee /etc/nginx/sites-available/$subdomain.conf > /dev/null <<EOF
server {
    listen 80;
    server_name $subdomain.$DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $subdomain.$DOMAIN;

    ssl_certificate /etc/letsencrypt/live/mobyme.site/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mobyme.site/privkey.pem;

    location / {
        proxy_pass http://localhost:$remote_port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    sudo ln -s /etc/nginx/sites-available/$subdomain.conf /etc/nginx/sites-enabled/
    sudo nginx -s reload

    log "Tunnel active. Press Ctrl+C to exit."
    # Keep the script running
    while true; do
        sleep 10
    done

    # Cleanup
    sudo rm /etc/nginx/sites-enabled/$subdomain.conf /etc/nginx/sites-available/$subdomain.conf
    sudo nginx -s reload
    sudo iptables -t nat -D PREROUTING -p tcp -d "$subdomain.$DOMAIN" --dport 80 -j REDIRECT --to-port $remote_port
    sudo iptables -t nat -D PREROUTING -p tcp -d "$subdomain.$DOMAIN" --dport 443 -j REDIRECT --to-port $remote_port
    remove_port $remote_port
}

log "Script running. Waiting for connection."
handle_connection 3000

log "Script ended"
