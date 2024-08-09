### Tunnel Service Documentation

---

## Project Overview

### Objective:
Create a streamlined tunneling service as an alternative to `ngrok` and `serveo.net`, using SSH reverse forwarding to offer dynamic public URLs for local applications.

### Key Features:
- **SSH Reverse Forwarding:** Securely forward local ports using SSH reverse tunneling.
- **Proxy Management:** Efficiently manage HTTP 80.
- **Wildcard Domains:** Support a variety of subdomains for greater flexibility.
- **Automatic Port Management:** Dynamically allocate and manage ports for reverse forwarding.

---
## Installation and Setup For TUNNEL SERVICE 1

### Prerequisites
- Ubuntu 20.04 or later
- Root access to the server
- A domain name (e.g., mobyme.site)

### Step 1: Update and Install Dependencies
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y nginx certbot python3-certbot-nginx
```

### Step 2: DNS Configuration
1. Log in to your domain registrar's DNS management page.
2. Add an A record pointing your domain (e.g., mobyme.site) to your server's IP address.
3. Add a wildcard CNAME record:
   - Host: *
   - Points to: @ (or your domain name)

### Step 3: SSL Certificate Setup
We'll use the manual DNS challenge method for obtaining a wildcard certificate:

```bash
sudo certbot certonly --manual --preferred-challenges=dns -d mobyme.site -d *.mobyme.site
```

Follow the prompts and add the TXT record to your DNS configuration when asked. Wait for DNS propagation before continuing.

### Step 4: Nginx Configuration
Create and edit the Nginx configuration file:

```bash
sudo nano /etc/nginx/sites-available/tunnel
```

Add the following content:

```nginx
server {
    listen 80;
    server_name *.mobyme.site;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl default_server;
    server_name *.mobyme.site;

    ssl_certificate /etc/letsencrypt/live/mobyme.site/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mobyme.site/privkey.pem;

    location / {
        return 404;
    }
}

