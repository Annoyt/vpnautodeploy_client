package core

import (
	"bytes"
	"context"
	"encoding/binary"
	"io"
	"net"
	"strconv"
	"testing"
	"time"
)

const nekoServerFirstProfile = `
proxies:
  - {name: u1-reality-sf, type: vless, server: 203.0.113.20, port: 2443, uuid: 0f9e8d7c-6b5a-4f3e-8d2c-1b0a9f8e7d6c, neko-server-first: true}
  - {name: u1-reality, type: vless, server: 203.0.113.20, port: 8443, uuid: 0f9e8d7c-6b5a-4f3e-8d2c-1b0a9f8e7d6c}
  - {name: u1-stls-sf, type: ss, server: Entry.Example, port: "2444", cipher: 2022-blake3-aes-128-gcm, password: x, neko-server-first: "true"}
  - {name: off, type: vless, server: 203.0.113.21, port: 2443, uuid: 0f9e8d7c-6b5a-4f3e-8d2c-1b0a9f8e7d6c, neko-server-first: false}
  - {name: chained, type: vless, server: 203.0.113.22, port: 2443, uuid: 0f9e8d7c-6b5a-4f3e-8d2c-1b0a9f8e7d6c, neko-server-first: true, dialer-proxy: neko-gateway}
proxy-groups:
  - {name: VPN, type: select, proxies: [u1-reality-sf, u1-reality, u1-stls-sf, off, chained]}
`

func TestPatchServerFirstChainsTheMarkedProxies(t *testing.T) {
	raw := nekoRaw(t, nekoServerFirstProfile)
	patchNekoServerFirst(raw)

	for _, name := range []string{"u1-reality-sf", "u1-stls-sf"} {
		proxy := nekoProxy(raw, name)
		if proxy["dialer-proxy"] != nekoServerFirstName {
			t.Fatalf("%s: dialer-proxy %v", name, proxy["dialer-proxy"])
		}
	}
	if _, ok := nekoProxy(raw, "u1-reality")["dialer-proxy"]; ok {
		t.Fatal("an unmarked proxy got a chain")
	}
	if _, ok := nekoProxy(raw, "off")["dialer-proxy"]; ok {
		t.Fatal("a proxy marked false got a chain")
	}
	if nekoProxy(raw, "chained")["dialer-proxy"] != "neko-gateway" {
		t.Fatal("an existing chain was replaced")
	}
	for _, proxy := range raw.Proxy {
		if _, ok := proxy[nekoServerFirstMarker]; ok && proxy["name"] != nekoServerFirstName {
			t.Fatalf("%v: the marker reaches mihomo", proxy["name"])
		}
	}

	helper := nekoProxy(raw, nekoServerFirstName)
	if helper == nil {
		t.Fatal("no helper proxy")
	}
	port, _ := nekoServerFirst.ensure()
	if helper["type"] != "socks5" || helper["server"] != "127.0.0.1" || helper["port"] != port ||
		helper["udp"] != false {
		t.Fatalf("helper proxy %v", helper)
	}
	for key, want := range map[string]bool{
		"203.0.113.20:2443":  true,
		"entry.example:2444": true,
		"203.0.113.20:8443":  false,
		"203.0.113.21:2443":  false,
		"203.0.113.22:2443":  false,
	} {
		if nekoServerFirst.isAllowed(key) != want {
			t.Fatalf("%s allowed: %v", key, !want)
		}
	}
}

func TestPatchServerFirstWithoutMarkedProxiesAddsNothingAndAllowsNothing(t *testing.T) {
	nekoServerFirst.setAllowed(map[string]bool{"203.0.113.20:2443": true})
	raw := nekoRaw(t, nekoGatewayProfile)
	before := len(raw.Proxy)
	patchNekoServerFirst(raw)
	if len(raw.Proxy) != before || nekoProxy(raw, nekoServerFirstName) != nil {
		t.Fatal("a helper proxy without marked servers")
	}
	if nekoServerFirst.isAllowed("203.0.113.20:2443") {
		t.Fatal("the last profile's servers are still allowed")
	}
}

func TestPatchServerFirstAfterTheGatewayLeavesItsChains(t *testing.T) {
	raw := nekoRaw(t, nekoServerFirstProfile)
	joinNekoGateway(raw, &nekoGatewayJoin{Hosts: []string{"192.168.43.1"}, Port: 7891,
		Username: "u", Password: "p"})
	patchNekoServerFirst(raw)
	if nekoProxy(raw, "u1-reality-sf")["dialer-proxy"] != nekoGatewayName {
		t.Fatal("the gateway's chain was replaced")
	}
	if nekoProxy(raw, nekoServerFirstName) != nil {
		t.Fatal("a helper proxy for servers the gateway carries")
	}
}

func TestNekoAddressKey(t *testing.T) {
	for _, c := range []struct {
		host string
		port int
		want string
	}{
		{"203.0.113.20", 2443, "203.0.113.20:2443"},
		{"::ffff:203.0.113.20", 2443, "203.0.113.20:2443"},
		{"[2001:DB8::1]", 2444, "[2001:db8::1]:2444"},
		{" Entry.Example ", 2444, "entry.example:2444"},
	} {
		if got := nekoAddressKey(c.host, c.port); got != c.want {
			t.Fatalf("%q: %q, want %q", c.host, got, c.want)
		}
	}
}

// A stand-in for the front: a banner line, then an echo.
func nekoTestFront(t *testing.T, banner []byte) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { listener.Close() })
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				defer c.Close()
				if _, err := c.Write(banner); err != nil {
					return
				}
				_, _ = io.Copy(c, c)
			}(conn)
		}
	}()
	return listener.Addr().String()
}

