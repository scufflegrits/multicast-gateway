//go:build linux

package main

import (
	"encoding/binary"
	"testing"
	"time"
)

func TestNextSendAtAvoidsCatchUpBurst(t *testing.T) {
	previous := time.Unix(1700000000, 0)
	interval := 100 * time.Millisecond
	for _, tt := range []struct {
		name          string
		elapsed, want time.Duration
	}{
		{"on schedule", 0, interval},
		{"before next slot", 40 * time.Millisecond, interval},
		{"exactly next slot", interval, 2 * interval},
		{"blocked write or suspended process", 350 * time.Millisecond, 450 * time.Millisecond},
	} {
		t.Run(tt.name, func(t *testing.T) {
			got := nextSendAt(previous, previous.Add(tt.elapsed), interval)
			if want := previous.Add(tt.want); !got.Equal(want) {
				t.Fatalf("next send is %s after previous slot, want %s", got.Sub(previous), tt.want)
			}
		})
	}
}

func TestFillPayloadLayout(t *testing.T) {
	now := time.Unix(1700000000, 123456789)
	for _, size := range []int{0, 1, 8, 15, 16, 17, 64} {
		b := make([]byte, size)
		fillPayload(b, 42, now)
		if size >= 8 {
			if got := binary.BigEndian.Uint64(b[0:8]); got != 42 {
				t.Errorf("size %d: sequence %d, want 42", size, got)
			}
		}
		if size >= 16 {
			if got := int64(binary.BigEndian.Uint64(b[8:16])); got != now.UnixNano() {
				t.Errorf("size %d: timestamp %d, want %d", size, got, now.UnixNano())
			}
		}
		for i := 16; i < size; i++ {
			if b[i] != byte(i) {
				t.Fatalf("size %d: pattern byte %d = %d, want %d", size, i, b[i], byte(i))
			}
		}
	}
}

func TestFillPayloadShortKeepsHeaderPrefix(t *testing.T) {
	b := make([]byte, 4)
	fillPayload(b, 0x0102030405060708, time.Unix(0, 0))
	if want := []byte{1, 2, 3, 4}; string(b) != string(want) {
		t.Fatalf("got %v, want %v", b, want)
	}
}
