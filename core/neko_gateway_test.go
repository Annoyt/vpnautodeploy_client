package core

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
)

const nekoGatewayProfile = `
proxies:
  - {name: reality, type: vless, server: 203.0.113.20, port: 443, uuid: 0f9e8d7c-6b5a-4f3e-8d2c-1b0a9f8e7d6c}
  - {name: relay, type: socks5, server: 203.0.113.30, port: 1080}
  - {name: chained, type: socks5, server: 203.0.113.31, port: 1080, dialer-proxy: relay}
  - {name: local, type: direct}
proxy-groups:
  - {name: VPN, type: select, proxies: [reality, DIRECT]}
proxy-providers:
  emergency: {type: http, url: "https://example.com/e", proxy: DIRECT, override: {additional-prefix: "[E] "}}
  mine: {type: http, url: "https://example.com/m", proxy: VPN}
rule-providers:
  ru-direct: {type: http, behavior: domain, url: "https://example.com/r"}
rules:
  - GEOIP,RU,DIRECT,no-resolve
  - AND,((DOMAIN,a.ru),(NETWORK,UDP)),DIRECT
  - DOMAIN-SUFFIX,youtube.com,VPN
  - MATCH,DIRECT
sub-rules:
  calls: [NETWORK,UDP,DIRECT]
dns:
  nameserver: [77.88.8.8, "https://1.1.1.1/dns-query#VPN", system]
  proxy-server-nameserver: ["https://1.1.1.1/dns-query", "dhcp://en0"]
  nameserver-policy:
    "+.ru": 77.88.8.8
    "+.su": [77.88.8.1, "tls://8.8.8.8#h3=true"]
`

func nekoRaw(t *testing.T, yaml string) *config.RawConfig {
	t.Helper()
	raw, err := config.UnmarshalRawConfig([]byte(yaml))
	if err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	return raw
}

func nekoProxy(raw *config.RawConfig, name string) map[string]any {
	for _, proxy := range raw.Proxy {
		if proxy["name"] == name {
			return proxy
		}
	}
	return nil
}

var nekoJoinOne = &nekoGatewayJoin{
	Hosts: []string{"192.168.43.1"}, Port: 7891, Username: "u", Password: "p",
}

func TestNekoGatewayShareOpensOnePasswordListener(t *testing.T) {
	raw := nekoRaw(t, "listeners:\n  - {name: neko-gateway, type: socks, port: 1}\n  - {name: other, type: socks, port: 2}\n")

	patchNekoGateway(raw, nekoGateway{Share: &nekoGatewayShare{Port: 7891, Username: "u", Password: "p"}})

	if len(raw.Listeners) != 2 || raw.Listeners[0]["name"] != "other" {
		t.Fatalf("listeners = %v, want the other one kept and one gateway", raw.Listeners)
	}
	got := raw.Listeners[1]
	want := map[string]any{
		"name": "neko-gateway", "type": "mixed", "listen": "0.0.0.0", "port": 7891,
		"udp": true, "proxy": "DIRECT",
		"users": []any{map[string]any{"username": "u", "password": "p"}},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("gateway listener = %v, want %v", got, want)
	}
}

func TestNekoGatewayJoinDialsEveryServerThroughIt(t *testing.T) {
	raw := nekoRaw(t, nekoGatewayProfile)

	patchNekoGateway(raw, nekoGateway{Join: nekoJoinOne})

	if got := nekoProxy(raw, "reality")["dialer-proxy"]; got != "neko-gateway" {
		t.Errorf("reality dialer-proxy = %v, want the gateway", got)
	}
	if got := nekoProxy(raw, "chained")["dialer-proxy"]; got != "relay" {
		t.Errorf("a chain keeps its first hop: dialer-proxy = %v, want relay", got)
	}
	if _, set := nekoProxy(raw, "local")["dialer-proxy"]; set {
		t.Error("a direct-type proxy opens nothing and gets no dialer-proxy")
	}
	gateway := nekoProxy(raw, "neko-gateway")
	want := map[string]any{
		"name": "neko-gateway", "type": "socks5", "server": "192.168.43.1",
		"port": 7891, "username": "u", "password": "p", "udp": true,
	}
	if !reflect.DeepEqual(gateway, want) {
		t.Errorf("gateway proxy = %v, want %v", gateway, want)
	}
	if _, set := gateway["dialer-proxy"]; set {
		t.Error("the gateway itself is dialed on the local network")
	}
}

