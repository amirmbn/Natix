package schedule

import (
	"errors"
	"fmt"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
)

const AutoRefreshMarker = "natix-auto-refresh"

const BinPath = "/usr/local/bin/natix"

func EffectiveHours(hours int) int {
	switch {
	case hours <= 0:
		return 0
	case hours <= 24:
		return hours
	default:
		return (hours / 24) * 24
	}
}

func HourlySpec(hours int) string {
	switch {
	case hours <= 0:
		return ""
	case hours == 1:
		return "0 * * * *"
	case hours < 24:
		return fmt.Sprintf("0 */%d * * *", hours)
	case hours == 24:
		return "0 0 * * *"
	default:
		days := hours / 24
		return fmt.Sprintf("0 0 */%d * *", days)
	}
}

func readCrontab() ([]string, error) {
	out, err := exec.Command("crontab", "-l").Output()
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) && noCrontabYet(ee.Stderr) {
			return nil, nil
		}
		return nil, fmt.Errorf("could not read the current crontab: %w", err)
	}
	var lines []string
	for _, l := range strings.Split(string(out), "\n") {
		if strings.TrimSpace(l) != "" {
			lines = append(lines, l)
		}
	}
	return lines, nil
}

func noCrontabYet(stderr []byte) bool {
	return strings.Contains(strings.ToLower(string(stderr)), "no crontab")
}

func writeCrontab(lines []string) error {
	cmd := exec.Command("crontab", "-")
	cmd.Stdin = strings.NewReader(strings.Join(lines, "\n") + "\n")
	return cmd.Run()
}

func SetCron(marker, spec, command string) error {
	current, err := readCrontab()
	if err != nil {
		return err
	}
	var kept []string
	for _, l := range current {
		if !strings.Contains(l, "# "+marker) {
			kept = append(kept, l)
		}
	}
	if spec != "" {
		kept = append(kept, fmt.Sprintf("%s %s # %s", spec, command, marker))
	}
	return writeCrontab(kept)
}

func RemoveCron(marker string) error {
	return SetCron(marker, "", "")
}

var intervalRe = regexp.MustCompile(`^0 \*/(\d+) \* \* \*`)

var dailyIntervalRe = regexp.MustCompile(`^0 0 \*/(\d+) \* \*`)

func GetIntervalHours(marker string) int {
	current, _ := readCrontab()
	for _, l := range current {
		if !strings.Contains(l, "# "+marker) {
			continue
		}
		return intervalFromLine(l)
	}
	return 0
}

func intervalFromLine(l string) int {
	switch {
	case strings.HasPrefix(l, "0 * * * *"):
		return 1
	case strings.HasPrefix(l, "0 0 * * *"):
		return 24
	}
	if m := intervalRe.FindStringSubmatch(l); m != nil {
		n, _ := strconv.Atoi(m[1])
		return n
	}
	if m := dailyIntervalRe.FindStringSubmatch(l); m != nil {
		n, _ := strconv.Atoi(m[1])
		return n * 24
	}
	return 0
}

func SetAutoRefresh(hours int) error {
	return SetCron(AutoRefreshMarker, HourlySpec(hours), BinPath+" restart-all")
}

func AutoRefreshHours() int {
	return GetIntervalHours(AutoRefreshMarker)
}
