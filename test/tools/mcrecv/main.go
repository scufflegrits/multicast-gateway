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
	flag.Parse()

	addr, err := net.ResolveUDPAddr("udp4", *listen)
	if err != nil || *listen == "" {
		fmt.Fprintf(os.Stderr, "mcrecv: invalid -listen %q: %v\n", *listen, err)
		os.Exit(2)
	}
	conn, err := net.ListenUDP("udp4", addr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "mcrecv: bind %v: %v\n", addr, err)
		os.Exit(2)
	}
	stopOnSignal(conn)
	conn.SetReadDeadline(time.Now().Add(*duration))

	enc := json.NewEncoder(os.Stdout)
	buf := make([]byte, 65536)
	received, bytes, outOfOrder := 0, 0, 0
	var last int64 = -1
	sources := map[string]int{}
	for {
		n, src, err := conn.ReadFromUDP(buf)
		if err != nil {
			if !errors.Is(err, os.ErrDeadlineExceeded) && !errors.Is(err, net.ErrClosed) {
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
			enc.Encode(map[string]any{"seq": seq, "len": n, "src": src.String()})
		}
	}
	enc.Encode(map[string]any{
		"tool": "mcrecv", "listen": addr.String(), "received": received,
		"bytes": bytes, "out_of_order": outOfOrder, "sources": sources,
	})
}

// stopOnSignal closes the socket on SIGINT/SIGTERM so the summary still prints.
func stopOnSignal(conn *net.UDPConn) {
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	go func() { <-sig; conn.Close() }()
}
