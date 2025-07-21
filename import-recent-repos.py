#!/usr/bin/env python3
"""
Import 10 most recently committed GitHub repositories to Gitea
"""
import requests
import json
import subprocess
import os
from datetime import datetime
import getpass

def get_github_repos(username, token):
    """Fetch all repos for a user sorted by last commit"""
    headers = {
        'Authorization': f'token {token}',
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
        
        # We only need the 10 most recent, so stop after we have enough
        if len(repos) >= 10:
            break
    
    # Return only the 10 most recently pushed repos
    return repos[:10]

def create_gitea_repo(gitea_url, gitea_token, repo_data):
    """Create a repository in Gitea"""
    headers = {
        'Authorization': f'token {gitea_token}',
        'Content-Type': 'application/json'
    }
    
    # Prepare repo data for Gitea
    gitea_repo_data = {
        'name': repo_data['name'],
        'description': repo_data['description'] or '',
        'private': repo_data['private'],
        'auto_init': False,  # We'll push from GitHub
        'gitignores': '',
        'license': '',
        'readme': ''
    }
    
    url = f'{gitea_url}/api/v1/user/repos'
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

def import_repository(github_repo, gitea_url, gitea_token):
    """Import a single repository from GitHub to Gitea"""
    print(f"\n{'='*60}")
    print(f"Importing: {github_repo['name']}")
    print(f"Description: {github_repo['description'] or 'No description'}")
    print(f"Last pushed: {github_repo['pushed_at']}")
    print(f"Private: {github_repo['private']}")
    
    # Create repo in Gitea
    gitea_repo = create_gitea_repo(gitea_url, gitea_token, github_repo)
    
    if gitea_repo:
        print(f"✓ Created repository in Gitea")
        clone_url = gitea_repo['clone_url']
        
        # Clone from GitHub and push to Gitea
        temp_dir = f"/tmp/gitea-import-{github_repo['name']}"
        
        try:
            # Remove temp dir if it exists
            subprocess.run(['rm', '-rf', temp_dir], check=False)
            
            # Clone from GitHub
            print(f"  Cloning from GitHub...")
            subprocess.run(['git', 'clone', '--mirror', github_repo['clone_url'], temp_dir], 
                         check=True, capture_output=True)
            
            # Push to Gitea
            print(f"  Pushing to Gitea...")
            os.chdir(temp_dir)
            
            # Update the remote URL to use Gitea
            gitea_push_url = clone_url.replace('https://', f'https://gitea:{gitea_token}@')
            subprocess.run(['git', 'remote', 'set-url', 'origin', gitea_push_url], 
                         check=True, capture_output=True)
            
            # Push all branches and tags
            subprocess.run(['git', 'push', '--mirror'], check=True, capture_output=True)
            
            print(f"✓ Successfully imported {github_repo['name']}")
            
            # Cleanup
            os.chdir('..')
            subprocess.run(['rm', '-rf', temp_dir], check=False)
            
            return True
            
        except subprocess.CalledProcessError as e:
            print(f"✗ Error during import: {e}")
            if e.stderr:
                print(f"  {e.stderr.decode()}")
            # Cleanup on error
            subprocess.run(['rm', '-rf', temp_dir], check=False)
            return False
    
    return False

def main():
    print("=== Import 10 Most Recent GitHub Repos to Gitea ===\n")
    
    # Get credentials
    print("GitHub Credentials:")
    github_username = input("GitHub username: ")
    github_token = getpass.getpass("GitHub personal access token: ")
    
    print("\nGitea Credentials:")
    gitea_url = input("Gitea URL (default: https://ci.gmac.io): ").strip() or "https://ci.gmac.io"
    gitea_token = getpass.getpass("Gitea API token: ")
    
    # Fetch recent repos
    print("\nFetching your 10 most recently updated GitHub repositories...")
    repos = get_github_repos(github_username, github_token)
    
    if not repos:
        print("Failed to fetch repositories")
        return
    
    print(f"\nFound {len(repos)} recent repositories:")
    for i, repo in enumerate(repos, 1):
        print(f"{i:2d}. {repo['name']} - Last pushed: {repo['pushed_at']}")
    
    # Confirm import
    confirm = input("\nProceed with import? (y/N): ")
    if confirm.lower() != 'y':
        print("Import cancelled")
        return
    
    # Import each repository
    successful = 0
    failed = 0
    
    for repo in repos:
        if import_repository(repo, gitea_url, gitea_token):
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
        print(f"\nYour repositories are now available at {gitea_url}")

if __name__ == "__main__":
    main()