func TestNekoGatewayJoinSendsDirectTrafficThroughIt(t *testing.T) {
	raw := nekoRaw(t, nekoGatewayProfile)

	patchNekoGateway(raw, nekoGateway{Join: nekoJoinOne})

	wantRules := []string{
		"GEOIP,RU,neko-gateway,no-resolve",
		"AND,((DOMAIN,a.ru),(NETWORK,UDP)),neko-gateway",
		"DOMAIN-SUFFIX,youtube.com,VPN",
		"MATCH,neko-gateway",
	}
	if !reflect.DeepEqual(raw.Rule, wantRules) {
		t.Errorf("rules = %v, want %v", raw.Rule, wantRules)
	}
	if got := raw.SubRules["calls"]; !reflect.DeepEqual(got, []string{"NETWORK,UDP,neko-gateway"}) {
		t.Errorf("sub-rules = %v", got)
	}
	if got := raw.ProxyGroup[0]["proxies"]; !reflect.DeepEqual(got, []any{"reality", "neko-gateway"}) {
		t.Errorf("group members = %v, want DIRECT replaced", got)
	}
}

func TestNekoGatewayJoinCarriesProvidersAndDns(t *testing.T) {
	raw := nekoRaw(t, nekoGatewayProfile)

	patchNekoGateway(raw, nekoGateway{Join: nekoJoinOne})

	emergency := raw.ProxyProvider["emergency"]
	if emergency["proxy"] != "neko-gateway" {
		t.Errorf("a DIRECT download goes through the gateway: proxy = %v", emergency["proxy"])
	}
	wantOverride := map[string]any{"additional-prefix": "[E] ", "dialer-proxy": "neko-gateway"}
	if !reflect.DeepEqual(emergency["override"], wantOverride) {
		t.Errorf("override = %v, want %v", emergency["override"], wantOverride)
	}
	if got := raw.ProxyProvider["mine"]["proxy"]; got != "VPN" {
		t.Errorf("a provider naming its own proxy keeps it: proxy = %v", got)
	}
	if got := raw.RuleProvider["ru-direct"]["proxy"]; got != "neko-gateway" {
		t.Errorf("rule provider proxy = %v", got)
	}
	wantNS := []string{"77.88.8.8#neko-gateway", "https://1.1.1.1/dns-query#VPN", "system"}
	if !reflect.DeepEqual(raw.DNS.NameServer, wantNS) {
		t.Errorf("nameserver = %v, want %v", raw.DNS.NameServer, wantNS)
	}
	wantPS := []string{"https://1.1.1.1/dns-query#neko-gateway", "dhcp://en0"}
	if !reflect.DeepEqual(raw.DNS.ProxyServerNameserver, wantPS) {
		t.Errorf("proxy-server-nameserver = %v, want %v", raw.DNS.ProxyServerNameserver, wantPS)
	}
	if got := raw.DNS.NameServerPolicy.Value("+.ru"); got != "77.88.8.8#neko-gateway" {
		t.Errorf("policy +.ru = %v", got)
	}
	wantSu := []any{"77.88.8.1#neko-gateway", "tls://8.8.8.8#h3=true"}
	if got := raw.DNS.NameServerPolicy.Value("+.su"); !reflect.DeepEqual(got, wantSu) {
		t.Errorf("policy +.su = %v, want %v", got, wantSu)
	}
}

func TestNekoGatewayJoinWithSeveralAddressesTakesTheFirstThatAnswers(t *testing.T) {
	raw := nekoRaw(t, nekoGatewayProfile)
	join := &nekoGatewayJoin{
		Hosts: []string{"10.0.0.1", "not an address", "192.168.1.5"},
		Port:  7891, Username: "u", Password: "p",
	}

	patchNekoGateway(raw, nekoGateway{Join: join})

	if nekoProxy(raw, "neko-gateway-1")["server"] != "10.0.0.1" ||
		nekoProxy(raw, "neko-gateway-2")["server"] != "192.168.1.5" {
		t.Fatalf("one socks5 per address, hostnames dropped: %v", raw.Proxy)
	}
	group := raw.ProxyGroup[len(raw.ProxyGroup)-1]
	if group["name"] != "neko-gateway" || group["type"] != "fallback" ||
		!reflect.DeepEqual(group["proxies"], []string{"neko-gateway-1", "neko-gateway-2"}) {
		t.Errorf("gateway group = %v", group)
	}
}

