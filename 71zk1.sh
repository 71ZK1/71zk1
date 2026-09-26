#!/usr/bin/env bash
#
# 71ZK1 — Automated Recon Pipeline
# Chains: subfinder -> httpx -> nuclei
#
# Author: Thejas
# Usage:  ./71zk1.sh -d target.com [-o output_dir] [-t nuclei_templates] [-r rate]
#
# Requires: subfinder, httpx, nuclei (all from ProjectDiscovery)
#   go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
#   go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
#   go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
#
# NOTE: There is also a Python package called "httpx" (an HTTP client
# library) that installs its own unrelated "httpx" command. If it's
# installed and appears earlier in your PATH, it silently shadows
# ProjectDiscovery's httpx and breaks this script with errors like:
#   "Usage: httpx [OPTIONS] URL ... Error: No such option: -l"
# To avoid that, this script resolves the Go-installed binaries by
# their known install path first, instead of blindly trusting PATH.

set -euo pipefail

# ---------- Defaults ----------
DOMAIN=""
OUTDIR="results"
TEMPLATES=""          # empty = nuclei's default template set
RATE=150              # nuclei requests/sec, keep polite by default
SEVERITY="low,medium,high,critical"

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

banner() {
cat << "EOF"
 ████████║   ██║ ███████╗██╗  ██╗ ██╗
    ╚══██║  ███║ ╚══███╔╝██║ ██╔╝███║
       ██║   ██║   ███╔╝ █████╔╝ ╚██║
       ██║   ██║  ███╔╝  ██╔═██╗  ██║
       ██║   ██║ ███████╗██║  ██╗ ██║
       ╚═╝   ╚═╝ ╚══════╝╚═╝  ╚═╝ ╚═╝

          recon pipeline
EOF
}

usage() {
    echo "Usage: $0 -d <domain> [-o <output_dir>] [-t <nuclei_templates>] [-r <rate>]"
    echo
    echo "  -d   Target domain (required), e.g. example.com"
    echo "  -o   Output directory (default: results)"
    echo "  -t   Path to custom nuclei templates (default: nuclei's built-in set)"
    echo "  -r   Nuclei rate limit, requests/sec (default: 150)"
    echo "  -h   Show this help message"
    exit 1
}

log() { echo -e "${CYAN}[71ZK1]${NC} $1"; }
ok()  { echo -e "${GREEN}[+]${NC} $1"; }
warn(){ echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[-]${NC} $1"; }

# ---------- Resolve real ProjectDiscovery binaries ----------
# Prefer the Go install location so we never accidentally call a
# same-named tool from somewhere else on PATH (e.g. Python's httpx).
GOBIN_DIR="$(go env GOPATH 2>/dev/null)/bin"
[[ -z "${GOBIN_DIR// }" || "$GOBIN_DIR" == "/bin" ]] && GOBIN_DIR="$HOME/go/bin"

resolve_bin() {
    local name="$1"
    if [[ -x "${GOBIN_DIR}/${name}" ]]; then
        echo "${GOBIN_DIR}/${name}"
    elif command -v "$name" &> /dev/null; then
        command -v "$name"
    else
        echo ""
    fi
}

SUBFINDER_BIN="$(resolve_bin subfinder)"
HTTPX_BIN="$(resolve_bin httpx)"
NUCLEI_BIN="$(resolve_bin nuclei)"

verify_httpx() {
    # ProjectDiscovery's httpx supports -silent; the Python "httpx" CLI does not.
    # This catches the shadowing case even if resolve_bin found *a* httpx.
    if [[ -n "$HTTPX_BIN" ]] && ! "$HTTPX_BIN" -h 2>&1 | grep -q "silent"; then
        err "Found a 'httpx' at $HTTPX_BIN, but it doesn't look like ProjectDiscovery's httpx."
        err "This is likely the Python 'httpx' HTTP client package shadowing the real tool."
        warn "Fix options:"
        warn "  1) pip uninstall httpx   (if you don't need the Python library globally)"
        warn "  2) Or run: export PATH=\"${GOBIN_DIR}:\$PATH\"   before running this script"
        warn "  3) Or reinstall: go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest"
        exit 1
    fi
}

check_deps() {
    local missing=0
    [[ -z "$SUBFINDER_BIN" ]] && { err "subfinder not found."; missing=1; }
    [[ -z "$HTTPX_BIN" ]] && { err "httpx not found."; missing=1; }
    [[ -z "$NUCLEI_BIN" ]] && { err "nuclei not found."; missing=1; }

    if [[ "$missing" -eq 1 ]]; then
        err "Install the missing tool(s) above before running 71ZK1. Run ./install.sh, or see the header of this script for install commands."
        exit 1
    fi

    verify_httpx
}

# ---------- Parse args ----------
while getopts "d:o:t:r:h" opt; do
    case "$opt" in
        d) DOMAIN="$OPTARG" ;;
        o) OUTDIR="$OPTARG" ;;
        t) TEMPLATES="$OPTARG" ;;
        r) RATE="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [[ -z "$DOMAIN" ]]; then
    err "Domain is required."
    usage