func nekoTestHelper(t *testing.T, allowed ...string) string {
	t.Helper()
	helper := &nekoServerFirstHelper{
		allowed: map[string]bool{},
		dial: func(ctx context.Context, network, address string) (net.Conn, error) {
			var d net.Dialer
			return d.DialContext(ctx, network, address)
		},
	}
	for _, key := range allowed {
		helper.allowed[key] = true
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { listener.Close() })
	go helper.serve(listener)
	return listener.Addr().String()
}

// nekoSocksConnect speaks a SOCKS5 CONNECT to the helper and returns the
// connection and the reply code.
func nekoSocksConnect(t *testing.T, helper string, request []byte) (net.Conn, byte) {
	t.Helper()
	conn, err := net.Dial("tcp", helper)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := conn.Write([]byte{5, 1, 0}); err != nil {
		t.Fatal(err)
	}
	greeting := make([]byte, 2)
	if _, err := io.ReadFull(conn, greeting); err != nil || !bytes.Equal(greeting, []byte{5, 0}) {
		t.Fatalf("greeting %v %v", greeting, err)
	}
	if _, err := conn.Write(request); err != nil {
		t.Fatal(err)
	}
	reply := make([]byte, 10)
	if _, err := io.ReadFull(conn, reply); err != nil {
		t.Fatalf("reply: %v", err)
	}
	return conn, reply[1]
}

func nekoIPv4Request(address string) []byte {
	host, portText, _ := net.SplitHostPort(address)
	port, _ := strconv.Atoi(portText)
	request := append([]byte{5, 1, 0, 1}, net.ParseIP(host).To4()...)
	return binary.BigEndian.AppendUint16(request, uint16(port))
}

func nekoDomainRequest(host string, port int) []byte {
	request := append([]byte{5, 1, 0, 3, byte(len(host))}, host...)
	return binary.BigEndian.AppendUint16(request, uint16(port))
}

func TestHelperDropsTheBannerAndPipesTheRest(t *testing.T) {
	front := nekoTestFront(t, []byte("SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.20\r\n"))
	helper := nekoTestHelper(t, front)
	conn, code := nekoSocksConnect(t, helper, nekoIPv4Request(front))
	if code != nekoSocksOK {
		t.Fatalf("reply %#x", code)
	}
	// The first byte after the reply is the echo of ours, never the banner.
	if _, err := conn.Write([]byte("hello")); err != nil {
		t.Fatal(err)
	}
	echo := make([]byte, 5)
	if _, err := io.ReadFull(conn, echo); err != nil || string(echo) != "hello" {
		t.Fatalf("echo %q %v", echo, err)
	}
}

func TestHelperKeepsWhatFollowsTheBanner(t *testing.T) {
	// The banner and the first handshake bytes in one write.
	front := nekoTestFront(t, []byte("SSH-2.0-X\r\nSERVER"))
	helper := nekoTestHelper(t, front)
	conn, code := nekoSocksConnect(t, helper, nekoIPv4Request(front))
	if code != nekoSocksOK {
		t.Fatalf("reply %#x", code)
	}
	rest := make([]byte, 6)
	if _, err := io.ReadFull(conn, rest); err != nil || string(rest) != "SERVER" {
		t.Fatalf("rest %q %v", rest, err)
	}
}

func TestHelperRefusesAServerTheProfileDoesNotMark(t *testing.T) {
	front := nekoTestFront(t, []byte("SSH-2.0-X\r\n"))
	helper := nekoTestHelper(t, "203.0.113.20:2443")
	if _, code := nekoSocksConnect(t, helper, nekoIPv4Request(front)); code != nekoSocksNotAllowed {
		t.Fatalf("reply %#x", code)
	}
}

func TestHelperTakesANameTheProfileMarks(t *testing.T) {
	front := nekoTestFront(t, []byte("SSH-2.0-X\r\n"))
	_, portText, _ := net.SplitHostPort(front)
	port, _ := strconv.Atoi(portText)
	helper := nekoTestHelper(t, "localhost:"+portText)
	if _, code := nekoSocksConnect(t, helper, nekoDomainRequest("LocalHost", port)); code != nekoSocksOK {
		t.Fatalf("reply %#x", code)
	}
}

func TestHelperFailsWithoutALine(t *testing.T) {
	for name, banner := range map[string][]byte{
		"too long":  bytes.Repeat([]byte("x"), nekoBannerMax+1),
		"no banner": nil,
	} {
		t.Run(name, func(t *testing.T) {
			var front string
			if banner == nil {
				listener, err := net.Listen("tcp", "127.0.0.1:0")
				if err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() { listener.Close() })
				go func() {
					for {
						conn, err := listener.Accept()
						if err != nil {
							return
						}
						conn.Close()
					}
				}()
				front = listener.Addr().String()
			} else {
				front = nekoTestFront(t, banner)
			}
			helper := nekoTestHelper(t, front)
			if _, code := nekoSocksConnect(t, helper, nekoIPv4Request(front)); code != nekoSocksRefused {
				t.Fatalf("reply %#x", code)
			}
		})
	}
}

func TestHelperAnswersOnlyConnect(t *testing.T) {
	front := nekoTestFront(t, []byte("SSH-2.0-X\r\n"))
	helper := nekoTestHelper(t, front)
	request := nekoIPv4Request(front)
	request[1] = 3 // UDP ASSOCIATE
	if _, code := nekoSocksConnect(t, helper, request); code != nekoSocksNoCommand {
		t.Fatalf("reply %#x", code)
	}
}

func TestHelperRefusesADeadServer(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	dead := listener.Addr().String()
	listener.Close()
	helper := nekoTestHelper(t, dead)
	if _, code := nekoSocksConnect(t, helper, nekoIPv4Request(dead)); code != nekoSocksRefused {
		t.Fatalf("reply %#x", code)
	}
}
