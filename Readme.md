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
- [subfinder](https://github.com/projectdiscovery/subfinder)
- [httpx](https://github.com/projectdiscovery/httpx)
- [nuclei](https://github.com/projectdiscovery/nuclei)

Install all three (requires Go):

```bash
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
```

Make sure `$GOPATH/bin` (usually `~/go/bin`) is in your `PATH`.

## Usage

```bash
chmod +x 71zk1.sh
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


