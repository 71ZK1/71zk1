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
   ______ _  ______  __ __
  /_  __/| |/_/_  / /_//_/
   / /  _>  <  / /_  /_/
  /_/  /_/|_|/___/_/  /
        7 1 Z K 1 — recon pipeline
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

check_deps() {
    local missing=0
    for bin in subfinder httpx nuclei; do
        if ! command -v "$bin" &> /dev/null; then
            err "$bin not found in PATH."
            missing=1
        fi
    done
    if [[ "$missing" -eq 1 ]]; then
        err "Install the missing tool(s) above before running 71ZK1. See the header of this script for install commands."
        exit 1
    fi
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
echo

# ---------- Stage 1: Subdomain enumeration ----------
log "Stage 1/3 — Enumerating subdomains with subfinder..."
subfinder -d "$DOMAIN" -silent -o "$SUBS_FILE"
SUB_COUNT=$(wc -l < "$SUBS_FILE" | tr -d ' ')
ok "Found $SUB_COUNT subdomains -> $SUBS_FILE"
echo

if [[ "$SUB_COUNT" -eq 0 ]]; then
    warn "No subdomains found. Stopping here."
    exit 0
fi

# ---------- Stage 2: Probe for live hosts ----------
log "Stage 2/3 — Probing for live hosts with httpx..."
httpx -l "$SUBS_FILE" -silent -status-code -title -tech-detect -o "$LIVE_FILE"
LIVE_COUNT=$(wc -l < "$LIVE_FILE" | tr -d ' ')
ok "Found $LIVE_COUNT live hosts -> $LIVE_FILE"
echo

if [[ "$LIVE_COUNT" -eq 0 ]]; then
    warn "No live hosts responded. Stopping here."
    exit 0
fi

# httpx above writes extra columns (status/title/tech) after the URL,
# nuclei needs bare URLs, so re-probe cleanly for just the URL list.
LIVE_URLS_FILE="${RUNDIR}/live_urls.txt"
awk '{print $1}' "$LIVE_FILE" > "$LIVE_URLS_FILE"

# ---------- Stage 3: Vulnerability scanning ----------
log "Stage 3/3 — Scanning live hosts with nuclei..."
if [[ -n "$TEMPLATES" ]]; then
    nuclei -l "$LIVE_URLS_FILE" -t "$TEMPLATES" -severity "$SEVERITY" -rl "$RATE" -silent -o "$NUCLEI_FILE"
else
    nuclei -l "$LIVE_URLS_FILE" -severity "$SEVERITY" -rl "$RATE" -silent -o "$NUCLEI_FILE"
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