include /etc/nginx/sites-enabled/*.conf;
```

Enable the configuration:

```bash
sudo ln -s /etc/nginx/sites-available/tunnel /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### Step 5: SSH Configuration
Edit the SSH configuration file:

```bash
sudo nano /etc/ssh/sshd_config
```

Add or modify the following lines:

```
Match User tunnel
    ForceCommand /usr/local/bin/tunnel_service_1.sh
    PermitTunnel yes
    GatewayPorts yes
    AllowTcpForwarding remote
```

Restart the SSH service:

```bash
sudo systemctl restart sshd
```

### Step 6: Create Tunnel User
```bash
sudo adduser --disabled-password --gecos "" tunnel
```

### Step 7: Set Up Tunnel Service Script
Create and edit the tunnel service script:

```bash
sudo nano /usr/local/bin/tunnel_service_1.sh
```

Add the content of the tunnel service 1 script in the repository.

Make the script executable:

```bash
sudo chmod +x /usr/local/bin/tunnel_service_1.sh
```

---
## Installation and Setup For TUNNEL SERVICE 2

### Prerequisites
- Ubuntu 20.04 or later
- A domain name (e.g., devobs.me)

### Step 1: Update and Install Dependencies
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y openssh-server
```

### Step 2: SSH Configuration

```bash
sudo nano /etc/ssh/sshd_config
```

Add or modify the following lines:

```
PasswordAuthentication yes
PermitEmptyPasswords yes
ChallengeResponseAuthentication no
PrintMod no
PrintLastLog no
Match User no-auth-user
    ForceCommand /usr/local/bin/tunnel_service_2.sh
    PermitTunnel yes
    GatewayPorts yes
    AllowTcpForwarding yes
```

Restart the SSH service:

```bash
sudo systemctl restart ssh
```

### Step 3: Create no-auth-user User
```bash
sudo adduser --disabled-password --gecos "" no-auth-user
```

### Step 4: Set Up Tunnel Service Script
Create and edit the tunnel service script:

```bash
sudo nano /usr/local/bin/tunnel_service_2.sh
```

Add the content of the tunnel service 2 script in the repository.

Make the script executable:

```bash
sudo chmod +x /usr/local/bin/tunnel_service_2.sh
```

---
## How the Tunnel Service Works (FOR TUNNEL SERVICE 1)

### 1. Initialization and Setup

The script begins by setting the domain name, log file location, and a base port for dynamic allocation:

```bash
#!/bin/bash

DOMAIN="mobyme.site"
LOG_FILE="/home/tunnel/tunnel_debug.log"
PORTS_FILE="/home/tunnel/used_ports.txt"
BASE_PORT=10000

echo "$(date): Script started" >> "$LOG_FILE"
```

### 2. Generating Random Subdomains

A random subdomain is generated for each tunnel session:

```bash
function generate_subdomain() {
    cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1
}
```

### 3. Logging and Port Management

Logging is streamlined with a function that appends entries to the log file:

```bash
function log() {
    echo "$(date): $1" >> "$LOG_FILE"
}
```

Ports are dynamically allocated and managed:

```bash
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
```

### 4. Handling Connections

A new tunnel is set up by generating a random subdomain, allocating a port, and configuring iptables and Nginx:

```bash
function handle_connection() {
    local subdomain=$(generate_subdomain)
    local local_port=$1
    local remote_port=$(get_available_port)

    log "Handling connection: $subdomain.$DOMAIN -> localhost:$local_port (Remote port: $remote_port)"
    echo "Tunnel established: https://$subdomain.$DOMAIN" | tee /home/tunnel/tunnel_url.txt

    # Set up iptables rule
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
```

### 5. Running the Script

The main script triggers the `handle_connection` function with the desired port:

```bash
log "Script running. Waiting for connection."
handle_connection 3000
log "Script ended"
```
---

### Step 8: Configure Sudo Permissions
Edit the sudoers file for the tunnel user:

```bash
sudo visudo -f /etc/sudoers.d/tunnel
```

Add the following lines:

```
tunnel ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/nginx/sites-available/*.conf
tunnel ALL=(ALL) NOPASSWD: /usr/bin/ln -s /etc/nginx/sites-available/*.conf /etc/nginx/sites-enabled/
tunnel ALL=(ALL) NOPASSWD: /usr/sbin/nginx -s reload
tunnel ALL=(ALL) NOPASSWD: /sbin/iptables -t nat -A PREROUTING -p tcp -d *.mobyme.site --dport 80 -j REDIRECT --to-port *
tunnel ALL=(ALL) NOPASSWD: /sbin/iptables -t nat -A PREROUTING -p tcp -d *.mobyme.site --dport 443 -j REDIRECT --to-port *
tunnel ALL=(ALL) NOPASSWD: /sbin/iptables -t nat -D PREROUTING -p tcp -d *.mobyme.site --dport 80 -j REDIRECT --to-port *
tunnel ALL=(ALL) NOPASSWD: /sbin/iptables -t nat -D PREROUTING -p tcp -d *.mobyme.site --dport 443 -j REDIRECT --to-port *
```
---
## How the Tunnel Service Works (FOR TUNNEL SERVICE 2)

The `handle_forwarding.sh` script is designed to facilitate SSH port forwarding by:

- Determining the port on which the SSH server is listening for incoming connections.
- Outputting a message indicating the port and IP address where the forwarded connections are being directed.
- Keeping the SSH session alive to maintain the tunnel.

### Script Breakdown

### Retrieve Parent Process ID (PID) of SSHD

```bash
PARENT_PID=$(ps -o ppid= -p $$ | tr -d ' ')
```

- ps -o ppid= -p $$ retrieves the parent process ID (PID) of the current shell, which should be the sshd process handling the SSH connection.
- tr -d ' ' removes any whitespace from the PID output to ensure it's clean and correctly formatted.

### Find and Extract the Forwarded Port

```
PORT=$(sudo /usr/bin/ss -tulnp | grep "pid=$PARENT_PID" | awk '{print $5}' | awk -F: '{print $2}' | sort -n | uniq | tr '\n' ' ' | xargs)
```

### Output the Forwarding Information

```
echo "Forwarding TCP connections from http://devobs.me:${PORT}"
```




## Usage

To start the tunneling service, use the following SSH command:

```bash
ssh -R 8080:localhost:3000 tunnel@mobyme.site
```

This will reverse forward your local application on port 3000 to a dynamically generated subdomain on `mobyme.site`, making it publicly accessible.

---

## Troubleshooting

1. If you encounter permission issues, ensure the tunnel user has the correct sudo permissions.
2. Check Nginx error logs: `sudo tail -f /var/log/nginx/error.log`
3. Verify iptables rules: `sudo iptables -t nat -L PREROUTING`
4. Ensure the SSL certificate is valid and properly configured.

## Conclusion

This tunneling service is made to be an alternative to `ngrok` and `serveo.net`, offering secure, dynamic URLs for accessing local applications using SSH reverse forwarding and Nginx proxy management.
