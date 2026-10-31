// NekoVPN (Annoyt/vpnautodeploy_client), client plan E30: the gateway.
// A phone shares its network with a neighbour that has none (docs/
// MULTIPATH.md 3.2). The sharing phone opens a listener on the local
// network with a password ("share"). The neighbour's core dials every
// server, its DNS and its direct traffic through it ("join"). The
// neighbour's tunnel stays its own: the sharing phone carries encrypted
// connections to our servers, plus the neighbour's direct traffic (Russian
// sites), and sees none of the tunnel's content.
//
// The app writes the state to nekoGatewayFile in the home directory and
// applies the profile again; the core patches the raw config at load time,
// for a plain profile and for one with a base alike.

package core

import (
	"encoding/json"
	"fmt"
	"net/netip"
	"os"
	"path/filepath"
	"strings"

	"github.com/metacubex/mihomo/common/orderedmap"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
)

const (
	nekoGatewayFile = "neko_gateway.json"
	nekoGatewayName = "neko-gateway"
)

type nekoGatewayShare struct {
	Port     int    `json:"port"`
	Username string `json:"username"`
	Password string `json:"password"`
}

type nekoGatewayJoin struct {
	Hosts    []string `json:"hosts"`
	Port     int      `json:"port"`
	Username string   `json:"username"`
	Password string   `json:"password"`
}

type nekoGateway struct {
	Share *nekoGatewayShare `json:"share"`
	Join  *nekoGatewayJoin  `json:"join"`
}

// readNekoGateway returns the app's choice; no file, or one it cannot
// read, is no gateway at all.
func readNekoGateway() nekoGateway {
	buf, err := os.ReadFile(filepath.Join(constant.Path.HomeDir(), nekoGatewayFile))
	if err != nil {
		return nekoGateway{}
	}
	var gateway nekoGateway
	if json.Unmarshal(buf, &gateway) != nil {
		return nekoGateway{}
	}
	return gateway
}

func nekoValidPort(port int) bool {
	return port > 0 && port < 65536
}

func (share *nekoGatewayShare) valid() bool {
	return share != nil && nekoValidPort(share.Port) &&
		share.Username != "" && share.Password != ""
}

// hosts returns the addresses that parse; a hostname is not taken, the
// sharing phone is always reached by its address on the local network.
func (join *nekoGatewayJoin) hosts() []string {
	var hosts []string
	for _, host := range join.Hosts {
		if address, err := netip.ParseAddr(strings.TrimSpace(host)); err == nil {
			hosts = append(hosts, address.String())
		}
	}
	return hosts
}

func (join *nekoGatewayJoin) valid() bool {
	return join != nil && nekoValidPort(join.Port) &&
		join.Username != "" && join.Password != "" && len(join.hosts()) > 0
}

// patchNekoGateway applies the app's choice to a raw config. A phone that
// joins a gateway does not share one: joining wins.
func patchNekoGateway(raw *config.RawConfig, gateway nekoGateway) {
	switch {
	case gateway.Join.valid():
		joinNekoGateway(raw, gateway.Join)
	case gateway.Share.valid():
		shareNekoGateway(raw, gateway.Share)
	}
}

// shareNekoGateway opens the listener: every connection a neighbour makes
// with the password leaves this phone directly, through its own network.
func shareNekoGateway(raw *config.RawConfig, share *nekoGatewayShare) {
	listeners := make([]map[string]any, 0, len(raw.Listeners)+1)
	for _, listener := range raw.Listeners {
		if listener["name"] != nekoGatewayName {
			listeners = append(listeners, listener)
		}
	}
	raw.Listeners = append(listeners, map[string]any{
		"name":   nekoGatewayName,
		"type":   "mixed",
		"listen": "0.0.0.0",
		"port":   share.Port,
		"udp":    true,
		// The shape YAML gives the decoder.
		"users": []any{
			map[string]any{"username": share.Username, "password": share.Password},
		},
		"proxy": "DIRECT",
	})
}

// Proxy types that open no connection of their own.
var nekoLocalProxyTypes = map[string]bool{
	"direct": true, "reject": true, "reject-drop": true, "pass": true,
	"compatible": true, "dns": true,
}

func nekoGatewayProxies(join *nekoGatewayJoin) (proxies []map[string]any, group map[string]any) {
	hosts := join.hosts()
	names := make([]string, 0, len(hosts))
	for i, host := range hosts {
		name := nekoGatewayName
		if len(hosts) > 1 {
			name = fmt.Sprintf("%s-%d", nekoGatewayName, i+1)
		}
		names = append(names, name)
		proxies = append(proxies, map[string]any{
			"name":     name,
			"type":     "socks5",
			"server":   host,
			"port":     join.Port,
			"username": join.Username,
			"password": join.Password,
			"udp":      true,
		})
	}
	if len(hosts) > 1 {
		// The sharing phone may be on several networks (its hotspot and a
		// Wi-Fi): the first address that answers.
		group = map[string]any{
			"name":     nekoGatewayName,
			"type":     "fallback",
			"proxies":  names,
			"interval": 120,
		}
	}
	return proxies, group
}

