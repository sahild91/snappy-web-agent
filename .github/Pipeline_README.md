# GitHub Actions CI/CD Pipeline

This repository uses GitHub Actions for automated building, testing, and releasing of the Snappy Web Agent across multiple platforms.

## Workflows

### 🚀 Release Workflow (`release.yml`)

**Trigger:** Git tags matching `v*.*.*` pattern (e.g., `v1.0.0`)

**What it does:**

- Builds universal binaries for macOS (Intel + Apple Silicon)
- Builds x64 and x86 binaries for Windows
- Creates professional installer packages:
  - macOS: `.pkg` installer with launchd daemon
  - Windows: `.msi` installer with Windows Service
- Creates GitHub release with detailed release notes
- Uploads all artifacts to the release

**Artifacts produced:**

- `snappy-web-agent-v1.0.0-macos-universal.pkg`
- `snappy-web-agent-v1.0.0-windows-installer.msi`
- Installation guides for both platforms
- Uninstaller scripts

### 🔧 CI Workflow (`ci.yml`)

**Trigger:** Push to `main` or `develop` branches, Pull Requests to `main`

**What it does:**

- Runs code formatting checks (`cargo fmt`)
- Runs linting with Clippy (`cargo clippy`)
- Executes test suite (`cargo test`)
- Builds binaries for macOS, Windows, and Linux
- Uploads build artifacts for inspection

### 🔒 Security Workflow (`security.yml`)

**Trigger:** Weekly schedule (Mondays at 9 AM UTC) or manual dispatch

**What it does:**

- Security audit with `cargo audit`
- License compliance checking with `cargo deny`
- Dependency staleness check with `cargo outdated`
- Code coverage analysis with `cargo tarpaulin`
- Generates dependency reports

## Creating a Release

### Method 1: Using the Release Script (Recommended)

```bash
# Auto-increment patch version (1.0.0 → 1.0.1)
./release.sh --patch

# Auto-increment minor version (1.0.0 → 1.1.0)
./release.sh --minor

# Auto-increment major version (1.0.0 → 2.0.0)
./release.sh --major

# Specify exact version
./release.sh 1.2.3

# Preview what would happen (dry run)
./release.sh --dry-run 1.2.3

# Skip confirmation prompts
./release.sh --force 1.2.3
```

### Method 2: Manual Git Tags

```bash
# Update version in Cargo.toml manually
vim Cargo.toml

# Commit the version change
git add Cargo.toml
git commit -m "Release version 1.0.0"

# Create and push tag
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin main
git push origin v1.0.0
```

### Method 3: GitHub Web Interface

1. Go to Releases page in GitHub
2. Click "Create a new release"
3. Create a new tag (e.g., `v1.0.0`)
4. GitHub Actions will automatically trigger

## Release Process Flow

1. **Developer creates release tag** (`v1.0.0`)
2. **GitHub Actions triggers** release workflow
3. **Parallel builds** start for macOS and Windows
4. **macOS build job:**
   - Compiles for x86_64 and ARM64
   - Creates universal binary with `lipo`
   - Runs `build_macos.sh` to create PKG installer
   - Uploads artifacts
5. **Windows build job:**
   - Compiles for x64 and x86
   - Installs WiX Toolset
   - Runs `build_windows.ps1` to create MSI installer
   - Uploads artifacts
6. **Release creation job:**
   - Downloads all artifacts
   - Creates GitHub release with detailed notes
   - Uploads all installers and documentation

## Monitoring Builds

- **Actions tab:** Monitor workflow progress and logs
- **Releases page:** View published releases and download artifacts
- **Security tab:** Review security advisories and dependabot alerts

## Environment Requirements

### For macOS builds:

- macOS runners (GitHub-hosted)
- Xcode command line tools
- Rust with Apple targets

### For Windows builds:

- Windows runners (GitHub-hosted)
- MSVC toolchain
- WiX Toolset v3.11
- PowerShell 5.0+

### For Linux builds:

- Ubuntu runners (GitHub-hosted)
- Standard GNU toolchain

## Secrets and Configuration

No secrets are required for public repositories. For private repositories, ensure:

- `GITHUB_TOKEN` has appropriate permissions (automatically provided)
- Release artifacts access is configured correctly

## Troubleshooting

### Build Failures

**Rust compilation errors:**

- Check Cargo.toml dependencies
- Review error logs in Actions tab
- Ensure all targets are properly configured

**macOS build issues:**

- Universal binary creation requires both Intel and ARM64 builds
- PKG creation requires proper signing (currently unsigned)

**Windows build issues:**

- WiX Toolset installation may timeout
- MSI creation requires proper directory structure
- Service installation needs administrator privileges

### Release Issues

**Tag creation problems:**

- Ensure tag format matches `v*.*.*` pattern
- Check for existing tags with same name
- Verify push permissions to repository

**Artifact upload failures:**

- Check file paths in workflow
- Ensure artifacts are created before upload
- Review GitHub API rate limits

## Configuration Files

- `.github/workflows/release.yml` - Main release workflow
- `.github/workflows/ci.yml` - Continuous integration
- `.github/workflows/security.yml` - Security and dependency checks
- `deny.toml` - Cargo deny configuration for security/license checks
- `release.sh` - Local release helper script

## Best Practices

1. **Always test builds locally** before creating releases
2. **Use semantic versioning** (MAJOR.MINOR.PATCH)
3. **Tag releases from main branch** after thorough testing
4. **Monitor security workflow** for dependency vulnerabilities
5. **Keep dependencies updated** regularly
6. **Review release notes** for accuracy before publishing

## Support

For issues with the CI/CD pipeline:

1. Check the Actions logs for detailed error messages
2. Verify all required files are present in the repository
3. Ensure proper permissions and access rights
4. Review this documentation for configuration details
