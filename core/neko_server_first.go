// NekoVPN (Annoyt/vpnautodeploy_client): servers behind the bot's
// server-first front (bot repo IMPROVEMENT_PLAN G4, AGENTS.md §62).
//
// Since 2026-11-19 a filter in front of our entry drops every connection from
// Russia in which the client sends first: the TCP handshake completes, and a
// TLS ClientHello, a QUIC packet or an SSH client's banner never arrives. A
// connection in which the server speaks first passes both ways. The bot's
// front writes one banner line before anything else, then pipes to the usual
// Reality and ShadowTLS servers; the bot gives this app a twin of each such
// server on the front's port, marked "neko-server-first: true".
//
// mihomo cannot wait for a server's first line, so the core patches the raw
// config at load time: a marked proxy is dialed through a local SOCKS5 helper
// (proxy "neko-server-first", 127.0.0.1 and a port the system picks). The
// helper opens the connection, reads and drops the banner line, and only then
// lets mihomo start its handshake. The marker is removed before mihomo reads
// the proxy. The helper's sockets are made by mihomo's dialer, so they leave
// outside the tunnel like every server connection; that is why it connects
// only to the servers the current profile marks: another app on the phone
// must not use it to reach anything else.
package core

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/netip"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/log"
)

const (
	nekoServerFirstName   = "neko-server-first"
	nekoServerFirstMarker = "neko-server-first"
	// The front's line: at most 253 characters and CRLF.
	nekoBannerMax     = 255
	nekoBannerTimeout = 10 * time.Second
	nekoSFDialTimeout = 10 * time.Second
	nekoSocksTimeout  = 10 * time.Second
)

// SOCKS5 replies (RFC 1928).
const (
	nekoSocksOK            = 0x00
	nekoSocksNotAllowed    = 0x02
	nekoSocksRefused       = 0x05
	nekoSocksNoCommand     = 0x07
	nekoSocksNoAddressType = 0x08
	nekoSocksVersion       = 0x05
	nekoSocksNoAuth        = 0x00
	nekoSocksNoAcceptable  = 0xff
	nekoSocksCmdConnect    = 0x01
	nekoSocksAddressIPv4   = 0x01
	nekoSocksAddressDomain = 0x03
	nekoSocksAddressIPv6   = 0x04
)

type nekoServerFirstHelper struct {
	mu       sync.Mutex
	listener net.Listener
	allowed  map[string]bool
	dial     func(ctx context.Context, network, address string) (net.Conn, error)
}

var nekoServerFirst = &nekoServerFirstHelper{
	dial: func(ctx context.Context, network, address string) (net.Conn, error) {
		return dialer.DialContext(ctx, network, address)
	},
}

// nekoAddressKey is a server's address the way the helper compares it: an IP
// in its canonical form (an IPv4-mapped one as IPv4), a name in lower case.
func nekoAddressKey(host string, port int) string {
	host = strings.TrimSuffix(strings.TrimPrefix(strings.TrimSpace(host), "["), "]")
	if address, err := netip.ParseAddr(host); err == nil {
		host = address.Unmap().String()
	} else {
		host = strings.ToLower(host)
	}
	return net.JoinHostPort(host, strconv.Itoa(port))
}

func nekoTruthy(value any) bool {
	switch v := value.(type) {
	case bool:
		return v
	case string:
		return strings.EqualFold(strings.TrimSpace(v), "true")
	}
	return false
}

func nekoProxyPort(value any) int {
	switch v := value.(type) {
	case int:
		return v
	case int64:
		return int(v)
	case uint64:
		return int(v)
	case float64:
		if v == float64(int(v)) {
			return int(v)
		}
	case string:
		if port, err := strconv.Atoi(strings.TrimSpace(v)); err == nil {
			return port
		}
	}
	return 0
}

