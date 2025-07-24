#!/usr/bin/env python3
"""
Add deployment secrets to ClassBack Gitea repository
"""
import requests
import base64
import os
import subprocess

# Configuration
GITEA_URL = "https://ci.gmac.io"
GITEA_TOKEN = "6c0c69be9e3ac745fd234a47e276df22955268ba"
OWNER = "mackieg"
REPO = "classback"

def add_secret(secret_name, secret_value):
    """Add a secret to the Gitea repository"""
    headers = {
        'Authorization': f'token {GITEA_TOKEN}',
        'Content-Type': 'application/json'
    }
    
    url = f"{GITEA_URL}/api/v1/repos/{OWNER}/{REPO}/actions/secrets/{secret_name}"
    
    data = {
        "data": secret_value
    }
    
    response = requests.put(url, headers=headers, json=data)
    
    if response.status_code in [201, 204]:
        print(f"✓ Successfully added secret '{secret_name}'")
        return True
    else:
        print(f"✗ Failed to add secret '{secret_name}': {response.status_code}")
        print(f"  {response.text}")
        return False

def main():
    print("=== Adding K3s Deployment Secrets to ClassBack ===\n")
    
    # Read kubeconfig
    try:
        with open('/Volumes/dev/gmac-io-ci/kubeconfig-base64.txt', 'r') as f:
            kubeconfig_base64 = f.read().strip()
    except FileNotFoundError:
        print("Error: kubeconfig-base64.txt not found!")
        return
    
    # Generate JWT secret
    jwt_secret = subprocess.check_output(['openssl', 'rand', '-base64', '32']).decode().strip()
    print(f"Generated JWT secret: {jwt_secret[:10]}...")
    
    # Turso credentials from .env
    turso_url = "libsql://classback-gmackie.turso.io"
    turso_auth_token = "eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3NDI4MTY3MDEsImlkIjoiOWM5NGE5MDctZGMyMS00MGRhLWE4NTAtNDVlNDRjZmI1YWI3In0.3np8DxEljJWU3Q5ymbDdun4uROtZ-clJwwxMn3X-4JjGdDSO106pUzEhV8TAVLkXn5Tnvs3vhQAjEWVyig9LAg"
    
    # Add all secrets
    secrets = {
        "KUBECONFIG": kubeconfig_base64,
        "GITEA_TOKEN": GITEA_TOKEN,
        "JWT_SECRET": jwt_secret,
        "TURSO_URL": turso_url,
        "TURSO_AUTH_TOKEN": turso_auth_token
    }
    
    all_success = True
    for name, value in secrets.items():
        if not add_secret(name, value):
            all_success = False
    
    if all_success:
        print(f"\n✅ All secrets added successfully!")
        print(f"\nDeployment information:")
        print(f"- Production: https://api.classcheck.io")
        print(f"- Staging: https://staging-api-pr-{{PR_NUMBER}}.classcheck.io")
        print(f"\nThe deployment will trigger automatically on the next push.")
    else:
        print(f"\n⚠️  Some secrets failed to add. Check the errors above.")

if __name__ == "__main__":
    main()