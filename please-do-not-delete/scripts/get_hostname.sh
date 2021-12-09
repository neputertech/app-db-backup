#!/bin/bash

# Get public IP address
function pub() {
    curl -s ipinfo.io | grep '"ip' | awk '{print $2}' | sed -e 's/"//g' -e 's/,//g'
}

# Get local IP address
function loc() {
    ip -o route get to 8.8.8.8 | sed -n 's/.*src \([0-9.]\+\).*/\1/p'
} 

# Get hostname
function hostname() {
    cat /etc/hostname
} 

$@
