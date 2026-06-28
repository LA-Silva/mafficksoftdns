# Compile & Install

This document explains how to compile, install, run, and verify the mfsdns binary included in this repository (mafficksoftdns).

## Prerequisites

- Go toolchain (version >= 1.25.5). The repository's go.mod specifies `go 1.25.5` — using that version or a newer stable Go is recommended.
- Git (to clone the repository) if you haven't already.
- A POSIX-like environment (Linux/macOS). The examples use Linux paths and systemd.

## Clone the repository

```bash
git clone https://github.com/LA-Silva/mafficksoftdns.git
cd mafficksoftdns
```

## Build (compile)

This repository includes a small build helper script `build.sh`. You can either use it or run go build directly.

Option A — using the provided script:

```bash
# Makes bin/mfsdns using the flags in build.sh
./build.sh
```

Option B — using go build directly (equivalent):

```bash
# Create the output directory then build
mkdir -p bin
go build -ldflags='-s -w' -o bin/mfsdns main.go
```

Notes:
- The `-ldflags='-s -w'` strip debug information producing a smaller binary. Remove them if you want debug symbols.
- If you prefer `go install`, you can run `go install` from module root and the binary will be installed under your Go bin directory (e.g. $GOBIN or $GOPATH/bin).

## Install (system-wide)

To install the compiled binary system-wide (requires root):

```bash
sudo install -m 0755 bin/mfsdns /usr/local/bin/mfsdns
```

Or copy manually:

```bash
sudo cp bin/mfsdns /usr/local/bin/
sudo chmod 755 /usr/local/bin/mfsdns
```

## Configuration & Running

The server reads records from a TSV file (default `records.tsv` in the repo root). It accepts flags:

- `-file`  : path to TSV file (default `records.tsv`)
- `-port`  : UDP port to listen on (default `5353`)
- `-size`  : maximum records per in-memory buffer (default `10000`)

Example run (foreground):

```bash
/usr/local/bin/mfsdns -file /path/to/records.tsv -port 5353 -size 20000
```

The server supports reloading the TSV on receipt of SIGHUP. For example:

```bash
# Send SIGHUP to reload records in a running process (replace PID)
kill -SIGHUP <pid>
```

### Health check

The server responds to a TXT query for the domain `checkstatus.local.` when the query originates from localhost (127.0.0.1 or ::1). Example using `dig`:

```bash
dig @127.0.0.1 -p 5353 checkstatus.local. TXT +short
```

You should see a TXT string containing STATUS=OK, request counts, RPS and uptime.

## Systemd service example (Linux)

Create a unit file `/etc/systemd/system/mfsdns.service` with the following contents (adjust paths and user as needed):

````ini
[Unit]
Description=mfsdns - Lightweight DNS server
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=/usr/local/bin/mfsdns -file /etc/mfsdns/records.tsv -port 5353 -size 20000
WorkingDirectory=/var/lib/mfsdns
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
````

After creating the unit and placing your `records.tsv` under `/etc/mfsdns/` (or other chosen location), enable and start the service:

```bash
sudo mkdir -p /etc/mfsdns /var/lib/mfsdns
sudo cp records.tsv /etc/mfsdns/records.tsv
sudo systemctl daemon-reload
sudo systemctl enable --now mfsdns
sudo systemctl status mfsdns
```

## Example records.tsv format

The repository includes an example `records.tsv`. The code expects a header line (which it skips) followed by tab-separated rows with at least 3 columns and optionally a TTL 4th column. The columns are:

1. Name (e.g. example.local.)
2. Type (e.g. A, AAAA, TXT, CNAME)
3. Value (record-specific value)
4. TTL (optional, defaults to 60)

Make sure names are fully-qualified (end with a dot) or the code will call dns.Fqdn on them.

## Development & dependency management

If you need to update or fetch dependencies:

```bash
# download modules
go mod download
# or tidy up
go mod tidy
```

## Troubleshooting

- Build errors about Go version: install Go 1.25.5 or newer.
- Missing module errors: run `go mod download` or `go mod tidy`.
- Permission denied when binding to low-numbered ports (<1024): use a higher port or run as root (not recommended).
- If the health check TXT doesn't respond, make sure you're querying from localhost and that the query type is TXT.

## Uninstall

To remove the installed binary and unit file:

```bash
sudo systemctl disable --now mfsdns
sudo rm /etc/systemd/system/mfsdns.service
sudo systemctl daemon-reload
sudo rm /usr/local/bin/mfsdns
```

## Contact / Notes

This project is MIT-style (no license file provided in this repository snapshot). Check the repository for a license or contact the maintainer for redistribution/use details.
