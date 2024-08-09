#!/bin/bash

USERNAME=$(echo "$PAM_USER")

# Check if user exists and create if not
if ! id -u "$USERNAME" >/dev/null 2>&1; then
    sudo useradd -m "$USERNAME"
fi
