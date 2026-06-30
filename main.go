package main

import (
	"encoding/csv"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/miekg/dns"
)

type DataStore struct {
	// Map structure: [lowercase_fqdn_string][dns_type_uint16]slice_of_precompiled_RRs
	Records map[string]map[uint16][]dns.RR
}

var (
	// Application Customization
	appName = "mfsdns"

	buffers      [2]*DataStore
	activeIndex  int32
	reloadLock   sync.Mutex
	startTime    time.Time

	// Flags
	maxRecords int
	port       int
	listenAddr string
	tsvPath    string

	// Stats & Rotation Counters
	queryCounter uint64
	rps1m        float64
	rps5m        float64
)

const HealthCheckDomain = "checkstatus.local."

func loadRecords() error {
	reloadLock.Lock()
	defer reloadLock.Unlock()

	currentActive := atomic.LoadInt32(&activeIndex)
	inactiveIndex := 1 - currentActive
	targetBuf := buffers[inactiveIndex]

	file, err := os.Open(tsvPath)
	if err != nil {
		return fmt.Errorf("could not open tsv file: %w", err)
	}
	defer file.Close()

	reader := csv.NewReader(file)
	reader.Comma = '\t'
	if _, err := reader.Read(); err != nil {
		return fmt.Errorf("could not read header: %w", err)
	}

	// Initialize a fresh map for the inactive buffer
	newRecords := make(map[string]map[uint16][]dns.RR)

	count := 0
	for {
		row, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		if count >= maxRecords {
			log.Printf("Warning: reached maxRecords limit of %d. Skipping remaining rows.", maxRecords)
			break
		}

		// Parse TTL from 4th column, default to 60 if empty
		ttlVal := "60"
		if len(row) > 3 && strings.TrimSpace(row[3]) != "" {
			ttlVal = strings.TrimSpace(row[3])
		}

		name := strings.ToLower(dns.Fqdn(row[0]))
		typeStr := strings.ToUpper(row[1])
		qType := dns.StringToType[typeStr]
		val := row[2]

		// TXT records need to be quoted
		if typeStr == "TXT" {
			val = fmt.Sprintf("\"%s\"", val)
		}

		// Pre-compile the resource record string into a dns.RR object right here during load time
		rrStr := fmt.Sprintf("%s %s IN %s %s", name, ttlVal, typeStr, val)
		rr, err := dns.NewRR(rrStr)
		if err != nil {
			log.Printf("Skipping invalid record line %d: %v", count+2, err)
			continue
		}

		// Initialize inner maps as needed
		//if _, exists := newRecords[name]; !exists {
		//	newRecords[name] = make(map[string]map[uint16][]dns.RR)
		//}
		if _, exists := newRecords[name]; !exists {
		    newRecords[name] = make(map[uint16][]dns.RR) // <-- Corrected
		}

		newRecords[name][qType] = append(newRecords[name][qType], rr)

		count++
	}

	targetBuf.Records = newRecords

	// Atomically point queries to the newly loaded map
	atomic.StoreInt32(&activeIndex, inactiveIndex)
	return nil
}

func monitorStats() {
	var lastCount uint64
	ticker := time.NewTicker(5 * time.Second)
	for range ticker.C {
		currentCount := atomic.LoadUint64(&queryCounter)
		delta := currentCount - lastCount
		lastCount = currentCount
		currentRPS := float64(delta) / 5.0
		rps1m = (currentRPS * 0.083) + (rps1m * (1 - 0.083))
		rps5m = (currentRPS * 0.016) + (rps5m * (1 - 0.016))
	}
}

func handleDnsRequest(w dns.ResponseWriter, r *dns.Msg) {
	reqID := atomic.AddUint64(&queryCounter, 1)

	m := new(dns.Msg)
	m.SetReply(r)
	m.Authoritative = true

	idx := atomic.LoadInt32(&activeIndex)
	activeBuf := buffers[idx]

	for _, q := range r.Question {
		qName := strings.ToLower(q.Name)

		// Internal health check path
		if qName == HealthCheckDomain && q.Qtype == dns.TypeTXT {
			remoteIP, _, _ := net.SplitHostPort(w.RemoteAddr().String())
			if remoteIP == "127.0.0.1" || remoteIP == "::1" {
				statusMsg := fmt.Sprintf("STATUS=OK; REQS=%d; RPS_1M=%.2f; RPS_5M=%.2f; UPTIME=%s",
					reqID, rps1m, rps5m, time.Since(startTime).Round(time.Second))
				txt, _ := dns.NewRR(fmt.Sprintf("%s 0 IN TXT \"%s\"", qName, statusMsg))
				m.Answer = append(m.Answer, txt)
				w.WriteMsg(m)
				return
			}
		}

		// O(1) Instant Map Lookup
		if typeMap, nameExists := activeBuf.Records[qName]; nameExists {
			if matches, typeExists := typeMap[q.Qtype]; typeExists {
				count := len(matches)
				if count > 0 {
					// Round-robin rotation offset using the atomic counter
					offset := int(reqID % uint64(count))
					for i := 0; i < count; i++ {
						m.Answer = append(m.Answer, matches[(i+offset)%count])
					}
				}
			}
		}
	}
	w.WriteMsg(m)
}

func main() {
	startTime = time.Now()

	flag.IntVar(&maxRecords, "size", 10000, "Maximum records per buffer")
	flag.IntVar(&port, "port", 5353, "UDP port")
	flag.StringVar(&listenAddr, "listen", "", "Listen IP address (default: all interfaces)")
	flag.StringVar(&tsvPath, "file", "records.tsv", "TSV file path")

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "%s - Extreme Stable DNS\nUsage:\n", appName)
		flag.PrintDefaults()
	}
	flag.Parse()

	// Initialize buffers
	for i := 0; i < 2; i++ {
		buffers[i] = &DataStore{Records: make(map[string]map[uint16][]dns.RR)}
	}

	if err := loadRecords(); err != nil {
		log.Fatalf("Initial load failed: %v", err)
	}

	go monitorStats()
	go func() {
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGHUP)
		for range sigChan {
			log.Printf("SIGHUP received, reloading TSV...")
			if err := loadRecords(); err != nil {
				log.Printf("Reload failed: %v", err)
			}
		}
	}()

	dns.HandleFunc(".", handleDnsRequest)
	//addr := fmt.Sprintf(":%d", port)
	addr := net.JoinHostPort(listenAddr, fmt.Sprintf("%d", port))
	log.Printf("%s live on %s (PID: %d) with capacity %d", appName, addr, os.Getpid(), maxRecords)
	log.Fatal(dns.ListenAndServe(addr, "udp", nil))
}
