#!/bin/bash
# Script to help push to GitHub

echo "🚀 K3s Cluster Bootstrap - GitHub Push Helper"
echo "==========================================="
echo
echo "Before pushing, make sure you have:"
echo "1. Created a new repository on GitHub"
echo "2. Named it something like 'k3s-cluster-bootstrap'"
echo "3. Do NOT initialize it with README, license, or .gitignore"
echo
read -p "Have you created an empty GitHub repository? (y/n): " confirm

if [[ "$confirm" != "y" ]]; then
    echo "Please create a repository first at: https://github.com/new"
    exit 1
fi

echo
read -p "Enter your GitHub username: " username
read -p "Enter your repository name [k3s-cluster-bootstrap]: " reponame
reponame=${reponame:-k3s-cluster-bootstrap}

echo
echo "Setting up remote..."
git remote add origin "https://github.com/$username/$reponame.git" 2>/dev/null || {
    echo "Remote 'origin' already exists. Updating URL..."
    git remote set-url origin "https://github.com/$username/$reponame.git"
}

echo
echo "Your repository will be available at:"
echo "https://github.com/$username/$reponame"
echo
echo "To push your code, run:"
echo "  git push -u origin master"
echo
echo "After pushing, update these in your README.md:"
echo "  - Replace 'yourusername' with '$username'"
echo "  - Replace 'k3s-cluster-bootstrap' with '$reponame' (if different)"
echo
echo "Repository description for GitHub:"
cat .github/repository-description.txt
echo
echo
echo "Topics to add: k3s, kubernetes, gitops, monitoring, self-hosted, devops, infrastructure"