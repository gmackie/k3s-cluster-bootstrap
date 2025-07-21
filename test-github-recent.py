#!/usr/bin/env python3
"""
Test script to verify we can fetch recent GitHub repos
"""
import requests
import json
from datetime import datetime

def test_github_api(username):
    """Test fetching recent repos without authentication first"""
    url = f'https://api.github.com/users/{username}/repos?sort=pushed&direction=desc&per_page=10'
    
    headers = {
        'Accept': 'application/vnd.github.v3+json'
    }
    
    print(f"Testing GitHub API for user: {username}")
    print(f"URL: {url}\n")
    
    response = requests.get(url, headers=headers)
    
    if response.status_code == 200:
        repos = response.json()
        print(f"✓ Successfully fetched {len(repos)} repositories\n")
        
        print("10 Most Recently Updated Repos:")
        print("-" * 80)
        
        for i, repo in enumerate(repos[:10], 1):
            pushed_date = datetime.fromisoformat(repo['pushed_at'].replace('Z', '+00:00'))
            print(f"{i:2d}. {repo['name']:<40} Last pushed: {pushed_date.strftime('%Y-%m-%d %H:%M')}")
            if repo['description']:
                print(f"    {repo['description'][:60]}...")
            print()
        
        return True
    else:
        print(f"✗ Error: {response.status_code}")
        print(response.text)
        return False

if __name__ == "__main__":
    # Test with a known username first
    print("=== Testing GitHub API Access ===\n")
    
    username = input("Enter GitHub username to test (or press Enter for 'torvalds'): ").strip()
    if not username:
        username = "torvalds"  # Default test user
    
    test_github_api(username)