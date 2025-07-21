# K3s Dedicated Server Setup

## Why Separate Server is Required

- **Port Conflict**: Gitea uses 80/443, k3s ingress needs the same ports
- **Resource Isolation**: CI builds won't affect production apps
- **Better Architecture**: Separation of concerns (CI vs Runtime)

## Server Recommendation

### Option 1: Another CPX11 (Recommended)
- **Same specs**: 2 vCPU, 2GB RAM, 40GB SSD
- **Cost**: Additional $4.20/month
- **Total monthly**: $8.40 (CI + k3s)
- **Good for**: 5-10 small apps or 2-3 medium apps

### Option 2: CPX21 (More headroom)
- **Specs**: 3 vCPU, 4GB RAM, 80GB SSD
- **Cost**: $8.49/month
- **Total monthly**: $12.69 (CI + k3s)
- **Good for**: 10-20 small apps or 5-10 medium apps

## New Architecture

```
┌─────────────────┐         ┌─────────────────┐
│  CI Server      │         │  K3s Server     │
│  ci.gmac.io     │         │  *.gmac.io      │
│  5.78.92.8      │──────>  │  (new IP)       │
│                 │ Deploy  │                 │
│  - Gitea        │         │  - k3s          │
│  - CI/CD        │         │  - Your apps    │
│  - Registry     │         │  - Ingress      │
└─────────────────┘         └─────────────────┘
```

## Setup Steps

1. **Create new Hetzner server**
   - Same datacenter (Nuremberg)
   - Ubuntu 24.04
   - CPX11 or CPX21

2. **Update DNS**
   ```
   ci.gmac.io       → 5.78.92.8 (existing)
   *.gmac.io        → NEW_SERVER_IP
   api.gmac.io      → NEW_SERVER_IP
   app.gmac.io      → NEW_SERVER_IP
   staging-*.gmac.io → NEW_SERVER_IP
   ```

3. **Install k3s** on new server
   - No port conflicts
   - Full resources available
   - Clean setup

4. **Connect CI to k3s**
   - Gitea builds → push to registry
   - Deploy to k3s via kubectl

## Benefits of Separation

✅ **No port conflicts** - Each server owns 80/443
✅ **Better performance** - Isolated workloads
✅ **Easier scaling** - Upgrade k3s server independently
✅ **Production ready** - Proper separation of concerns
✅ **Still affordable** - Under $10/month total

## Hetzner CLI Command

```bash
# Create new server (adjust as needed)
hcloud server create \
  --name k3s-gmac-io \
  --type cpx11 \
  --image ubuntu-24.04 \
  --location nbg1 \
  --ssh-key your-ssh-key-name
```

Ready to create the new server?