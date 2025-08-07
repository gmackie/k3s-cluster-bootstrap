# NPM Registry Component

This component installs Verdaccio as a private npm registry integrated with the cluster's centralized OAuth2 authentication system.

## Features

- Private npm registry with Verdaccio
- Integrated with cluster-wide GitHub OAuth authentication
- Persistent storage for packages
- Uplink to npmjs.org for public packages
- Web UI for browsing packages
- Scoped package support (@gmac/*)

## Prerequisites

- The control-panel component must be installed with OAuth2 proxy configured
- A domain must be configured for the cluster

## Installation

```bash
./components/npm-registry/install.sh
```

## Configuration

### External Access

The registry is available at:
- Web UI: `https://npm.<your-domain>`
- Registry: `https://npm.<your-domain>`

Configure npm:
```bash
npm config set registry https://npm.<your-domain>
npm config set @gmac:registry https://npm.<your-domain>
```

### Local Access (without domain)

For local/development access:
- Web UI: `http://<node-ip>:30873`
- Registry: `http://<node-ip>:30873`

Configure npm:
```bash
npm config set registry http://<node-ip>:30873
npm config set @gmac:registry http://<node-ip>:30873
```

## Authentication

Authentication is handled automatically through the cluster's centralized OAuth2 proxy. When you access the registry, you'll be redirected to GitHub to authenticate if not already logged in.

### Using npm CLI

For CLI access, you need to authenticate and get a token:

1. **Via Browser**: 
   - Visit `https://npm.<your-domain>` and log in
   - Click on your username in the top right
   - Copy your npm token from the displayed configuration

2. **Configure npm with the token**:
   ```bash
   npm config set //npm.<your-domain>/:_authToken <your-token>
   ```

3. **Alternative - Use npm login**:
   ```bash
   npm login --registry https://npm.<your-domain>
   # This will open a browser for authentication
   ```

## Publishing Packages

### Scoped Package (@gmac/*)
```bash
# Initialize with scope
npm init --scope=@gmac

# Publish
npm publish
```

### In package.json
```json
{
  "name": "@gmac/my-api-library",
  "version": "1.0.0",
  "publishConfig": {
    "registry": "https://npm.your-domain.com"
  }
}
```

### Publishing Script
```json
{
  "scripts": {
    "publish:private": "npm publish --registry https://npm.your-domain.com"
  }
}
```

## Package Access Control

- `@gmac/*` packages: Authenticated users only (read/write)
- Other scoped packages: Public read, authenticated write  
- Unscoped packages: Public read, authenticated write

## Storage

Packages are stored in a persistent volume (10GB by default). Adjust the size in `verdaccio-pvc.yaml` if needed.

## Troubleshooting

### Check logs
```bash
kubectl logs -n npm-registry deployment/verdaccio
```

### Access the web UI
- External: `https://npm.<your-domain>`
- Local: `http://<node-ip>:30873`

### Authentication Issues

If you're having authentication issues:

1. Clear your browser cookies for the domain
2. Check that the OAuth2 proxy is running:
   ```bash
   kubectl get pods -n monitoring | grep oauth2-proxy
   ```
3. Verify the auth headers are being passed:
   ```bash
   kubectl logs -n npm-registry deployment/verdaccio | grep X-Auth-Request-Email
   ```

### Rebuild the Docker image
If you need to update the auth-proxy plugin:
```bash
cd components/npm-registry
./build-image.sh
kubectl rollout restart -n npm-registry deployment/verdaccio
```

## Security Notes

- Authentication is handled by the cluster's OAuth2 proxy
- Only users who can authenticate with GitHub can access the registry
- All traffic should use HTTPS in production
- The registry trusts authentication headers from the proxy