// Command mcrecv listens for unicast UDP datagrams sent by mcgw tests and
// reports what arrived: per-datagram JSON lines (with -lines) and a summary.
package main

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	listen := flag.String("listen", "", "local ip:port to listen on")
	duration := flag.Duration("duration", 5*time.Second, "how long to listen")
	lines := flag.Bool("lines", false, "print one JSON line per datagram")
	readyFile := flag.String("ready-file", "", "write readiness marker after socket setup")
	flag.Parse()
	if *duration <= 0 {
		fail("-duration must be positive")
	}

	addr, err := net.ResolveUDPAddr("udp4", *listen)
	if err != nil || *listen == "" {
		fail("invalid -listen %q: %v", *listen, err)
	}
	conn, err := net.ListenUDP("udp4", addr)
	if err != nil {
		fail("bind %v: %v", addr, err)
	}
	stopOnSignal(conn)
	if err := conn.SetReadDeadline(time.Now().Add(*duration)); err != nil {
		fail("set read deadline: %v", err)
	}

	if *readyFile != "" {
		if err := os.WriteFile(*readyFile, []byte("ready\n"), 0600); err != nil {
			fail("readiness marker: %v", err)
		}
	}
	termination, complete := "", false
	enc := json.NewEncoder(os.Stdout)
	buf := make([]byte, 65536)
	received, bytes, outOfOrder := 0, 0, 0
	var last int64 = -1
	sources := map[string]int{}
	for {
		n, src, err := conn.ReadFromUDP(buf)
		if err != nil {
			termination, complete = receiveTermination(err)
			if termination == "read_error" {
				fmt.Fprintf(os.Stderr, "mcrecv: read: %v\n", err)
			}
			break
		}
		received++
		bytes += n
		sources[src.String()]++
		seq := int64(-1)
		if n >= 8 {
			seq = int64(binary.BigEndian.Uint64(buf[0:8]))
			if seq <= last {
				outOfOrder++
			}
			last = seq
		}
		if *lines {
			_ = enc.Encode(map[string]any{"seq": seq, "len": n, "src": src.String()})
		}
	}
	if err := enc.Encode(map[string]any{
		"complete": complete, "termination": termination,
		"tool": "mcrecv", "listen": addr.String(), "received": received,
		"bytes": bytes, "out_of_order": outOfOrder, "sources": sources,
	}); err != nil {
		fail("write summary: %v", err)
	}
	if !complete {
		os.Exit(1)
	}
}

// stopOnSignal closes the socket on SIGINT/SIGTERM so the summary still prints.
func stopOnSignal(conn *net.UDPConn) {
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	go func() { <-sig; _ = conn.Close() }()
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "mcrecv: "+format+"\n", args...)
	os.Exit(2)
}

// Only deadline expiry completes the requested observation window.
func receiveTermination(err error) (string, bool) {
	if errors.Is(err, os.ErrDeadlineExceeded) {
		return "deadline", true
	}
	if errors.Is(err, net.ErrClosed) {
		return "closed", false
	}
	return "read_error", false
}
