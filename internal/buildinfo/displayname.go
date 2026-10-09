package buildinfo

// DisplayName is the product name the tray menu shows the user. Identifiers
// (bundle id, binary, config dir, socket) keep the name neru. Override with
// -ldflags "-X github.com/y3owk1n/neru/internal/buildinfo.DisplayName=...".
var DisplayName = "Homekey"

// RepoURL is the repository the app sends people to: source, docs, issues.
// Override with -ldflags "-X github.com/y3owk1n/neru/internal/buildinfo.RepoURL=...".
var RepoURL = "https://github.com/alexanderconun/neru"
