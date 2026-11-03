package cli

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"

	"natix/internal/version"
)

const (
	Reset = "\033[0m"
	Bold  = "\033[1m"
	Red   = "\033[36m"
	White = "\033[97m"
	Gray  = "\033[90m"
	Green = "\033[32m"
	Amber = "\033[33m"
	ErrC  = "\033[31m"

	RuleWidth = 58
)

var reader = bufio.NewReader(os.Stdin)

func Clear() {
	fmt.Print("\033[2J\033[H")
}

func Logo() {
	banner := `
    _   __      __  _     
   / | / /___ _/ /_(_)  __
  /  |/ / __ '/ __/ / |/_/
 / /|  / /_/ / /_/ />  <  
/_/ |_/\__,_/\__/_/_/|_|  `
	fmt.Printf("%s%s%s%s\n", Bold, Red, banner, Reset)
	fmt.Printf("  %sNatix Network Engine v%s%s %s| Multi-Protocol Tunnel & Route Analyzer%s\n", Bold+White, version.Version, Reset, Gray, Reset)
	fmt.Printf("  %sRepository: %s%s\n\n", Gray, version.RepoURL, Reset)
}

func Rule() {
	fmt.Printf(" %s%s%s\n", Gray, strings.Repeat("-", RuleWidth), Reset)
}

func Header() {
	Clear()
	Logo()
	Rule()
	fmt.Println()
}

func Title(text string) {
	fmt.Printf("\n %s%s>> %s%s\n", Bold, Red, strings.ToUpper(text), Reset)
	Rule()
	fmt.Println()
}

func Opt(n, title, desc string) {
	optW(n, title, desc, 20)
}

func optW(n, title, desc string, width int) {
	if desc != "" {
		fmt.Printf("  %s[%2s]%s %s%-*s%s  %s%s%s\n",
			Red, n, Reset,
			Bold+White, width, title, Reset,
			Gray, desc, Reset)
	} else {
		fmt.Printf("  %s[%2s]%s %s%s%s\n",
			Red, n, Reset,
			Bold+White, title, Reset)
	}
}

type MenuOpt struct {
	Title string
	Desc  string
}

func ChooseOpt(title string, opts []MenuOpt) int {
	Title(title)
	w := 20
	for _, o := range opts {
		if len(o.Title) > w {
			w = len(o.Title)
		}
	}
	for i, o := range opts {
		optW(strconv.Itoa(i+1), o.Title, o.Desc, w)
	}
	fmt.Println()
	Rule()
	raw := Ask("Select option (0 to return)", "0")
	n, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil || n < 1 || n > len(opts) {
		return 0
	}
	return n
}

func KV(key, val string) {
	fmt.Printf("   %s%-18s%s %s%s%s\n", Gray, key+":", Reset, Bold+White, val, Reset)
}

func Ok(msg string) {
	fmt.Printf(" %s%s[OK]%s %s\n", Bold, Green, Reset, msg)
}

func Warn(msg string) {
	fmt.Printf(" %s%s[!]%s  %s\n", Bold, Amber, Reset, msg)
}

func Err(msg string) {
	fmt.Printf(" %s%s[X]  %s%s\n", Bold, ErrC, msg, Reset)
}

func Info(msg string) {
	fmt.Printf(" %s[*]%s  %s\n", Red, Reset, msg)
}

func Subtle(msg string) {
	fmt.Printf("   %s%s%s\n", Gray, msg, Reset)
}

func Step(n, total int, msg string) {
	fmt.Printf("\n %s[%d/%d]%s %s%s%s\n", Red, n, total, Reset, Bold+White, msg, Reset)
}

func Pause() {
	fmt.Printf("\n %sPress Enter to return...%s", Gray, Reset)
	_, _ = reader.ReadString('\n')
}

func Ask(prompt, def string) string {
	if def != "" {
		fmt.Printf(" %s%s%s %s(%s)%s: ", Bold+White, prompt, Reset, Gray, def, Reset)
	} else {
		fmt.Printf(" %s%s%s: ", Bold+White, prompt, Reset)
	}
	line, err := reader.ReadString('\n')
	if err != nil {
		return def
	}
	line = strings.TrimSpace(line)
	if line == "" {
		return def
	}
	return line
}

func Confirm(prompt string, defYes bool) bool {
	hint := "y/N"
	if defYes {
		hint = "Y/n"
	}
	fmt.Printf(" %s%s%s %s[%s]%s: ", Bold+White, prompt, Reset, Gray, hint, Reset)
	line, err := reader.ReadString('\n')
	if err != nil {
		return defYes
	}
	line = strings.ToLower(strings.TrimSpace(line))
	if line == "" {
		return defYes
	}
	return line == "y" || line == "yes"
}
