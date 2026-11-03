package cli

import (
	"fmt"

	"natix/internal/health"
)

func healthCheck() {
	Header()
	Title("Health Check")
	Warn("Checking The Server And Tunnels...")
	fmt.Println()

	checks := health.Run(StoreDir)
	okCount, warnCount, failCount := 0, 0, 0
	group := ""
	for _, c := range checks {
		switch c.Level {
		case health.OK:
			okCount++
		case health.Warn:
			warnCount++
		case health.Fail:
			failCount++
		}
		if c.Group != group {
			group = c.Group
			fmt.Println()
			fmt.Printf("  %s%s%s\n", Bold+White, group, Reset)
		}
		fmt.Printf("   %s %-22s %s%s%s\n", checkMark(c.Level), c.Name, Gray, c.Detail, Reset)
		if c.Fix != "" {
			fmt.Printf("       %s→ %s%s\n", Red, c.Fix, Reset)
		}
	}

	fmt.Println()
	Rule()
	summary := fmt.Sprintf("%d passed", okCount)
	if warnCount > 0 {
		summary += fmt.Sprintf(" · %d warning(s)", warnCount)
	}
	if failCount > 0 {
		summary += fmt.Sprintf(" · %d problem(s)", failCount)
	}
	switch {
	case failCount > 0:
		Err("Problems Found — " + summary)
		Warn("Fix The Red Items, Then Check Again.")
	case warnCount > 0:
		Info("Mostly Healthy — " + summary)
	default:
		Ok("Healthy — " + summary)
	}
	Pause()
}

func checkMark(l health.Level) string {
	switch l {
	case health.OK:
		return Bold + White + "✓" + Reset
	case health.Warn:
		return Gray + "!" + Reset
	case health.Fail:
		return Bold + Red + "✗" + Reset
	default:
		return Gray + "·" + Reset
	}
}
