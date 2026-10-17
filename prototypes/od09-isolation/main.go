//go:build linux

// Command od09-isolation is a throwaway OD-09 prototype: a minimal IPv4
// multicast receiver whose socket isolation options can be switched, so a run
// shows which datagrams the kernel delivers to the socket and which the
// per-datagram checks would reject.
//
// It is not mcgw code and must not be imported by the daemon.
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
	"runtime"
	"sort"
	"syscall"
	"time"
)

// IP_MULTICAST_ALL from linux/in.h; not exported by package syscall.
const ipMulticastAll = 49

type origin struct {
	Dst     string `json:"dst"`
	IfIndex int    `json:"ifindex"`
	Src     string `json:"src"`
	Verdict string `json:"verdict"`
	Count   int    `json:"count"`
}

func main() {
	name := flag.String("name", "R", "receiver label used in output")
	groupS := flag.String("group", "", "multicast group, e.g. 239.1.1.1")
	port := flag.Int("port", 3000, "UDP port")
	ifName := flag.String("iface", "", "ingress interface name")
	sourceS := flag.String("source", "", "source address for a source-specific join (optional)")
	bind := flag.String("bind", "group", "bind address: group or wildcard")
	mcall := flag.String("mcall", "default", "IP_MULTICAST_ALL: default, 0 or 1")
	maxDatagram := flag.Int("max", 9000, "maximum accepted payload size")
	duration := flag.Duration("duration", 5*time.Second, "how long to receive")
	lines := flag.Bool("lines", false, "print one JSON line per datagram")
	flag.Parse()

	group := net.ParseIP(*groupS).To4()
	if group == nil || !group.IsMulticast() {
		fail("invalid -group %q", *groupS)
	}
	ifi, err := net.InterfaceByName(*ifName)
	if err != nil {
		fail("interface %q: %v", *ifName, err)
	}
	var source net.IP
	if *sourceS != "" {
		if source = net.ParseIP(*sourceS).To4(); source == nil {
			fail("invalid -source %q", *sourceS)
		}
	}

	fd, err := openSocket(group, *port, ifi, source, *bind, *mcall)
	if err != nil {
		fail("%v", err)
	}
	file := os.NewFile(uintptr(fd), "od09")
	pc, err := net.FilePacketConn(file)
	_ = file.Close()
	if err != nil {
		fail("wrap socket: %v", err)
	}
	conn := pc.(*net.UDPConn)
	stopOnSignal(conn)
	if err := conn.SetReadDeadline(time.Now().Add(*duration)); err != nil {
		fail("set read deadline: %v", err)
	}

	enc := json.NewEncoder(os.Stdout)
	buf := make([]byte, *maxDatagram+1)
	oob := make([]byte, 128)
	counts := map[origin]int{}
	verdicts := map[string]int{}
	received, foreign := 0, 0
	for {
		n, oobn, flags, src, err := conn.ReadMsgUDP(buf, oob)
		if err != nil {
			if !errors.Is(err, os.ErrDeadlineExceeded) && !errors.Is(err, net.ErrClosed) {
				fmt.Fprintf(os.Stderr, "od09: read: %v\n", err)
			}
			break
		}
		received++
		dst, ifindex, ok := pktinfo(oob[:oobn])
		own := ok && dst.Equal(group) && ifindex == ifi.Index && (source == nil || src.IP.Equal(source))
		if !own {
			foreign++
		}
		v := verdict(flags, ok, dst, ifindex, n, src.IP, group, ifi.Index, source, *maxDatagram)
		verdicts[v]++
		key := origin{Dst: ipString(dst), IfIndex: ifindex, Src: src.IP.String(), Verdict: v}
		counts[key]++
		if *lines {
			_ = enc.Encode(map[string]any{"name": *name, "dst": key.Dst, "ifindex": ifindex,
				"src": src.String(), "len": n, "seq": seq(buf[:min(n, len(buf))]), "verdict": v})
		}
	}

	origins := make([]origin, 0, len(counts))
	for k, c := range counts {
		k.Count = c
		origins = append(origins, k)
	}
	sort.Slice(origins, func(i, j int) bool {
		a, b := origins[i], origins[j]
		return fmt.Sprint(a.Dst, a.IfIndex, a.Src, a.Verdict) < fmt.Sprint(b.Dst, b.IfIndex, b.Src, b.Verdict)
	})
	if err := enc.Encode(map[string]any{
		"tool": "od09-isolation", "name": *name, "go": runtime.Version(),
		"options": map[string]any{"group": group.String(), "port": *port, "iface": ifi.Name,
			"ifindex": ifi.Index, "source": *sourceS, "bind": *bind, "mcall": *mcall, "max": *maxDatagram},
		"received": received, "foreign_delivered": foreign, "verdicts": verdicts, "origins": origins,
	}); err != nil {
		fail("write summary: %v", err)
	}
}

