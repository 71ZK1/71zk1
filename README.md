# 71ZK1

Automated recon pipeline for bug bounty and web asset discovery.

Chains three industry-standard tools into a single command:

```
subfinder → httpx → nuclei
```

## What it does

1. **subfinder** — enumerates subdomains for the target domain
2. **httpx** — probes which subdomains are live, and grabs status code, title, and detected tech
3. **nuclei** — scans the live hosts against community vulnerability templates

Each run is saved into its own timestamped folder so nothing overwrites previous scans, and a `summary.txt` is generated at the end.

## Requirements

- Bash (Linux/macOS/WSL)
- Go (installed automatically by `install.sh` if missing)
- [subfinder](https://github.com/projectdiscovery/subfinder)
- [httpx](https://github.com/projectdiscovery/httpx)
- [nuclei](https://github.com/projectdiscovery/nuclei)

## Setup

Clone the repo and run the installer once — it checks for Go, installs subfinder/httpx/nuclei if they're missing, adds them to your `PATH`, and pulls the latest nuclei templates:

```bash
git clone https://github.com/<your-username>/71zk1.git
cd 71zk1
chmod +x install.sh 71zk1.sh
./install.sh
```

If `install.sh` adds anything to your `PATH`, restart your terminal (or run `source ~/.bashrc` / `source ~/.zshrc`) before continuing.

## Usage

```bash
./71zk1.sh -d example.com
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-d` | Target domain (required) | — |
| `-o` | Output directory | `results` |
| `-t` | Path to custom nuclei templates | nuclei's built-in set |
| `-r` | Nuclei rate limit (requests/sec) | `150` |
| `-h` | Show help | — |

### Example

```bash
./71zk1.sh -d example.com -o scans -r 100
```

Output structure:

```
scans/
└── example.com/
    └── 2026-09-25_14-30-00/
        ├── subdomains.txt
        ├── live_hosts.txt
        ├── live_urls.txt
        ├── nuclei_findings.txt
        └── summary.txt
```

## Notes

- Only run this against domains you are authorized to test (bug bounty programs you're enrolled in, or your own infrastructure).
- Nuclei's severity filter defaults to `low,medium,high,critical` — edit the `SEVERITY` variable in the script if you want informational findings too.
- This is a recon starting point, not a replacement for manual testing — treat the nuclei output as a lead list, not a final report.

