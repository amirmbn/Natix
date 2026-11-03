//go:build !linux

package conntest

import "context"

func PathMTU(context.Context, Link) int { return 0 }
