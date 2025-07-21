#!/usr/bin/env python3
"""
Add deployment secrets to a Gitea repository
"""
import requests
import base64
import sys
import getpass

def add_secret(gitea_url, token, owner, repo, secret_name, secret_value):
    """Add a secret to a Gitea repository"""
    headers = {
        'Authorization': f'token {token}',
        'Content-Type': 'application/json'
    }
    
    # Gitea Actions secrets API endpoint
    url = f"{gitea_url}/api/v1/repos/{owner}/{repo}/actions/secrets/{secret_name}"
    
    # Create/update the secret
    data = {
        "data": secret_value
    }
    
    response = requests.put(url, headers=headers, json=data)
    
    if response.status_code in [201, 204]:
        print(f"✓ Successfully added secret '{secret_name}' to {owner}/{repo}")
        return True
    else:
        print(f"✗ Failed to add secret '{secret_name}': {response.status_code}")
        print(f"  {response.text}")
        return False

def main():
    print("=== Add K3s Deployment Secrets to Gitea Repository ===\n")
    
    # Get repository details
    gitea_url = input("Gitea URL (default: https://ci.gmac.io): ").strip() or "https://ci.gmac.io"
    owner = input("Repository owner (default: mackieg): ").strip() or "mackieg"
    repo = input("Repository name: ").strip()
    
    if not repo:
        print("Repository name is required!")
        sys.exit(1)
    
    # Get Gitea token
    gitea_token = getpass.getpass("Gitea API token: ")
    
    print(f"\nAdding secrets to: {owner}/{repo}")
    
    # Read kubeconfig
    try:
        with open('kubeconfig-base64.txt', 'r') as f:
            kubeconfig_base64 = f.read().strip()
    except FileNotFoundError:
        print("Error: kubeconfig-base64.txt not found!")
        print("Run: cat ~/.kube/k3s-gmac.yaml | base64 > kubeconfig-base64.txt")
        sys.exit(1)
    
    # Add KUBECONFIG secret
    success1 = add_secret(gitea_url, gitea_token, owner, repo, "KUBECONFIG", kubeconfig_base64)
    
    # Add GITEA_TOKEN secret (same token for registry access)
    success2 = add_secret(gitea_url, gitea_token, owner, repo, "GITEA_TOKEN", gitea_token)
    
    if success1 and success2:
        print(f"\n✅ All secrets added successfully!")
        print(f"\nNext steps:")
        print(f"1. Copy a workflow file to {repo}/.gitea/workflows/deploy.yml")
        print(f"2. Push to main branch to trigger deployment")
        print(f"3. Your app will be available at https://{repo}.gmac.io")
    else:
        print(f"\n⚠️  Some secrets failed to add. Check the errors above.")

if __name__ == "__main__":
    main()