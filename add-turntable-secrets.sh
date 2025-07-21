#!/bin/bash
# Add secrets to turntable.bot repository

cd /Volumes/dev/gmac-io-ci
source venv/bin/activate

# Use the Python script with input piped
echo -e "\nmackieg\nturntable.bot\n6c0c69be9e3ac745fd234a47e276df22955268ba" | python add-gitea-secrets.py