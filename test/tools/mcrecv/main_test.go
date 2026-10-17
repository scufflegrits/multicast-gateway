package main

import (
	"errors"
	"fmt"
	"net"
	"os"
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
