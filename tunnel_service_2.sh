#!/bin/bash

# Get the PID of the current shell's parent process, which should be the sshd process
PARENT_PID=$(ps -o ppid= -p $$ | tr -d ' ')

# Extract the remote port using the PID of the SSHD Process
PORT=$(sudo /usr/bin/ss -tulnp | grep "pid=$PARENT_PID" | awk '{print $5}' | awk -F: '{print $2}' | sort -n | uniq | tr '\n' ' ' | xargs)

# Output the forwarding information
echo "Forwarding TCP connections from http://devobs.me:${PORT}"

# Keep the SSH session alive to maintain the tunnel
while true; do sleep infinity; done