// patchNekoServerFirst dials every marked proxy through the helper. It runs
// after patchNekoGateway: a proxy the gateway already chains keeps its chain
// (both at once are not supported) and is not added to what the helper
// reaches. Should the helper fail to listen, the marked proxies are left
// without a chain: mihomo loads the profile, and the fallback group moves on
// from servers that cannot answer.
func patchNekoServerFirst(raw *config.RawConfig) {
	allowed := map[string]bool{}
	var marked []map[string]any
	for _, proxy := range raw.Proxy {
		value, present := proxy[nekoServerFirstMarker]
		if !present {
			continue
		}
		delete(proxy, nekoServerFirstMarker)
		if !nekoTruthy(value) {
			continue
		}
		if _, chained := proxy["dialer-proxy"]; chained {
			continue
		}
		server, _ := proxy["server"].(string)
		port := nekoProxyPort(proxy["port"])
		if strings.TrimSpace(server) == "" || !nekoValidPort(port) {
			continue
		}
		allowed[nekoAddressKey(server, port)] = true
		marked = append(marked, proxy)
	}
	if len(marked) == 0 {
		nekoServerFirst.setAllowed(nil)
		return
	}
	port, err := nekoServerFirst.ensure()
	if err != nil {
		log.Warnln("[NEKO] server-first helper cannot listen: %v", err)
		nekoServerFirst.setAllowed(nil)
		return
	}
	for _, proxy := range marked {
		proxy["dialer-proxy"] = nekoServerFirstName
	}
	raw.Proxy = append(raw.Proxy, map[string]any{
		"name":   nekoServerFirstName,
		"type":   "socks5",
		"server": "127.0.0.1",
		"port":   port,
		"udp":    false,
	})
	nekoServerFirst.setAllowed(allowed)
}

// ensure starts the helper once; it serves for the life of the process.
func (h *nekoServerFirstHelper) ensure() (int, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.listener == nil {
		listener, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			return 0, err
		}
		h.listener = listener
		go h.serve(listener)
	}
	return h.listener.Addr().(*net.TCPAddr).Port, nil
}

func (h *nekoServerFirstHelper) setAllowed(allowed map[string]bool) {
	h.mu.Lock()
	h.allowed = allowed
	h.mu.Unlock()
}

func (h *nekoServerFirstHelper) isAllowed(key string) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.allowed[key]
}

func (h *nekoServerFirstHelper) serve(listener net.Listener) {
	for {
		conn, err := listener.Accept()
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				return
			}
			time.Sleep(100 * time.Millisecond)
			continue
		}
		go h.handle(conn)
	}
}

func (h *nekoServerFirstHelper) handle(client net.Conn) {
	_ = client.SetDeadline(time.Now().Add(nekoSocksTimeout))
	host, port, err := nekoSocksRequest(client)
	if err != nil {
		var reply nekoSocksError
		if errors.As(err, &reply) {
			nekoSocksReply(client, byte(reply))
		}
		client.Close()
		return
	}
	address := net.JoinHostPort(host, strconv.Itoa(port))
	if !h.isAllowed(nekoAddressKey(host, port)) {
		nekoSocksReply(client, nekoSocksNotAllowed)
		client.Close()
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), nekoSFDialTimeout)
	upstream, err := h.dial(ctx, "tcp", address)
	cancel()
	if err != nil {
		nekoSocksReply(client, nekoSocksRefused)
		client.Close()
		return
	}
	if err := nekoDropBanner(upstream); err != nil {
		log.Warnln("[NEKO] server-first %s: %v", address, err)
		nekoSocksReply(client, nekoSocksRefused)
		upstream.Close()
		client.Close()
		return
	}
	if err := nekoSocksReply(client, nekoSocksOK); err != nil {
		upstream.Close()
		client.Close()
		return
	}
	_ = client.SetDeadline(time.Time{})
	nekoPipe(client, upstream)
}

