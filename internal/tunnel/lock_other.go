//go:build !unix

package tunnel

var LockDir = ""

func lockTunnel(string) (func(), error) { return func() {}, nil }
