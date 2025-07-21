#!/usr/bin/env python3
"""
Import 10 most recently committed GitHub repositories to Gitea with progress
"""
import requests
import subprocess
import os
import sys
from datetime import datetime

# Get credentials from environment or command line
GITHUB_TOKEN = os.environ.get('GITHUB_TOKEN', sys.argv[1] if len(sys.argv) > 1 else None)
GITEA_TOKEN = os.environ.get('GITEA_KEY', sys.argv[2] if len(sys.argv) > 2 else None)
GITEA_URL = "https://ci.gmac.io"

if not GITHUB_TOKEN or not GITEA_TOKEN:
    print("Usage: python import-with-progress.py <GITHUB_TOKEN> <GITEA_TOKEN>")
    print("Or set GITHUB_TOKEN and GITEA_KEY environment variables")
    exit(1)

def get_github_username():
    """Get the authenticated user's username"""
    headers = {
        'Authorization': f'token {GITHUB_TOKEN}',
        'Accept': 'application/vnd.github.v3+json'
    }
    response = requests.get('https://api.github.com/user', headers=headers)
    if response.status_code == 200:
        return response.json()['login']
    return None

def get_github_repos():
    """Fetch repos for authenticated user"""
    headers = {
        'Authorization': f'token {GITHUB_TOKEN}',
        'Accept': 'application/vnd.github.v3+json'
    }
    
    url = 'https://api.github.com/user/repos?sort=pushed&direction=desc&per_page=10'
    response = requests.get(url, headers=headers)
    
    if response.status_code == 200:
        return response.json()
    return []

def import_repository(github_repo):
    """Import a single repository"""
    print(f"\n{'='*60}")
    print(f"Importing: {github_repo['name']}")
    
    # First check if repo exists
    headers = {'Authorization': f'token {GITEA_TOKEN}'}
    check_url = f"{GITEA_URL}/api/v1/repos/{get_github_username()}/{github_repo['name']}"
    check_response = requests.get(check_url, headers=headers)
    
    if check_response.status_code == 200:
        print(f"  Repository already exists in Gitea, skipping...")
        return True
    
    # Create repo
    create_data = {
        'name': github_repo['name'],
        'description': github_repo['description'] or '',
        'private': github_repo['private'],
        'auto_init': False
    }
    
    create_url = f'{GITEA_URL}/api/v1/user/repos'
    headers['Content-Type'] = 'application/json'
    
    print(f"  Creating repository in Gitea...")
    create_response = requests.post(create_url, headers=headers, json=create_data)
    
    if create_response.status_code != 201:
        print(f"  ✗ Error creating repo: {create_response.status_code}")
        print(f"  {create_response.text}")
        return False
    
    gitea_repo = create_response.json()
    print(f"  ✓ Created repository")
    
    # Clone and push
    temp_dir = f"/tmp/gitea-{github_repo['name']}"
    
    try:
        # Cleanup
        subprocess.run(['rm', '-rf', temp_dir], check=False, capture_output=True)
        
        # Clone with progress
        print(f"  Cloning from GitHub (this may take a moment)...")
        github_clone_url = f"https://{GITHUB_TOKEN}@github.com/{github_repo['full_name']}.git"
        
        # Show progress by not capturing output
        result = subprocess.run(['git', 'clone', '--mirror', github_clone_url, temp_dir], 
                              capture_output=False)
        
        if result.returncode != 0:
            print(f"  ✗ Failed to clone from GitHub")
            return False
        
        print(f"  ✓ Cloned successfully")
        
        # Push to Gitea
        print(f"  Pushing to Gitea...")
        os.chdir(temp_dir)
        
        gitea_push_url = f"https://gitea:{GITEA_TOKEN}@ci.gmac.io/{gitea_repo['full_name']}.git"
        subprocess.run(['git', 'remote', 'set-url', 'origin', gitea_push_url], 
                     check=True, capture_output=True)
        
        # Push with progress
        result = subprocess.run(['git', 'push', '--mirror'], capture_output=False)
        
        if result.returncode == 0:
            print(f"  ✓ Successfully imported {github_repo['name']}")
            return True
        else:
            print(f"  ✗ Failed to push to Gitea")
            return False
            
    except Exception as e:
        print(f"  ✗ Error: {e}")
        return False
    finally:
        os.chdir('/')
        subprocess.run(['rm', '-rf', temp_dir], check=False, capture_output=True)

def main():
    print("=== Import Recent GitHub Repos to Gitea ===\n")
    
    # Get username
    username = get_github_username()
    if not username:
        print("Failed to authenticate with GitHub")
        return
    
    print(f"GitHub user: {username}")
    print(f"Gitea URL: {GITEA_URL}")
    
    # Get repos
    print("\nFetching repositories...")
    repos = get_github_repos()
    
    if not repos:
        print("No repositories found")
        return
    
    print(f"\nFound {len(repos)} repositories to import")
    
    # Import each
    successful = 0
    failed = 0
    
    for i, repo in enumerate(repos, 1):
        print(f"\nProgress: {i}/{len(repos)}")
        if import_repository(repo):
            successful += 1
        else:
            failed += 1
    
    # Summary
    print(f"\n{'='*60}")
    print(f"Import Summary:")
    print(f"  Successful: {successful}")
    print(f"  Failed: {failed}")
    print(f"  Total: {len(repos)}")

if __name__ == "__main__":
    main()