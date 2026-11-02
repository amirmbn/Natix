//go:build unix

package tunnel

import (
	"os"
	"syscall"
)

// LockDir holds the per-tunnel lock files shared with natix-kernel.
var LockDir = "/run"

// lockTunnel takes /run/natix-<name>.lock, the lock natix-kernel holds
// while it brings the tunnel up or down.
func lockTunnel(name string) (func(), error) {
	f, err := os.OpenFile(LockDir+"/natix-"+name+".lock", os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, err
	}
	// Never wait behind an up/down in progress: the caller retries later.
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = f.Close()
		if err == syscall.EWOULDBLOCK {
			return nil, errBusy
		}
		return nil, err
	}
	return func() { _ = f.Close() }, nil
}
