#!/bin/bash

IP="127.0.0.1"
PORT="2222"
USER="aditya"

echo "Testing SSH access..."
ssh -o BatchMode=yes -o ConnectTimeout=5 -p $PORT $USER@$IP "echo OK" || exit 1

echo "Testing root login (should fail)..."
if ssh -o ConnectTimeout=5 -p $PORT root@$IP exit 2>/dev/null; then
  echo "Root login should be disabled"
  exit 1
fi

echo "Testing password auth (should fail)..."
if ssh -o PreferredAuthentications=password -o ConnectTimeout=5 -p $PORT $USER@$IP exit 2>/dev/null; then
  echo "Password auth should be disabled"
  exit 1
fi

echo "Testing sudo..."
ssh -p $PORT $USER@$IP "sudo whoami" | grep root || exit 1

echo "Testing firewall..."
ssh -p $PORT $USER@$IP "sudo ufw status" | grep active || exit 1

echo "Testing SSH config inside VM..."
ssh -p $PORT $USER@$IP "grep -E 'PermitRootLogin|PasswordAuthentication' /etc/ssh/sshd_config" | grep -E "no" || exit 1

echo "All tests passed!"