func TestNekoGatewayJoinWinsOverShare(t *testing.T) {
	raw := nekoRaw(t, nekoGatewayProfile)

	patchNekoGateway(raw, nekoGateway{
		Share: &nekoGatewayShare{Port: 7891, Username: "u", Password: "p"},
		Join:  nekoJoinOne,
	})

	if len(raw.Listeners) != 0 {
		t.Errorf("listeners = %v, want none while joined", raw.Listeners)
	}
	if nekoProxy(raw, "neko-gateway") == nil {
		t.Error("the join was not applied")
	}
}

func TestNekoGatewayIncompleteChangesNothing(t *testing.T) {
	for name, gateway := range map[string]nekoGateway{
		"none":         {},
		"share port":   {Share: &nekoGatewayShare{Port: 70000, Username: "u", Password: "p"}},
		"share secret": {Share: &nekoGatewayShare{Port: 7891, Username: "u"}},
		"join hosts":   {Join: &nekoGatewayJoin{Hosts: []string{"gateway.local"}, Port: 7891, Username: "u", Password: "p"}},
		"join port":    {Join: &nekoGatewayJoin{Hosts: []string{"10.0.0.1"}, Username: "u", Password: "p"}},
	} {
		raw := nekoRaw(t, nekoGatewayProfile)
		before := nekoRaw(t, nekoGatewayProfile)
		patchNekoGateway(raw, gateway)
		if !reflect.DeepEqual(raw.Proxy, before.Proxy) || !reflect.DeepEqual(raw.Rule, before.Rule) ||
			!reflect.DeepEqual(raw.DNS.NameServer, before.DNS.NameServer) || len(raw.Listeners) != 0 {
			t.Errorf("%s: the config changed", name)
		}
	}
}

func nekoGatewayHome(t *testing.T, gateway any) string {
	t.Helper()
	home := t.TempDir()
	previous := constant.Path.HomeDir()
	constant.SetHomeDir(home)
	t.Cleanup(func() { constant.SetHomeDir(previous) })
	if gateway != nil {
		buf, _ := json.Marshal(gateway)
		if err := os.WriteFile(filepath.Join(home, nekoGatewayFile), buf, 0o600); err != nil {
			t.Fatalf("write gateway: %v", err)
		}
	}
	return home
}

func TestReadNekoGatewayToleratesAMissingOrBrokenFile(t *testing.T) {
	nekoGatewayHome(t, nil)
	if got := readNekoGateway(); got.Share != nil || got.Join != nil {
		t.Errorf("no file: %+v", got)
	}
	home := nekoGatewayHome(t, nil)
	if err := os.WriteFile(filepath.Join(home, nekoGatewayFile), []byte("{not json"), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := readNekoGateway(); got.Share != nil || got.Join != nil {
		t.Errorf("broken file: %+v", got)
	}
}

func TestLoadSetupConfigOpensTheGatewayListener(t *testing.T) {
	home := nekoGatewayHome(t, map[string]any{
		"share": map[string]any{"port": 17891, "username": "u", "password": "p"},
	})
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), []byte("rules:\n  - MATCH,DIRECT\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg, err := loadSetupConfig(defaultSetupParams())

	if err != nil {
		t.Fatalf("loadSetupConfig = %v", err)
	}
	if cfg.Listeners["neko-gateway"] == nil {
		t.Errorf("listeners = %v, want the gateway", cfg.Listeners)
	}
}

func TestLoadSetupConfigJoinsTheGateway(t *testing.T) {
	home := nekoGatewayHome(t, map[string]any{
		"join": map[string]any{"hosts": []string{"192.168.43.1"}, "port": 7891, "username": "u", "password": "p"},
	})
	profile := "proxies:\n  - {name: a, type: socks5, server: 203.0.113.30, port: 1080}\nrules:\n  - MATCH,DIRECT\n"
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), []byte(profile), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg, err := loadSetupConfig(defaultSetupParams())

	if err != nil {
		t.Fatalf("loadSetupConfig = %v", err)
	}
	if cfg.Proxies["neko-gateway"] == nil {
		t.Error("the gateway proxy is missing")
	}
	if got := ruleStrings(cfg); !reflect.DeepEqual(got, []string{"Match,,neko-gateway"}) {
		t.Errorf("rules = %v, want MATCH through the gateway", got)
	}
}
