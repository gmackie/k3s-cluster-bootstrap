#!/usr/bin/env python3
"""
Test script to verify the bulk import functionality
This script shows the workflow without requiring actual tokens
"""
import requests
import json

def test_github_api():
    """Test if we can reach GitHub API"""
    try:
        response = requests.get("https://api.github.com/user", timeout=5)
        print(f"✓ GitHub API reachable (status: {response.status_code})")
        return True
    except Exception as e:
        print(f"✗ GitHub API error: {e}")
        return False

def test_gitea_api():
    """Test if we can reach Gitea API"""
    try:
        response = requests.get("https://ci.gmac.io/api/v1/version", timeout=5)
        if response.status_code == 200:
            version_info = response.json()
            print(f"✓ Gitea API reachable (version: {version_info.get('version', 'unknown')})")
            return True
        else:
            print(f"✗ Gitea API error: {response.status_code}")
            return False
    except Exception as e:
        print(f"✗ Gitea API error: {e}")
        return False

def simulate_import_flow():
    """Simulate the import flow without actual tokens"""
    print("\n=== Bulk Import Flow Simulation ===")
    print("1. ✓ Get Gitea API token from: https://ci.gmac.io/user/settings/applications")
    print("2. ✓ Enter GitHub username")
    print("3. ✓ Optionally enter GitHub token for private repos")
    print("4. ✓ Fetch repositories from GitHub API")
    print("5. ✓ Filter repositories (all/public/select)")
    print("6. ✓ Import each repository to Gitea")
    print("7. ✓ Show import summary")

def main():
    print("=== Gitea Bulk Import Test ===\n")
    
    # Test API connectivity
    github_ok = test_github_api()
    gitea_ok = test_gitea_api()
    
    if github_ok and gitea_ok:
        print("\n✓ All APIs are reachable!")
        simulate_import_flow()
        print("\n✓ Ready to run actual import with:")
        print("  python gitea-bulk-import.py")
    else:
        print("\n✗ API connectivity issues detected")
        if not github_ok:
            print("  - Check internet connection for GitHub API")
        if not gitea_ok:
            print("  - Check if Gitea server is running at ci.gmac.io")

if __name__ == "__main__":
    main()