package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"natix/internal/catalog"
	"natix/internal/cli"
	"natix/internal/localproxy"
	"natix/internal/speedtest"
	"natix/internal/tunnel"
	"natix/internal/version"
)

func main() {
	if len(os.Args) < 2 {
		cli.RunInteractiveMenu()
		return
	}
	sub := strings.ToLower(strings.TrimSpace(os.Args[1]))
	rest := os.Args[2:]

	switch sub {
	case "menu", "ui":
		cli.RunInteractiveMenu()

	case "status", "list", "ls":
		cli.StatusTable()

	case "up", "restart", "down", "link":
		if len(rest) != 1 {
			log.Fatalf("usage: natix %s <tunnel-name>", sub)
		}
		execTunnelAction(sub, rest[0])

	case "apply-link", "import":
		if len(rest) != 1 {
			log.Fatal("usage: natix apply-link 'natix://...'")
		}
		importAndStartLink(rest[0])

	case "conntest", "probe":
		if len(rest) != 1 {
			log.Fatal("usage: natix conntest 'natix-test://...'")
		}
		if err := cli.RunConnTest(rest[0]); err != nil {
			log.Fatal(err)
		}

	case "conntest-server", "probe-server":
		bindIP := ""
		if len(rest) > 0 {
			bindIP = rest[0]
		}
		cli.ConnTestServer(bindIP)

	case "linktest", "bench":
		fs := flag.NewFlagSet("linktest", flag.ExitOnError)
		port := fs.Int("port", speedtest.DefaultSpeedPort, "responder TCP port")
		_ = fs.Parse(rest)
		if fs.NArg() != 1 {
			log.Fatal("usage: natix linktest [-port N] <target-ip>")
		}
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		target := net.JoinHostPort(fs.Arg(0), strconv.Itoa(*port))
		fmt.Print(speedtest.Format(speedtest.Run(ctx, target, 20)))

	case "speedtest-server", "bench-server":
		fs := flag.NewFlagSet("speedtest-server", flag.ExitOnError)
		port := fs.Int("port", speedtest.DefaultSpeedPort, "TCP listen port")
		_ = fs.Parse(rest)
		addr, _, err := speedtest.StartServer(fmt.Sprintf(":%d", *port))
		if err != nil {
			log.Fatal(err)
		}
		log.Printf("natix benchmark responder listening on %s", addr)
		select {}

	case "catalog", "methods":
		fmt.Printf("%-4s %-15s %-12s %s\n", "ID", "TRANSPORT", "LAYER", "DESCRIPTION")
		fmt.Println(strings.Repeat("-", 68))
		for _, m := range catalog.Methods {
			fmt.Printf("%2d   %-15s %-12s %s\n", m.ID, m.Name, m.Family, m.Title)
		}

	case "restart-all":
		okCount, failCount := cli.RestartAll()
		fmt.Printf("natix: restarted %d tunnel(s), %d failed\n", okCount, failCount)
		if failCount > 0 {
			os.Exit(1)
		}

	case "proxy-serve":
		ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
		defer cancel()
		localproxy.Run(ctx)

	case "optimize", "tune":
		if err := tunnel.Optimize(); err != nil {
			log.Fatal(err)
		}
		fmt.Println("natix: kernel network stack optimized (BBR + fq + socket buffers)")

	case "version", "-v", "--version":
		fmt.Printf("natix v%s\n", version.Version)

	default:
		printUsage()
	}
}

func printUsage() {
	fmt.Printf(`Natix v%s - Multi-Protocol Tunnel & Route Quality CLI

Usage:
  natix [command] [arguments]

Commands:
  (no command)                 Launch interactive terminal dashboard
  status | ls                  Show active tunnels, state, and traffic counters
  up | down | restart <name>   Control a specific tunnel service
  link <name>                  Export peer setup link (natix://) & RouterOS script
  apply-link 'natix://...'     Deploy and start peer tunnel from setup link
  conntest-server [ip]         Start Iran-side route & DPI probe listener
  conntest 'natix-test://...'  Run Kharej-side transport & throughput benchmark
  linktest [-port N] <host>    Measure RTT, packet loss, and 4-stream TCP speed
  speedtest-server [-port N]   Run standalone TCP benchmark responder (port 7711)
  restart-all                  Restart all configured tunnels
  proxy-serve                  Run local SOCKS5/HTTP exit proxy daemon
  optimize                     Apply BBR, fq, and high-BDP sysctl parameters
  catalog                      List all 28 supported kernel & encrypted transports
  version                      Display installed version
`, version.Version)
}

func execTunnelAction(action, name string) {
	st, err := catalog.LoadStore(cli.StoreDir)
	if err != nil {
		log.Fatal(err)
	}
	tc, ok := st.Find(name)
	if !ok {
		log.Fatalf("natix: tunnel %q does not exist", name)
	}
	switch action {
	case "up", "restart":
		err = tunnel.Apply(tc)
	case "down":
		_, err = tunnel.Run("systemctl", "stop", tunnel.Unit(tc))
	case "link":
		var link string
		link, err = catalog.EncodeSetupLink(tc)
		fmt.Println(link)
		if ros := tunnel.MikroTik(tc); ros != "" {
			fmt.Println("\n# MikroTik RouterOS 7 Peer Script:\n" + ros)
		}
	}
	if err != nil {
		log.Fatal(err)
	}
}

func importAndStartLink(rawLink string) {
	tc, err := catalog.DecodeSetupLink(rawLink)
	if err != nil {
		log.Fatal(err)
	}
	st, err := catalog.LoadStore(cli.StoreDir)
	if err != nil {
		log.Fatal(err)
	}
	if err := tunnel.Import(st, &tc); err != nil {
		log.Fatal(err)
	}
	if err := tunnel.Apply(tc); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("natix: tunnel %s (%s) active: %s <-> %s\n", tc.Name, tc.Method, tc.TunLocal4, tc.TunRemote4)
}
