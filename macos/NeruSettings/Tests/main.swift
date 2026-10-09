// Settings app self-checks. Run: just check-settings
// Every check is a plain assert; a failure stops with the line that broke.
runCoreTests()
runLauncherTests()
runScrollTests()
runGridTests()
runPerAppTests()
runUpdateTests()
print("ok")
