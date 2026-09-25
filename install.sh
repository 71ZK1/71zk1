#!/usr/bin/env bash
#
# install.sh — Dependency installer for 71ZK1
# Installs: Go (if missing), subfinder, httpx, nuclei
#
# Usage: chmod +x install.sh && ./install.sh

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${CYAN}[install]${NC} $1"; }
ok()   { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; }

echo "=============================="
echo "   71ZK1 — Dependency Setup"
echo "=============================="
echo

# ---------- Step 1: Check / install Go ----------
if command -v go &> /dev/null; then
    ok "Go is already installed ($(go version))"
else
    warn "Go not found."
    if [[ "$(uname)" == "Linux" ]]; then
        log "Installing Go via apt..."
        sudo apt update && sudo apt install -y golang-go
    elif [[ "$(uname)" == "Darwin" ]]; then
        log "Installing Go via Homebrew..."
        if ! command -v brew &> /dev/null; then
            err "Homebrew not found. Install it first: https://brew.sh"
            exit 1
        fi
        brew install go
    else
        err "Unsupported OS for auto-install. Install Go manually: https://go.dev/doc/install"
        exit 1
    fi
    ok "Go installed ($(go version))"
fi
echo

# ---------- Step 2: Ensure GOPATH/bin is in PATH ----------
GOBIN_DIR="$(go env GOPATH)/bin"
if [[ ":$PATH:" != *":$GOBIN_DIR:"* ]]; then
    warn "$GOBIN_DIR is not in your PATH."
    SHELL_RC="$HOME/.bashrc"
    [[ "$SHELL" == *"zsh"* ]] && SHELL_RC="$HOME/.zshrc"
    echo "export PATH=\$PATH:$GOBIN_DIR" >> "$SHELL_RC"
    ok "Added $GOBIN_DIR to PATH in $SHELL_RC"
    warn "Run 'source $SHELL_RC' or restart your terminal after this script finishes."
    export PATH="$PATH:$GOBIN_DIR"
fi
echo

# ---------- Step 3: Install subfinder, httpx, nuclei ----------
install_tool() {
    local name="$1"
    local pkg="$2"
    if command -v "$name" &> /dev/null; then
        ok "$name already installed"
    else
        log "Installing $name..."
        go install -v "$pkg"@latest
        ok "$name installed"
    fi
}

install_tool "subfinder" "github.com/projectdiscovery/subfinder/v2/cmd/subfinder"
install_tool "httpx"     "github.com/projectdiscovery/httpx/cmd/httpx"
install_tool "nuclei"    "github.com/projectdiscovery/nuclei/v3/cmd/nuclei"
echo

# ---------- Step 4: Pull latest nuclei templates ----------
if command -v nuclei &> /dev/null; then
    log "Updating nuclei templates..."
    nuclei -update-templates -silent || true
    ok "Nuclei templates up to date"
fi
echo

# ---------- Step 5: Final check ----------
MISSING=0
for bin in subfinder httpx nuclei; do
    if ! command -v "$bin" &> /dev/null; then
        err "$bin still not found in PATH."
        MISSING=1
    fi
done

if [[ "$MISSING" -eq 0 ]]; then
    echo
    ok "All dependencies installed successfully."
    echo "You can now run: ./71zk1.sh -d example.com"
else
    echo
    warn "Some tools are missing from PATH. Try restarting your terminal, then re-run this script."
fi