// openSocket creates the receive socket with the selected isolation options.
func openSocket(group net.IP, port int, ifi *net.Interface, source net.IP, bind, mcall string) (int, error) {
	fd, err := syscall.Socket(syscall.AF_INET, syscall.SOCK_DGRAM|syscall.SOCK_CLOEXEC, syscall.IPPROTO_UDP)
	if err != nil {
		return -1, fmt.Errorf("socket: %w", err)
	}
	set := func(level, opt, v int, label string) error {
		if err := syscall.SetsockoptInt(fd, level, opt, v); err != nil {
			return fmt.Errorf("%s: %w", label, err)
		}
		return nil
	}
	// SO_REUSEADDR lets several receivers share the port, as the test cases require.
	if err := set(syscall.SOL_SOCKET, syscall.SO_REUSEADDR, 1, "SO_REUSEADDR"); err != nil {
		return -1, err
	}
	if err := set(syscall.IPPROTO_IP, syscall.IP_PKTINFO, 1, "IP_PKTINFO"); err != nil {
		return -1, err
	}
	switch mcall {
	case "default":
	case "0", "1":
		if err := set(syscall.IPPROTO_IP, ipMulticastAll, int(mcall[0]-'0'), "IP_MULTICAST_ALL"); err != nil {
			return -1, err
		}
	default:
		return -1, fmt.Errorf("invalid -mcall %q", mcall)
	}

	sa := &syscall.SockaddrInet4{Port: port}
	switch bind {
	case "group":
		copy(sa.Addr[:], group)
	case "wildcard":
	default:
		return -1, fmt.Errorf("invalid -bind %q", bind)
	}
	if err := syscall.Bind(fd, sa); err != nil {
		return -1, fmt.Errorf("bind %s:%d: %w", bind, port, err)
	}

	if source == nil {
		mreq := &syscall.IPMreqn{Ifindex: int32(ifi.Index)}
		copy(mreq.Multiaddr[:], group)
		if err := syscall.SetsockoptIPMreqn(fd, syscall.IPPROTO_IP, syscall.IP_ADD_MEMBERSHIP, mreq); err != nil {
			return -1, fmt.Errorf("IP_ADD_MEMBERSHIP: %w", err)
		}
		return fd, nil
	}
	// struct ip_mreq_source { imr_multiaddr; imr_interface; imr_sourceaddr; }
	local, err := ifaceAddr(ifi)
	if err != nil {
		return -1, err
	}
	mreq := make([]byte, 0, 12)
	mreq = append(append(append(mreq, group...), local...), source...)
	if err := syscall.SetsockoptString(fd, syscall.IPPROTO_IP, syscall.IP_ADD_SOURCE_MEMBERSHIP, string(mreq)); err != nil {
		return -1, fmt.Errorf("IP_ADD_SOURCE_MEMBERSHIP: %w", err)
	}
	return fd, nil
}

// verdict applies the architecture §4 rejection precedence.
func verdict(flags int, ok bool, dst net.IP, ifindex, n int, src, group net.IP, want int, source net.IP, max int) string {
	switch {
	case flags&syscall.MSG_CTRUNC != 0 || !ok:
		return "truncated"
	case ifindex != want:
		return "wrong_ingress"
	case !dst.Equal(group):
		return "wrong_destination"
	case flags&syscall.MSG_TRUNC != 0 || n > max:
		return "oversize"
	case source != nil && !src.Equal(source):
		return "source_filtered"
	}
	return "accept"
}

// pktinfo extracts the header destination and arrival interface from IP_PKTINFO.
func pktinfo(oob []byte) (net.IP, int, bool) {
	msgs, err := syscall.ParseSocketControlMessage(oob)
	if err != nil {
		return nil, 0, false
	}
	for _, m := range msgs {
		if m.Header.Level == syscall.IPPROTO_IP && m.Header.Type == syscall.IP_PKTINFO && len(m.Data) >= 12 {
			ifindex := int(int32(binary.NativeEndian.Uint32(m.Data[0:4])))
			return net.IP(append([]byte(nil), m.Data[8:12]...)), ifindex, true
		}
	}
	return nil, 0, false
}

func ifaceAddr(ifi *net.Interface) (net.IP, error) {
	addrs, err := ifi.Addrs()
	if err != nil {
		return nil, err
	}
	for _, a := range addrs {
		if ipn, ok := a.(*net.IPNet); ok && ipn.IP.To4() != nil {
			return ipn.IP.To4(), nil
		}
	}
	return nil, fmt.Errorf("interface %s has no IPv4 address", ifi.Name)
}

func seq(b []byte) int64 {
	if len(b) < 8 {
		return -1
	}
	return int64(binary.BigEndian.Uint64(b[0:8]))
}

func ipString(ip net.IP) string {
	if ip == nil {
		return ""
	}
	return ip.String()
}

func stopOnSignal(conn *net.UDPConn) {
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	go func() { <-sig; _ = conn.Close() }()
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "od09: "+format+"\n", args...)
	os.Exit(2)
}