// nekoDropBanner reads the front's line, up to and with its line feed, and
// not one byte more: what follows belongs to the handshake.
func nekoDropBanner(conn net.Conn) error {
	_ = conn.SetReadDeadline(time.Now().Add(nekoBannerTimeout))
	defer conn.SetReadDeadline(time.Time{})
	var b [1]byte
	for n := 0; n < nekoBannerMax; n++ {
		if _, err := io.ReadFull(conn, b[:]); err != nil {
			return fmt.Errorf("no banner: %w", err)
		}
		if b[0] == '\n' {
			return nil
		}
	}
	return fmt.Errorf("no line feed in the first %d bytes", nekoBannerMax)
}

type nekoSocksError byte

func (e nekoSocksError) Error() string { return fmt.Sprintf("socks reply %#x", byte(e)) }

// nekoSocksRequest reads a SOCKS5 greeting (no authentication) and a CONNECT
// request, and answers the greeting. An error that wants a reply carries it.
func nekoSocksRequest(conn net.Conn) (string, int, error) {
	head := make([]byte, 2)
	if _, err := io.ReadFull(conn, head); err != nil {
		return "", 0, err
	}
	if head[0] != nekoSocksVersion || head[1] == 0 {
		return "", 0, errors.New("not socks5")
	}
	methods := make([]byte, head[1])
	if _, err := io.ReadFull(conn, methods); err != nil {
		return "", 0, err
	}
	if bytes.IndexByte(methods, nekoSocksNoAuth) < 0 {
		_, _ = conn.Write([]byte{nekoSocksVersion, nekoSocksNoAcceptable})
		return "", 0, errors.New("no acceptable method")
	}
	if _, err := conn.Write([]byte{nekoSocksVersion, nekoSocksNoAuth}); err != nil {
		return "", 0, err
	}
	request := make([]byte, 4)
	if _, err := io.ReadFull(conn, request); err != nil {
		return "", 0, err
	}
	if request[0] != nekoSocksVersion {
		return "", 0, errors.New("not socks5")
	}
	var host string
	switch request[3] {
	case nekoSocksAddressIPv4, nekoSocksAddressIPv6:
		size := 4
		if request[3] == nekoSocksAddressIPv6 {
			size = 16
		}
		ip := make([]byte, size)
		if _, err := io.ReadFull(conn, ip); err != nil {
			return "", 0, err
		}
		address, _ := netip.AddrFromSlice(ip)
		host = address.Unmap().String()
	case nekoSocksAddressDomain:
		size := make([]byte, 1)
		if _, err := io.ReadFull(conn, size); err != nil {
			return "", 0, err
		}
		name := make([]byte, size[0])
		if _, err := io.ReadFull(conn, name); err != nil {
			return "", 0, err
		}
		host = string(name)
	default:
		return "", 0, nekoSocksError(nekoSocksNoAddressType)
	}
	port := make([]byte, 2)
	if _, err := io.ReadFull(conn, port); err != nil {
		return "", 0, err
	}
	if request[1] != nekoSocksCmdConnect {
		return "", 0, nekoSocksError(nekoSocksNoCommand)
	}
	return host, int(port[0])<<8 | int(port[1]), nil
}

func nekoSocksReply(conn net.Conn, code byte) error {
	_, err := conn.Write([]byte{nekoSocksVersion, code, 0x00, nekoSocksAddressIPv4, 0, 0, 0, 0, 0, 0})
	return err
}

type nekoCloseWriter interface{ CloseWrite() error }

// nekoPipe copies both ways. A clean end is passed on as a half-close, so
// the other side finishes its answer; a broken one closes both.
func nekoPipe(a, b net.Conn) {
	var once sync.Once
	closeBoth := func() {
		once.Do(func() {
			a.Close()
			b.Close()
		})
	}
	done := make(chan struct{}, 2)
	copyOne := func(dst, src net.Conn) {
		if _, err := io.Copy(dst, src); err != nil {
			closeBoth()
		} else if half, ok := dst.(nekoCloseWriter); ok {
			_ = half.CloseWrite()
		} else {
			closeBoth()
		}
		done <- struct{}{}
	}
	go copyOne(a, b)
	go copyOne(b, a)
	<-done
	<-done
	closeBoth()
}
