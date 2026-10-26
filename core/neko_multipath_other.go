//go:build !(android && cgo)

package core

import "errors"

// Binding a socket to a network is Android's; elsewhere sockets keep the
// system's choice.
func nekoSetSockNetwork(uint64, int) error {
	return errors.ErrUnsupported
}
