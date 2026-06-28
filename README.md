# Mafficksoft DNS (steindns)

Lightweight DNS server written in Go. This repository contains the source for a small, fast DNS server that serves records from a TSV file and supports live reload on SIGHUP.

Repository: https://github.com/LA-Silva/mafficksoftdns

## Quickstart

Prerequisites:
- Go 1.25.5 or newer
- Git (if cloning)

Clone, build and run:

```bash
git clone https://github.com/LA-Silva/mafficksoftdns.git
cd mafficksoftdns
# build using helper
./build.sh
# or
mkdir -p bin
go build -ldflags='-s -w' -o bin/steindns main.go
# run
./bin/steindns -file records.tsv -port 5353 -size 10000
```

Or install directly with Go (if you prefer):

```bash
go install github.com/LA-Silva/mafficksoftdns@latest
```

If available, you can also download pre-built binaries from the Releases page.

## Configuration

- `-file`  : TSV file with records (default: `records.tsv`)
- `-port`  : UDP port to listen on (default: `5353`)
- `-size`  : maximum records per in-memory buffer (default: `10000`)

By default the server expects a header row in the TSV and then tab-separated records. See the Example records section below.

## Example records.tsv format

The TSV should include a single header line (the program skips the first line) followed by rows with the fields:

1. Name (FQDN; the code normalizes using dns.Fqdn)
2. Type (A, AAAA, TXT, CNAME, etc.)
3. Value (record-specific data)
4. TTL (optional; defaults to 60)

Example:

```
name	type	value	ttl
example.local.	A	192.0.2.10	300
www.example.local.	CNAME	example.local.
status.local.	TXT	"ok"
```

## Health check

The server responds to a TXT query for `checkstatus.local.` when the query originates from localhost. Example:

```bash
dig @127.0.0.1 -p 5353 checkstatus.local. TXT +short
```

## Running as a service (systemd example)

Create `/etc/systemd/system/steindns.service` and adjust paths/users as needed:

````ini
[Unit]
Description=steindns - Lightweight DNS server
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=/usr/local/bin/steindns -file /etc/steindns/records.tsv -port 5353 -size 20000
WorkingDirectory=/var/lib/steindns
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
````

Enable and start:

```bash
sudo mkdir -p /etc/steindns /var/lib/steindns
sudo cp records.tsv /etc/steindns/records.tsv
sudo systemctl daemon-reload
sudo systemctl enable --now steindns
sudo systemctl status steindns
```

## Reloading records

Send SIGHUP to the process to trigger a TSV reload:

```bash
kill -SIGHUP <pid>
```

## Troubleshooting

- Build issues: ensure Go >= 1.25.5 is installed. Run `go mod download` or `go mod tidy` to fetch dependencies.
- Permission errors binding to low ports: use a higher port or run with appropriate privileges.
- If health-check TXT doesn't respond, ensure you're querying from 127.0.0.1 or ::1 and using TXT query type.

## Development

- Module: `go.mod` is present; dependencies are managed with Go modules.
- Use `go mod tidy` to clean module files and `go mod download` to prefetch modules.

## See also
- INSTALL.md — detailed compile/install/CI notes and systemd example
- LICENSE — project license (MIT)

