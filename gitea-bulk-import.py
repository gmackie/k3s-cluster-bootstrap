#!/usr/bin/env python3

import requests
import json
import time
import sys
import getpass

# Configuration
GITEA_URL = "https://ci.gmac.io"

def get_credentials():
    """Get credentials from user"""
    print("=== Gitea Bulk Import Tool ===\n")
    
    print("Step 1: Gitea API Token")
    print("Get it from: https://ci.gmac.io/user/settings/applications")
    print("Click 'Generate New Token' with 'repo' scope")
    gitea_token = getpass.getpass("Enter your Gitea API token: ").strip()
    
    print("\nStep 2: GitHub Username")
    github_user = input("Enter your GitHub username: ").strip()
    
    print("\nStep 3: GitHub Token (optional, needed for private repos)")
    print("Get it from: https://github.com/settings/tokens")
    print("Create token with 'repo' scope")
    print("Press Enter to skip if you only want to import public repos")
    github_token = getpass.getpass("Enter your GitHub token (or press Enter): ").strip()
    
    return gitea_token, github_user, github_token

def get_github_repos(github_user, github_token):
    """Fetch all repos from GitHub"""
    repos = []
    page = 1
    
    while True:
        url = f"https://api.github.com/users/{github_user}/repos"
        params = {"page": page, "per_page": 100}
        headers = {}
        
        if github_token:
            headers["Authorization"] = f"token {github_token}"
        
        response = requests.get(url, params=params, headers=headers)
        
        if response.status_code != 200:
            print(f"Error fetching GitHub repos: {response.status_code}")
            print(response.text)
            return []
        
        data = response.json()
        
        if not data:
            break
            
        repos.extend(data)
        page += 1
    
    return repos

def import_repo(repo, gitea_token, github_token):
    """Import a single repo to Gitea"""
    clone_url = repo['clone_url']
    if github_token and repo['private']:
        clone_url = clone_url.replace('https://', f'https://{github_token}@')
    
    data = {
        "clone_addr": clone_url,
        "repo_name": repo['name'],
        "description": repo['description'] or "",
        "private": repo['private'],
        "mirror": False,
        "wiki": True,
        "issues": True,
        "pull_requests": True,
        "releases": True,
        "labels": True,
        "milestones": True
    }
    
    headers = {
        "Authorization": f"token {gitea_token}",
        "Content-Type": "application/json"
    }
    
    response = requests.post(
        f"{GITEA_URL}/api/v1/repos/migrate",
        headers=headers,
        json=data
    )
    
    if response.status_code == 201:
        print(f"✓ Imported: {repo['name']}")
    elif response.status_code == 409:
        print(f"⚠ Already exists: {repo['name']}")
    else:
        print(f"✗ Failed: {repo['name']} - {response.text}")
    
    return response.status_code

def filter_repos(repos):
    """Allow user to filter which repos to import"""
    print("\nRepositories found:")
    public_repos = [r for r in repos if not r['private']]
    private_repos = [r for r in repos if r['private']]
    
    print(f"  Public: {len(public_repos)}")
    print(f"  Private: {len(private_repos)}")
    
    if private_repos:
        print("\nImport options:")
        print("1. All repositories")
        print("2. Public repositories only")
        print("3. Select individually")
        choice = input("\nYour choice (1-3): ").strip()
        
        if choice == "2":
            repos = public_repos
        elif choice == "3":
            selected_repos = []
            print("\nSelect repositories to import (y/n/q to quit):")
            for repo in repos:
                response = input(f"  {repo['name']} {'(private)' if repo['private'] else '(public)'}: ").lower()
                if response == 'q':
                    break
                elif response == 'y':
                    selected_repos.append(repo)
            repos = selected_repos
    
    return repos

def main():
    # Get credentials
    gitea_token, github_user, github_token = get_credentials()
    
    print(f"\nFetching repos from GitHub user: {github_user}")
    repos = get_github_repos(github_user, github_token)
    print(f"Found {len(repos)} repositories")
    
    if not repos:
        print("No repositories found!")
        return
    
    # Filter repos
    repos = filter_repos(repos)
    
    if not repos:
        print("No repositories selected for import")
        return
    
    # Show what will be imported
    print(f"\nWill import {len(repos)} repositories:")
    for repo in repos[:10]:  # Show first 10
        print(f"  - {repo['name']} {'(private)' if repo['private'] else '(public)'}")
    if len(repos) > 10:
        print(f"  ... and {len(repos) - 10} more")
    
    confirm = input("\nProceed with import? (y/N): ")
    if confirm.lower() != 'y':
        print("Cancelled")
        return
    
    print("\nStarting import...")
    success = 0
    failed = 0
    skipped = 0
    
    for i, repo in enumerate(repos):
        print(f"\n[{i+1}/{len(repos)}] ", end='')
        status = import_repo(repo, gitea_token, github_token)
        
        if status == 201:
            success += 1
        elif status == 409:
            skipped += 1
        else:
            failed += 1
        
        # Be nice to the API
        time.sleep(2)
    
    print(f"\n\nImport complete!")
    print(f"✓ Success: {success}")
    print(f"⚠ Skipped (already exists): {skipped}")
    print(f"✗ Failed: {failed}")
    print(f"\nVisit https://ci.gmac.io to see your repositories")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nImport cancelled by user")
        sys.exit(0)
    except Exception as e:
        print(f"\nError: {e}")
        sys.exit(1)