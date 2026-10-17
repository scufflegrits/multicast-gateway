//go:build linux

// Command mcsend sends numbered UDP datagrams for mcgw tests.
//
// Payload layout: bytes 0-7 sequence number, bytes 8-15 send time in Unix
// nanoseconds (both big-endian), then a repeating pattern up to -size bytes.
// Sizes below 16 carry only the header bytes that fit.
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

func main() {
	to := flag.String("to", "", "destination ip:port (multicast or unicast)")
	from := flag.String("from", "", "local source address (optional)")
	sport := flag.Int("sport", 0, "local source port (0 = ephemeral)")
	iface := flag.String("iface", "", "outgoing interface for multicast (optional)")
	n := flag.Int("n", 100, "number of datagrams")
	size := flag.Int("size", 64, "payload size in bytes")
	rate := flag.Int("rate", 100, "datagrams per second")
	ttl := flag.Int("ttl", 1, "multicast TTL")
	flag.Parse()
	if *n < 0 || *size < 0 || *rate <= 0 {
		fail("-n and -size must be nonnegative; -rate must be positive")
	}

	dst, err := net.ResolveUDPAddr("udp4", *to)
	if err != nil || *to == "" {
		fail("invalid -to %q: %v", *to, err)
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
		ifindex := 0
		if *iface != "" {
			ifi, err := net.InterfaceByName(*iface)
			if err != nil {
				fail("interface %q: %v", *iface, err)
			}
			ifindex = ifi.Index
		}
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
	for i := 16; i < len(payload); i++ {
		payload[i] = byte(i)
	}
	header := make([]byte, 16)
	interval := time.Second / time.Duration(max(*rate, 1))
	sent, errs := 0, 0
	next := time.Now()
	for seq := 0; seq < *n; seq++ {
		binary.BigEndian.PutUint64(header[0:8], uint64(seq))
		binary.BigEndian.PutUint64(header[8:16], uint64(time.Now().UnixNano()))
		copy(payload, header)
		if _, err := conn.WriteToUDP(payload, dst); err != nil {
			errs++
		} else {
			sent++
		}
		next = next.Add(interval)
		time.Sleep(time.Until(next))
	}

	if err := json.NewEncoder(os.Stdout).Encode(map[string]any{
		"tool": "mcsend", "to": dst.String(), "from": conn.LocalAddr().String(),
		"iface": *iface, "size": *size, "sent": sent, "errors": errs,
	}); err != nil {
		fail("write summary: %v", err)
	}
	if errs != 0 {
		os.Exit(1)
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
