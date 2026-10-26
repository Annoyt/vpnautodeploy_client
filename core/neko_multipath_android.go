//go:build android && cgo

package core

/*
#cgo LDFLAGS: -landroid
#include <android/multinetwork.h>
*/
import "C"

import "syscall"

// nekoSetSockNetwork binds fd to the Android network with this handle
// (Network.getNetworkHandle), API 23+.
func nekoSetSockNetwork(handle uint64, fd int) error {
	if C.android_setsocknetwork(C.net_handle_t(handle), C.int(fd)) != 0 {
		return syscall.EINVAL
	}
	return nil
}
