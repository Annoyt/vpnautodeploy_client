// NekoVPN (Annoyt/vpnautodeploy_client), client plan E37: the core's own
// sockets spread over several networks at once, e.g. Wi-Fi from a second
// phone's hotspot plus this phone's mobile data (docs/MULTIPATH.md, 3.1).
// The Android service reports the networks (NekoNetworksModule); the socket
// hook binds each new socket to the network chosen here.

package core

import (
	"encoding/json"
	"net"
	"net/netip"
	"sort"
	"sync"
	"sync/atomic"
)

const (
	nekoModeOff        = "off"
	nekoModeFailover   = "failover"
	nekoModeDistribute = "distribute"
)

type nekoNetwork struct {
	Handle    uint64 `json:"handle"`
	Transport string `json:"transport"`
	Validated bool   `json:"validated"`
}

type nekoNetworks struct {
	Mode     string        `json:"mode"`
	Networks []nekoNetwork `json:"networks"`
}

var (
	nekoNetworksMu   sync.RWMutex
	nekoNetworksNow  = nekoNetworks{Mode: nekoModeOff}
	nekoNetworksNext atomic.Uint64
)

// The order networks are preferred in, the same as the service's
// NetworkObserver: Wi-Fi, Ethernet, USB, then mobile data.
var nekoTransportRank = map[string]int{
	"wifi": 0, "ethernet": 1, "usb": 2, "bluetooth": 3, "cellular": 4,
}

func nekoRank(transport string) int {
	if rank, ok := nekoTransportRank[transport]; ok {
		return rank
	}
	return 20
}

// NekoUpdateNetworks takes the service's report: the mode and the networks
// with their handles. An unreadable report switches the binding off.
func NekoUpdateNetworks(value string) {
	next := nekoNetworks{Mode: nekoModeOff}
	if err := json.Unmarshal([]byte(value), &next); err != nil {
		next = nekoNetworks{Mode: nekoModeOff}
	}
	if next.Mode != nekoModeFailover && next.Mode != nekoModeDistribute {
		next.Mode = nekoModeOff
	}
	sort.SliceStable(next.Networks, func(i, j int) bool {
		return nekoRank(next.Networks[i].Transport) < nekoRank(next.Networks[j].Transport)
	})
	nekoNetworksMu.Lock()
	nekoNetworksNow = next
	nekoNetworksMu.Unlock()
}

// nekoPickNetwork is the network handle a new socket to address should be
// bound to, or 0 to leave it on the system's default network.
//
// Never bound: DNS (port 53, the resolvers belong to one network), local
// and private addresses (a LAN, the hotspot's own gateway). Failover takes
// the first validated network in order of preference, so a Wi-Fi without
// internet stops carrying new connections at once. Distribute takes the
// validated networks in turn: one connection is on one network, many add up.
func nekoPickNetwork(state nekoNetworks, address string, turn uint64) uint64 {
	if state.Mode == nekoModeOff {
		return 0
	}
	if !nekoBindable(address) {
		return 0
	}
	usable := make([]nekoNetwork, 0, len(state.Networks))
	for _, network := range state.Networks {
		if network.Validated && network.Handle != 0 {
			usable = append(usable, network)
		}
	}
	if len(usable) == 0 {
		return 0
	}
	if state.Mode == nekoModeDistribute {
		return usable[turn%uint64(len(usable))].Handle
	}
	return usable[0].Handle
}

func nekoBindable(address string) bool {
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		// A listening UDP socket (":0") has no peer yet; it carries a
		// tunnel to a server, which is what may be spread.
		host, port = "", ""
	}
	if port == "53" {
		return false
	}
	ip, err := netip.ParseAddr(host)
	if err != nil {
		return true
	}
	ip = ip.Unmap()
	return !(ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() ||
		ip.IsLinkLocalMulticast() || ip.IsMulticast() || ip.IsUnspecified() ||
		nekoSharedAddressSpace.Contains(ip))
}

var nekoSharedAddressSpace = netip.MustParsePrefix("100.64.0.0/10")

// nekoBindSocket binds fd to the network nekoPickNetwork chooses. Called
// from the socket hook right after the socket is protected from the VPN.
func nekoBindSocket(address string, fd int) {
	nekoNetworksMu.RLock()
	state := nekoNetworksNow
	nekoNetworksMu.RUnlock()
	handle := nekoPickNetwork(state, address, nekoNetworksNext.Add(1)-1)
	if handle == 0 {
		return
	}
	_ = nekoSetSockNetwork(handle, fd)
}
