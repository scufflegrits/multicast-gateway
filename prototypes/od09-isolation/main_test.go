//go:build linux

package main

import (
	"errors"
	"fmt"
	"net"
	"os"
	"syscall"
	"testing"
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
	} {
		t.Run(tt.name, func(t *testing.T) {
			if got := verdict(tt.flags, tt.ok, tt.dst, tt.iface, tt.n, src, group, 2, tt.source, 9000); got != tt.want {
				t.Fatalf("got %s, want %s", got, tt.want)
			}
		})
	}
}