// joinNekoGateway sends everything this phone would send itself through
// the gateway: each server is dialed through it, and so are the direct
// rules, DNS and the providers' downloads.
func joinNekoGateway(raw *config.RawConfig, join *nekoGatewayJoin) {
	for _, proxy := range raw.Proxy {
		kind, _ := proxy["type"].(string)
		if nekoLocalProxyTypes[strings.ToLower(kind)] {
			continue
		}
		// A chain is dialed from its first hop, which gets the gateway.
		if _, chained := proxy["dialer-proxy"]; !chained {
			proxy["dialer-proxy"] = nekoGatewayName
		}
	}
	proxies, group := nekoGatewayProxies(join)
	raw.Proxy = append(raw.Proxy, proxies...)

	for _, proxyGroup := range raw.ProxyGroup {
		if members, ok := proxyGroup["proxies"].([]any); ok {
			for i, member := range members {
				if name, ok := member.(string); ok && strings.EqualFold(name, "DIRECT") {
					members[i] = nekoGatewayName
				}
			}
		}
	}
	if group != nil {
		raw.ProxyGroup = append(raw.ProxyGroup, group)
	}

	for _, provider := range raw.ProxyProvider {
		override, _ := provider["override"].(map[string]any)
		if override == nil {
			override = map[string]any{}
		}
		if _, chained := override["dialer-proxy"]; !chained {
			override["dialer-proxy"] = nekoGatewayName
		}
		provider["override"] = override
		nekoGatewayDownload(provider)
	}
	for _, provider := range raw.RuleProvider {
		nekoGatewayDownload(provider)
	}

	for i, rule := range raw.Rule {
		raw.Rule[i] = nekoGatewayRule(rule)
	}
	for name, rules := range raw.SubRules {
		for i, rule := range rules {
			rules[i] = nekoGatewayRule(rule)
		}
		raw.SubRules[name] = rules
	}

	dns := &raw.DNS
	dns.NameServer = nekoGatewayResolvers(dns.NameServer)
	dns.Fallback = nekoGatewayResolvers(dns.Fallback)
	dns.ProxyServerNameserver = nekoGatewayResolvers(dns.ProxyServerNameserver)
	dns.DirectNameServer = nekoGatewayResolvers(dns.DirectNameServer)
	nekoGatewayPolicy(dns.NameServerPolicy)
	nekoGatewayPolicy(dns.ProxyServerNameserverPolicy)
}

// A provider downloads through the gateway unless it names a proxy of its
// own; ours name DIRECT, which this phone does not have.
func nekoGatewayDownload(provider map[string]any) {
	via, _ := provider["proxy"].(string)
	if via == "" || strings.EqualFold(via, "DIRECT") {
		provider["proxy"] = nekoGatewayName
	}
}

// nekoGatewayRule turns a rule whose target is DIRECT into one through the
// gateway. A rule is TYPE,PAYLOAD,TARGET[,OPTIONS] or MATCH,TARGET; a
// logical rule's payload is in brackets and holds commas of its own.
func nekoGatewayRule(rule string) string {
	fields := nekoSplitRule(rule)
	target := 2
	if len(fields) > 0 && strings.EqualFold(strings.TrimSpace(fields[0]), "MATCH") {
		target = 1
	}
	if target >= len(fields) || !strings.EqualFold(strings.TrimSpace(fields[target]), "DIRECT") {
		return rule
	}
	fields[target] = nekoGatewayName
	return strings.Join(fields, ",")
}

func nekoSplitRule(rule string) []string {
	var fields []string
	depth, start := 0, 0
	for i, char := range rule {
		switch char {
		case '(':
			depth++
		case ')':
			depth--
		case ',':
			if depth == 0 {
				fields = append(fields, rule[start:i])
				start = i + 1
			}
		}
	}
	return append(fields, rule[start:])
}

// A resolver is asked through the gateway unless it already names a proxy
// (or other options) after '#', or is the system's own.
func nekoGatewayResolver(server string) string {
	trimmed := strings.TrimSpace(server)
	if trimmed == "" || strings.Contains(trimmed, "#") ||
		trimmed == "system" || strings.HasPrefix(trimmed, "system://") ||
		strings.HasPrefix(trimmed, "dhcp://") || strings.HasPrefix(trimmed, "rcode://") {
		return server
	}
	return trimmed + "#" + nekoGatewayName
}

func nekoGatewayResolvers(servers []string) []string {
	for i, server := range servers {
		servers[i] = nekoGatewayResolver(server)
	}
	return servers
}

func nekoGatewayPolicy(policy *orderedmap.OrderedMap[string, any]) {
	if policy == nil {
		return
	}
	for pair := policy.Oldest(); pair != nil; pair = pair.Next() {
		switch value := pair.Value.(type) {
		case string:
			pair.Value = nekoGatewayResolver(value)
		case []any:
			for i, server := range value {
				if name, ok := server.(string); ok {
					value[i] = nekoGatewayResolver(name)
				}
			}
		case []string:
			pair.Value = nekoGatewayResolvers(value)
		}
	}
}
