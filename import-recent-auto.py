#!/usr/bin/env python3
"""
Import 10 most recently committed GitHub repositories to Gitea
Uses environment variables for authentication
"""
import requests
import json
import subprocess
import os
from datetime import datetime

# Get credentials from environment
GITHUB_TOKEN = os.environ.get('GITHUB_TOKEN')
GITEA_TOKEN = os.environ.get('GITEA_KEY')
GITEA_URL = "https://ci.gmac.io"

if not GITHUB_TOKEN or not GITEA_TOKEN:
    print("Error: Please set GITHUB_TOKEN and GITEA_KEY environment variables")
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
    else:
        print(f"Error getting GitHub username: {response.status_code}")
        return None

def get_github_repos():
    """Fetch all repos for authenticated user sorted by last commit"""
    headers = {
        'Authorization': f'token {GITHUB_TOKEN}',
        'Accept': 'application/vnd.github.v3+json'
    }
    
    repos = []
    page = 1
    
    while True:
        url = f'https://api.github.com/user/repos?page={page}&per_page=100&sort=pushed&direction=desc'
        response = requests.get(url, headers=headers)
        
        if response.status_code != 200:
            print(f"Error fetching repos: {response.status_code}")
            print(response.text)
            return []
        
        data = response.json()
        if not data:
            break
            
        repos.extend(data)
        page += 1
        
        # We only need the 10 most recent
        if len(repos) >= 10:
            break
    
    return repos[:10]

def create_gitea_repo(repo_data):
    """Create a repository in Gitea"""
    headers = {
        'Authorization': f'token {GITEA_TOKEN}',
        'Content-Type': 'application/json'
    }
    
    gitea_repo_data = {
        'name': repo_data['name'],
        'description': repo_data['description'] or '',
        'private': repo_data['private'],
        'auto_init': False,
        'gitignores': '',
        'license': '',
        'readme': ''
    }
    
    url = f'{GITEA_URL}/api/v1/user/repos'
    response = requests.post(url, headers=headers, json=gitea_repo_data)
    
    if response.status_code == 201:
        return response.json()
    elif response.status_code == 409:
        print(f"  Repository '{repo_data['name']}' already exists")
        return None
    else:
        print(f"  Error creating repo: {response.status_code}")
        print(f"  {response.text}")
        return None

def import_repository(github_repo):
    """Import a single repository from GitHub to Gitea"""
    print(f"\n{'='*60}")
    print(f"Importing: {github_repo['name']}")
    print(f"Description: {github_repo['description'] or 'No description'}")
    print(f"Last pushed: {github_repo['pushed_at']}")
    print(f"Private: {github_repo['private']}")
    
    gitea_repo = create_gitea_repo(github_repo)
    
    if gitea_repo:
        print(f"✓ Created repository in Gitea")
        clone_url = gitea_repo['clone_url']
        
        temp_dir = f"/tmp/gitea-import-{github_repo['name']}"
        
        try:
            subprocess.run(['rm', '-rf', temp_dir], check=False)
            
            print(f"  Cloning from GitHub...")
            # Use token in clone URL for private repos
            github_clone_url = github_repo['clone_url'].replace(
                'https://', f'https://{GITHUB_TOKEN}@'
            )
            subprocess.run(['git', 'clone', '--mirror', github_clone_url, temp_dir], 
                         check=True, capture_output=True)
            
            print(f"  Pushing to Gitea...")
            os.chdir(temp_dir)
            
            gitea_push_url = clone_url.replace('https://', f'https://gitea:{GITEA_TOKEN}@')
            subprocess.run(['git', 'remote', 'set-url', 'origin', gitea_push_url], 
                         check=True, capture_output=True)
            
            subprocess.run(['git', 'push', '--mirror'], check=True, capture_output=True)
            
            print(f"✓ Successfully imported {github_repo['name']}")
            
            os.chdir('..')
            subprocess.run(['rm', '-rf', temp_dir], check=False)
            
            return True
            
        except subprocess.CalledProcessError as e:
            print(f"✗ Error during import: {e}")
            if e.stderr:
                print(f"  {e.stderr.decode()}")
            subprocess.run(['rm', '-rf', temp_dir], check=False)
            return False
    
    return False

def main():
    print("=== Import 10 Most Recent GitHub Repos to Gitea ===\n")
    
    # Get GitHub username
    username = get_github_username()
    if not username:
        print("Failed to authenticate with GitHub")
        return
    
    print(f"Authenticated as: {username}")
    print(f"Target Gitea: {GITEA_URL}")
    
    # Fetch recent repos
    print("\nFetching your 10 most recently updated repositories...")
    repos = get_github_repos()
    
    if not repos:
        print("Failed to fetch repositories")
        return
    
    print(f"\nFound {len(repos)} recent repositories:")
    for i, repo in enumerate(repos, 1):
        print(f"{i:2d}. {repo['name']} - Last pushed: {repo['pushed_at']}")
    
    # Import each repository
    successful = 0
    failed = 0
    
    for repo in repos:
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
    
    if successful > 0:
        print(f"\nYour repositories are now available at {GITEA_URL}")

if __name__ == "__main__":
    main()