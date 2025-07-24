# GitHub OAuth App Setup for K3s Dashboard

## Step 1: Create GitHub OAuth Application

1. Go to [GitHub Developer Settings](https://github.com/settings/applications/new)
2. Fill in the application details:
   - **Application name**: `K3s Dashboard - GMAC.io`
   - **Homepage URL**: `https://k3s.gmac.io`
   - **Application description**: `Kubernetes Dashboard for GMAC.io infrastructure`
   - **Authorization callback URL**: `https://k3s.gmac.io/oauth2/callback`

3. Click "Register application"

## Step 2: Get OAuth Credentials

After creating the app, you'll see:
- **Client ID**: Copy this value
- **Client Secret**: Click "Generate a new client secret" and copy the value

## Step 3: Update .env File

The OAuth credentials are already configured in your `.env` file:
```bash
export K3S_GITHUB_OAUTH_CLIENT_ID=Ov23liUoDijhtGOCmugS
export K3S_GITHUB_OAUTH_CLIENT_SECRET=b15f1f1d349f54288456451bb321fe236fe65501
```

✅ No manual configuration needed - the setup script will automatically read from `.env`

## Step 4: Run Setup

```bash
./setup-k3s-dashboard.sh
```

## Security Notes

- Only the GitHub user `gmackie` will be able to access the dashboard
- All other GitHub users will be denied access
- The OAuth app is configured for the specific domain `k3s.gmac.io`
- HTTPS is enforced with automatic Let's Encrypt certificates

## Troubleshooting

If you get OAuth errors:
1. Verify the callback URL matches exactly: `https://k3s.gmac.io/oauth2/callback`
2. Check that DNS is pointing k3s.gmac.io to your server IP
3. Ensure the certificate is issued: `kubectl get certificate -n kubernetes-dashboard`

## Emergency Access

If OAuth fails, you can use the admin token:
```bash
kubectl -n kubernetes-dashboard create token admin-user
```

Then access the dashboard directly and use "Token" authentication with the generated token.