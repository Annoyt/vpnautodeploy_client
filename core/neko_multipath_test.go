package core

import "testing"

func nekoState(mode string, networks ...nekoNetwork) nekoNetworks {
	return nekoNetworks{Mode: mode, Networks: networks}
}

var (
	nekoWifi     = nekoNetwork{Handle: 11, Transport: "wifi", Validated: true}
	nekoCellular = nekoNetwork{Handle: 22, Transport: "cellular", Validated: true}
)

func TestNekoPickNetworkOffLeavesTheDefault(t *testing.T) {
	state := nekoState(nekoModeOff, nekoWifi, nekoCellular)
	if got := nekoPickNetwork(state, "203.0.113.20:443", 0); got != 0 {
		t.Fatalf("off: got %d, want 0", got)
	}
}

func TestNekoPickNetworkDistributesInTurn(t *testing.T) {
	state := nekoState(nekoModeDistribute, nekoWifi, nekoCellular)
	var got []uint64
	for turn := uint64(0); turn < 4; turn++ {
		got = append(got, nekoPickNetwork(state, "203.0.113.20:443", turn))
	}
	want := []uint64{11, 22, 11, 22}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("distribute: got %v, want %v", got, want)
		}
	}
}

func TestNekoPickNetworkFailoverSkipsANetworkWithoutInternet(t *testing.T) {
	broken := nekoNetwork{Handle: 11, Transport: "wifi", Validated: false}
	state := nekoState(nekoModeFailover, broken, nekoCellular)
	if got := nekoPickNetwork(state, "203.0.113.20:443", 5); got != 22 {
		t.Fatalf("failover: got %d, want the cellular 22", got)
	}
	healthy := nekoState(nekoModeFailover, nekoWifi, nekoCellular)
	if got := nekoPickNetwork(healthy, "203.0.113.20:443", 5); got != 11 {
		t.Fatalf("failover: got %d, want the wifi 11", got)
	}
}

func TestNekoPickNetworkNeverBindsDnsOrLocalAddresses(t *testing.T) {
	state := nekoState(nekoModeDistribute, nekoWifi, nekoCellular)
	for _, address := range []string{
		"8.8.8.8:53", "[2001:4860:4860::8888]:53", "192.168.43.1:443",
		"10.0.0.5:80", "127.0.0.1:7890", "169.254.1.1:80", "100.64.0.1:443",
		"[fe80::1]:443", "[::ffff:192.168.1.1]:443", "224.0.0.251:5353",
	} {
		if got := nekoPickNetwork(state, address, 1); got != 0 {
			t.Fatalf("%s: got %d, want 0", address, got)
		}
	}
	for _, address := range []string{"203.0.113.20:443", ":0", "example.com:443"} {
		if got := nekoPickNetwork(state, address, 1); got == 0 {
			t.Fatalf("%s: left on the default network", address)
		}
	}
}

func TestNekoPickNetworkWithoutUsableNetworks(t *testing.T) {
	none := nekoState(nekoModeDistribute, nekoNetwork{Handle: 11, Transport: "wifi"})
	if got := nekoPickNetwork(none, "203.0.113.20:443", 0); got != 0 {
		t.Fatalf("got %d, want 0", got)
	}
	zero := nekoState(nekoModeFailover, nekoNetwork{Transport: "wifi", Validated: true})
	if got := nekoPickNetwork(zero, "203.0.113.20:443", 0); got != 0 {
		t.Fatalf("a zero handle: got %d, want 0", got)
	}
}

func TestNekoUpdateNetworksOrdersAndValidates(t *testing.T) {
	defer NekoUpdateNetworks(`{"mode":"off"}`)
	NekoUpdateNetworks(`{"mode":"failover","networks":[` +
		`{"handle":22,"transport":"cellular","validated":true},` +
		`{"handle":33,"transport":"vpn-ish","validated":true},` +
		`{"handle":11,"transport":"wifi","validated":true}]}`)
	nekoNetworksMu.RLock()
	state := nekoNetworksNow
	nekoNetworksMu.RUnlock()
	if state.Mode != nekoModeFailover || len(state.Networks) != 3 {
		t.Fatalf("got %+v", state)
	}
	if state.Networks[0].Handle != 11 || state.Networks[2].Handle != 33 {
		t.Fatalf("not in order of preference: %+v", state.Networks)
	}
	for _, report := range []string{`{"mode":"turbo"}`, `not json`} {
		NekoUpdateNetworks(report)
		nekoNetworksMu.RLock()
		mode := nekoNetworksNow.Mode
		nekoNetworksMu.RUnlock()
		if mode != nekoModeOff {
			t.Fatalf("%s: mode %q, want off", report, mode)
		}
	}
}