fi

# Strip an accidentally-pasted scheme/path so subfinder gets a bare domain,
# e.g. "https://example.com/" -> "example.com"
DOMAIN="${DOMAIN#http://}"
DOMAIN="${DOMAIN#https://}"
DOMAIN="${DOMAIN%%/*}"

banner
check_deps

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
RUNDIR="${OUTDIR}/${DOMAIN}/${TIMESTAMP}"
mkdir -p "$RUNDIR"

SUBS_FILE="${RUNDIR}/subdomains.txt"
LIVE_FILE="${RUNDIR}/live_hosts.txt"
NUCLEI_FILE="${RUNDIR}/nuclei_findings.txt"
SUMMARY_FILE="${RUNDIR}/summary.txt"

log "Target: $DOMAIN"
log "Output: $RUNDIR"
log "Using subfinder: $SUBFINDER_BIN"
log "Using httpx:     $HTTPX_BIN"
log "Using nuclei:    $NUCLEI_BIN"
echo

# ---------- Stage 1: Subdomain enumeration ----------
log "Stage 1/3 — Enumerating subdomains with subfinder..."
"$SUBFINDER_BIN" -d "$DOMAIN" -silent -o "$SUBS_FILE"
SUB_COUNT=$(wc -l < "$SUBS_FILE" | tr -d ' ')
ok "Found $SUB_COUNT subdomains -> $SUBS_FILE"
echo

if [[ "$SUB_COUNT" -eq 0 ]]; then
    warn "No subdomains found. Stopping here."
    exit 0
fi

# ---------- Stage 2: Probe for live hosts ----------
log "Stage 2/3 — Probing for live hosts with httpx..."
"$HTTPX_BIN" -l "$SUBS_FILE" -silent -status-code -title -tech-detect -o "$LIVE_FILE"
LIVE_COUNT=$(wc -l < "$LIVE_FILE" | tr -d ' ')
ok "Found $LIVE_COUNT live hosts -> $LIVE_FILE"
echo

if [[ "$LIVE_COUNT" -eq 0 ]]; then
    warn "No live hosts responded. Stopping here."
    exit 0
fi

# httpx above writes extra columns (status/title/tech) after the URL,
# nuclei needs bare URLs, so extract just the URL column.
LIVE_URLS_FILE="${RUNDIR}/live_urls.txt"
awk '{print $1}' "$LIVE_FILE" > "$LIVE_URLS_FILE"

# ---------- Stage 3: Vulnerability scanning ----------
log "Stage 3/3 — Scanning live hosts with nuclei..."
if [[ -n "$TEMPLATES" ]]; then
    "$NUCLEI_BIN" -l "$LIVE_URLS_FILE" -t "$TEMPLATES" -severity "$SEVERITY" -rl "$RATE" -silent -o "$NUCLEI_FILE"
else
    "$NUCLEI_BIN" -l "$LIVE_URLS_FILE" -severity "$SEVERITY" -rl "$RATE" -silent -o "$NUCLEI_FILE"
fi
FINDING_COUNT=$(wc -l < "$NUCLEI_FILE" 2>/dev/null | tr -d ' ' || echo 0)
ok "Nuclei finished — $FINDING_COUNT findings -> $NUCLEI_FILE"
echo

# ---------- Summary ----------
{
    echo "71ZK1 Recon Summary"
    echo "===================="
    echo "Target:          $DOMAIN"
    echo "Run time:        $TIMESTAMP"
    echo "Subdomains:      $SUB_COUNT"
    echo "Live hosts:      $LIVE_COUNT"
    echo "Nuclei findings: $FINDING_COUNT"
    echo
    echo "Files:"
    echo "  - $SUBS_FILE"
    echo "  - $LIVE_FILE"
    echo "  - $NUCLEI_FILE"
} > "$SUMMARY_FILE"

cat "$SUMMARY_FILE"
ok "Full run saved under: $RUNDIR"
