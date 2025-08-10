# Contributing to K3s Cluster Bootstrap

Thank you for your interest in contributing! This project aims to make Kubernetes accessible to everyone.

## How to Contribute

### Reporting Issues
- Check existing issues first
- Include system information
- Provide reproduction steps
- Share relevant logs (without secrets!)

### Submitting Pull Requests
1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes
4. Test thoroughly: `./scripts/validate-deployment.sh`
5. Commit with descriptive message
6. Push and create PR

### Adding New Components
To add a new service:
1. Create directory: `components/service-name/`
2. Add `install.sh` following existing patterns
3. Include Kubernetes manifests
4. Update documentation
5. Add to setup wizard options

### Code Standards
- Use consistent formatting in shell scripts
- Follow Kubernetes best practices
- Never commit secrets or credentials
- Include helpful error messages
- Document configuration options

### Testing
- Test on fresh K3s cluster
- Verify OAuth integration works
- Check resource limits are reasonable
- Ensure uninstall is clean

## Component Guidelines

### Security
- All services must integrate with central OAuth
- Use sealed secrets for sensitive data
- Follow principle of least privilege
- Enable network policies where possible

### Resource Management
- Set appropriate resource requests/limits
- Use persistent volumes for stateful data
- Configure health checks
- Implement graceful shutdown

### Documentation
- Update README for new features
- Add troubleshooting for common issues
- Include example configurations
- Document any breaking changes

## Development Setup

```bash
# Clone your fork
git clone https://github.com/yourusername/k3s-cluster-bootstrap.git
cd k3s-cluster-bootstrap

# Create test cluster
./setup-wizard.sh

# Make changes and test
./scripts/validate-deployment.sh
```

## Questions?
Open an issue for discussion before making large changes.

Thank you for helping make K3s clusters better! 🚀