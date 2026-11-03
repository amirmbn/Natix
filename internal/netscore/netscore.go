package netscore

import (
	"net"
	"os/exec"
	"regexp"
	"sort"
	"strconv"
)

type EndpointScore struct {
	Addr      string
	RTTms     float64
	JitterMs  float64
	LossPct   float64
	Score     float64
	Reachable bool
}

func computeScore(rttMs, jitterMs, lossPct float64) float64 {
	return rttMs + 2*jitterMs + 20*lossPct
}

var (
	reScoreRTT  = regexp.MustCompile(`=\s*[0-9.]+/([0-9.]+)/[0-9.]+/([0-9.]+)`)
	reScoreLoss = regexp.MustCompile(`([0-9.]+)% packet loss`)
)

func hostOf(addr string) string {
	if h, _, err := net.SplitHostPort(addr); err == nil {
		return h
	}
	return addr
}

func parseScorePing(out string) EndpointScore {
	var s EndpointScore
	if m := reScoreLoss.FindStringSubmatch(out); m != nil {
		s.LossPct, _ = strconv.ParseFloat(m[1], 64)
	} else {
		s.LossPct = 100
	}
	if m := reScoreRTT.FindStringSubmatch(out); m != nil {
		s.RTTms, _ = strconv.ParseFloat(m[1], 64)
		s.JitterMs, _ = strconv.ParseFloat(m[2], 64)
		s.Reachable = true
	}
	s.Score = computeScore(s.RTTms, s.JitterMs, s.LossPct)
	return s
}

func ScoreEndpoint(addr string, samples int) EndpointScore {
	if samples <= 0 {
		samples = 5
	}
	cmd := exec.Command("ping", "-c", strconv.Itoa(samples), "-i", "0.2", "-W", "2", "-q", hostOf(addr))
	out, _ := cmd.CombinedOutput() // non-zero exit on loss is expected; parse anyway
	s := parseScorePing(string(out))
	s.Addr = addr
	if !s.Reachable {
		s.Score = 1e9 // last, but still comparable
	}
	return s
}

func ScoreEndpoints(addrs []string, samples int) []EndpointScore {
	out := make([]EndpointScore, len(addrs))
	for i, a := range addrs {
		out[i] = ScoreEndpoint(a, samples)
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Score < out[j].Score })
	return out
}
