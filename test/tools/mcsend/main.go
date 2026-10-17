//go:build linux

// Command mcsend sends numbered UDP datagrams for mcgw tests.
//
// Payload layout: bytes 0-7 sequence number, bytes 8-15 send time in Unix
// nanoseconds (both big-endian), then a repeating pattern up to -size bytes.
// Sizes below 16 carry only the header bytes that fit.
//
// Exit status: 0 when every datagram was accepted by the local socket, 1 when
// any submission failed (the summary is still printed), 2 for usage or setup
// errors. Success means local submission, not receipt.
//
// Broadcast destinations need no flag: Go enables SO_BROADCAST on every UDP
// socket by default.
package main

import (
	"encoding/binary"
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"os"
	"syscall"
	"time"
)

// maxUDPPayload is the largest IPv4 UDP payload (65535 - 20 IP - 8 UDP).
const maxUDPPayload = 65507

func main() {
	to := flag.String("to", "", "destination ip:port (multicast, unicast or broadcast)")
	from := flag.String("from", "", "local source address (optional)")
	sport := flag.Int("sport", 0, "local source port (0 = ephemeral)")
	iface := flag.String("iface", "", "outgoing interface for multicast (optional; must exist)")
	n := flag.Int("n", 100, "number of datagrams")
	size := flag.Int("size", 64, "payload size in bytes (0-65507)")
	rate := flag.Int("rate", 100, "datagrams per second")
	ttl := flag.Int("ttl", 1, "multicast TTL")
	flag.Parse()
	if *n < 0 || *rate <= 0 {
		fail("-n must be nonnegative and -rate positive")
	}
	if *size < 0 || *size > maxUDPPayload {
		fail("-size must be between 0 and %d", maxUDPPayload)
	}

	dst, err := net.ResolveUDPAddr("udp4", *to)
	if err != nil || *to == "" {
		fail("invalid -to %q: %v", *to, err)
	}
	// Validate -iface even when it will not be used, so a typo is not silently ignored.
	ifindex := 0
	if *iface != "" {
		ifi, err := net.InterfaceByName(*iface)
		if err != nil {
			fail("interface %q: %v", *iface, err)
		}
		ifindex = ifi.Index
	}
	local := &net.UDPAddr{Port: *sport}
	if *from != "" {
		if local.IP = net.ParseIP(*from).To4(); local.IP == nil {
			fail("invalid -from %q", *from)
		}
	}
	conn, err := net.ListenUDP("udp4", local)
	if err != nil {
		fail("bind %v: %v", local, err)
	}
	defer func() { _ = conn.Close() }()

	if dst.IP.IsMulticast() {
		if err := control(conn, func(fd int) error {
			if ifindex != 0 {
				mreq := &syscall.IPMreqn{Ifindex: int32(ifindex)}
				if err := syscall.SetsockoptIPMreqn(fd, syscall.IPPROTO_IP, syscall.IP_MULTICAST_IF, mreq); err != nil {
					return fmt.Errorf("IP_MULTICAST_IF: %w", err)
				}
			}
			return syscall.SetsockoptInt(fd, syscall.IPPROTO_IP, syscall.IP_MULTICAST_TTL, *ttl)
		}); err != nil {
			fail("%v", err)
		}
	}

	payload := make([]byte, *size)
	interval := time.Second / time.Duration(*rate)
	sent, errs := 0, 0
	var firstErr error
	next := time.Now()
	for seq := 0; seq < *n; seq++ {
		fillPayload(payload, uint64(seq), time.Now())
		if _, err := conn.WriteToUDP(payload, dst); err != nil {
			errs++
			if firstErr == nil {
				firstErr = err
			}
		} else {
			sent++
		}
		if seq == *n-1 {
			break // no pacing delay after the final datagram
		}
		// Pace from the schedule, but never send a backlog in a burst after a stall:
		// a burst could overflow the system under test and look like its loss.
		next = next.Add(interval)
		if now := time.Now(); next.Before(now) {
			next = now
		}
		time.Sleep(time.Until(next))
	}
	if firstErr != nil {
		fmt.Fprintf(os.Stderr, "mcsend: %d of %d submissions failed; first error: %v\n", errs, *n, firstErr)
	}

	// "from" is the bound local address; 0.0.0.0 means the kernel chose the source.
	if err := json.NewEncoder(os.Stdout).Encode(map[string]any{
		"tool": "mcsend", "to": dst.String(), "from": conn.LocalAddr().String(),
		"iface": *iface, "size": *size, "n": *n, "rate": *rate,
		"sent": sent, "errors": errs,
	}); err != nil {
		fail("write summary: %v", err)
	}
	if errs != 0 {
		os.Exit(1)
	}
}

// fillPayload writes the sequence number and send time into the start of b
// (truncated when b is shorter than 16 bytes) and a repeating pattern after it.
func fillPayload(b []byte, seq uint64, now time.Time) {
	var header [16]byte
	binary.BigEndian.PutUint64(header[0:8], seq)
	binary.BigEndian.PutUint64(header[8:16], uint64(now.UnixNano()))
	copy(b, header[:])
	for i := len(header); i < len(b); i++ {
		b[i] = byte(i)
	}
}

func control(conn *net.UDPConn, fn func(fd int) error) error {
	raw, err := conn.SyscallConn()
	if err != nil {
		return err
	}
	var inner error
	if err := raw.Control(func(fd uintptr) { inner = fn(int(fd)) }); err != nil {
		return err
	}
	return inner
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "mcsend: "+format+"\n", args...)
	os.Exit(2)
}
