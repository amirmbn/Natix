// Package version holds the release version, overridable at build time with
// -ldflags "-X natix/pkg/version.Version=1.0.0".
package version

var Version = "1.0.0"

// RepoURL is the project repository shown in the CLI.
const RepoURL = "https://github.com/amirmbn/Natix"
