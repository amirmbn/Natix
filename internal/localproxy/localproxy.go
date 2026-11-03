package localproxy

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"path/filepath"

	"log"
	"os"

	"natix/internal/socks"
)

type Kind string

const (
	SOCKS5 Kind = "socks5"
	HTTP   Kind = "http"
)

type Config struct {
	Enabled bool `json:"enabled"`
	Type Kind `json:"type"`
	Port int `json:"port"`
	Username string `json:"username,omitempty"`
	Password string `json:"password,omitempty"`
}

var Dir = "/etc/natix"

func path() string { return filepath.Join(Dir, "proxy.json") }

func Load() Config {
	var c Config
	if b, err := os.ReadFile(path()); err == nil {
		if err := json.Unmarshal(b, &c); err != nil {
			log.Printf("%s is corrupt, proxy stays off: %v", path(), err)
			c = Config{}
		}
	}
	if c.Type == "" {
		c.Type = SOCKS5
	}
	return c
}

func Save(c Config) error {
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(Dir, 0o700); err != nil {
		return err
	}
	tmp := path() + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path())
}

func (c Config) authFunc() socks.AuthFunc {
	if c.Username == "" && c.Password == "" {
		return nil
	}
	return func(u, p string) bool {
		user := subtle.ConstantTimeCompare([]byte(u), []byte(c.Username))
		pass := subtle.ConstantTimeCompare([]byte(p), []byte(c.Password))
		return user&pass == 1
	}
}

func (c Config) Addr() string { return fmt.Sprintf("127.0.0.1:%d", c.Port) }

func Run(ctx context.Context) {
	c := Load()
	if !c.Enabled || c.Port <= 0 {
		<-ctx.Done()
		return
	}
	log.Printf("built-in %s proxy listening on %s", c.Type, c.Addr())

	switch c.Type {
	case HTTP:
		if err := serveHTTP(ctx, c.Addr(), c.authFunc()); err != nil {
			log.Printf("http proxy stopped: %v", err)
		}
	default: // socks5
		if err := socks.Serve(ctx, c.Addr(), c.authFunc()); err != nil {
			log.Printf("socks5 proxy stopped: %v", err)
		}
	}
}
