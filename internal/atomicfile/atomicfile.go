package atomicfile

import (
	"os"
	"runtime"
	"time"
)

func Replace(src, dst string) error {
	if runtime.GOOS != "windows" {
		return os.Rename(src, dst)
	}
	var err error
	for i := 0; i < 100; i++ {
		if err = os.Rename(src, dst); err == nil {
			return nil
		}
		time.Sleep(10 * time.Millisecond)
	}
	return err
}
