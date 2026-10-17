//go:build linux

package main

import (
	"encoding/binary"
	"testing"
	"time"
)

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
