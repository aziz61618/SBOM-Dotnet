INSTALL_DIR="$HOME/bin"

TRIVY_VERSION=$(curl -fsSL \
https://api.github.com/repos/aquasecurity/trivy/releases/latest \
  | grep '"tag_name":' \
  | sed -E 's/.*"v([^"]+)".*/\1/')

echo "Installing Trivy v${TRIVY_VERSION}..."
apt-get install -y curl
mkdir -p "$INSTALL_DIR"

TRIVY_URL="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"

if ! curl -sfL "$TRIVY_URL" -o trivy.tar.gz; then
    echo "Failed to download Trivy from $TRIVY_URL (release/asset may not exist - check https://github.com/aquasecurity/trivy/releases for a valid TRIVY_VERSION)" >&2
    exit 1
fi

tar -xzf trivy.tar.gz -C "$INSTALL_DIR" trivy
rm -f trivy.tar.gz

if [ ! -x "$INSTALL_DIR/trivy" ]; then
    echo "Trivy failed to install to $INSTALL_DIR/trivy" >&2
    exit 1
fi

PROJECT_DIR=$(pwd)
"$INSTALL_DIR/trivy" fs --scanners vuln --format table --exit-code 0 --output trivy-vulnerabilities.txt "$PROJECT_DIR"
