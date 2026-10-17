//go:build linux

package main

import (
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"os"
	"syscall"
	"testing"
	"unsafe"
)

func TestReceiveTermination(t *testing.T) {
	for _, tt := range []struct {
		name     string
		err      error
		reason   string
		complete bool
	}{
		{"deadline", fmt.Errorf("read: %w", os.ErrDeadlineExceeded), "deadline", true},
		{"closed early", net.ErrClosed, "closed", false},
		{"unexpected failure", errors.New("injected receive failure"), "read_error", false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			reason, complete := receiveTermination(tt.err)
			if reason != tt.reason || complete != tt.complete {
				t.Fatalf("got (%s, %v), want (%s, %v)", reason, complete, tt.reason, tt.complete)
			}
		})
	}
}

func TestVerdictBoundaryAndPrecedence(t *testing.T) {
	group, src := net.ParseIP("239.1.1.1"), net.ParseIP("192.168.10.20")
	for _, tt := range []struct {
		name     string
		flags    int
		ok       bool
		dst      net.IP
		iface, n int
		source   net.IP
		want     string
	}{
		{"valid", 0, true, group, 2, 64, nil, "accept"},
		{"unicast injection", 0, true, net.ParseIP("192.168.10.1"), 2, 64, nil, "wrong_destination"},
		{"ancillary first", syscall.MSG_CTRUNC, true, group, 3, 10000, nil, "truncated"},
		{"missing metadata", 0, false, nil, 0, 64, nil, "truncated"},
		{"interface before size", 0, true, group, 3, 10000, nil, "wrong_ingress"},
		{"size before source", 0, true, group, 2, 10000, net.ParseIP("192.168.10.21"), "oversize"},
		{"wrong source", 0, true, group, 2, 64, net.ParseIP("192.168.10.21"), "source_filtered"},
		{"exactly max accepted", 0, true, group, 2, 9000, nil, "accept"},
		{"one over max", 0, true, group, 2, 9001, nil, "oversize"},
		{"kernel truncation flag alone", syscall.MSG_TRUNC, true, group, 2, 64, nil, "oversize"},
		{"ingress before destination", 0, true, net.ParseIP("192.168.10.1"), 1, 64, nil, "wrong_ingress"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			if got := verdict(tt.flags, tt.ok, tt.dst, tt.iface, tt.n, src, group, 2, tt.source, 9000); got != tt.want {
				t.Fatalf("got %s, want %s", got, tt.want)
			}
		})
	}
}

// cmsg builds one control message the way the kernel lays it out.
func cmsg(level, typ int32, data []byte) []byte {
	b := make([]byte, syscall.CmsgSpace(len(data)))
	h := (*syscall.Cmsghdr)(unsafe.Pointer(&b[0]))
	h.Level, h.Type = level, typ
	h.SetLen(syscall.CmsgLen(len(data)))
	copy(b[syscall.CmsgLen(0):], data)
	return b
}

// inPktinfo encodes struct in_pktinfo {int ipi_ifindex; in_addr ipi_spec_dst; in_addr ipi_addr;}.
func inPktinfo(ifindex int32, specDst, addr string) []byte {
	b := make([]byte, 12)
	binary.NativeEndian.PutUint32(b[0:4], uint32(ifindex))
	copy(b[4:8], net.ParseIP(specDst).To4())
	copy(b[8:12], net.ParseIP(addr).To4())
	return b
}

func TestPktinfo(t *testing.T) {
	valid := cmsg(syscall.IPPROTO_IP, syscall.IP_PKTINFO, inPktinfo(7, "192.168.10.1", "239.1.1.1"))
	other := cmsg(syscall.SOL_SOCKET, syscall.SCM_TIMESTAMP, make([]byte, 16))
	short := cmsg(syscall.IPPROTO_IP, syscall.IP_PKTINFO, make([]byte, 8))
	for _, tt := range []struct {
		name    string
		oob     []byte
		dst     string
		ifindex int
		ok      bool
	}{
		// ipi_addr (header destination) must be used, not ipi_spec_dst (local address).
		{"header destination and ifindex", valid, "239.1.1.1", 7, true},
		{"other cmsg first", append(append([]byte(nil), other...), valid...), "239.1.1.1", 7, true},
		{"empty", nil, "", 0, false},
		{"short data", short, "", 0, false},
		{"truncated header", valid[:4], "", 0, false},
		{"unrelated only", other, "", 0, false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			dst, ifindex, ok := pktinfo(tt.oob)
			if ok != tt.ok || ifindex != tt.ifindex || (tt.ok && dst.String() != tt.dst) {
				t.Fatalf("got (%v, %d, %v), want (%s, %d, %v)", dst, ifindex, ok, tt.dst, tt.ifindex, tt.ok)
			}
		})
	}
}

func TestSortOriginsDeterministic(t *testing.T) {
	// These two keys collided under the old fmt.Sprint-based sort key.
	counts := map[origin]int{
		{Dst: "239.1.1.1", IfIndex: 23, Src: "10.0.0.1", Verdict: "accept"}:       1,
		{Dst: "239.1.1.12", IfIndex: 3, Src: "10.0.0.1", Verdict: "accept"}:       2,
		{Dst: "239.1.1.1", IfIndex: 10, Src: "10.0.0.1", Verdict: "accept"}:       3,
		{Dst: "239.1.1.1", IfIndex: 2, Src: "10.0.0.1", Verdict: "wrong_ingress"}: 4,
	}
	want := []int{4, 3, 1, 2} // Dst, then numeric IfIndex
	for run := 0; run < 20; run++ {
		got := sortOrigins(counts)
		for i, o := range got {
			if o.Count != want[i] {
				t.Fatalf("run %d: order %v, want counts %v", run, got, want)
			}
		}
	}
}
