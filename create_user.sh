#!/bin/bash

# If a username is provided, don't create a new user
if [ -n "$PAM_USER" ] && [ "$PAM_USER" != "sshd" ]; then
    exit 0
fi

# Generate a random username
USERNAME=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)

# Check if the user already exists
if id "$USERNAME" &>/dev/null; then
    exit 0
fi

# Create the user with a home directory and set the shell to /bin/bash
useradd -m -s /bin/bash $USERNAME
