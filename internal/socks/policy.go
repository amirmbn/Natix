package socks

import (
	"errors"
	"net"
	"syscall"
	"time"
)

var Target = PublicOrPrivate

func PublicOrPrivate(ip net.IP) bool {
	return !(ip.IsLoopback() || ip.IsUnspecified() || ip.IsLinkLocalUnicast() ||
		ip.IsLinkLocalMulticast() || ip.IsInterfaceLocalMulticast() || ip.IsMulticast())
}

var ErrRefusedTarget = errors.New("socks: that destination is refused: it is this machine, or link-local")

func control(_, address string, _ syscall.RawConn) error {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return ErrRefusedTarget
	}
	if ip := net.ParseIP(host); ip == nil || !Target(ip) {
		return ErrRefusedTarget
	}
	return nil
}

func DialTarget(network, addr string, timeout time.Duration) (net.Conn, error) {
	d := net.Dialer{Timeout: timeout, Control: control}
	return d.Dial(network, addr)
}
