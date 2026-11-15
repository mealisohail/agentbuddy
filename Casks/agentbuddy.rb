cask "agentbuddy" do
  version "1.0.2"
  sha256 "a76514375e4b850b54797bf1de12c61c09e0635ef6eb2aad0517288f2ebe220c"

  url "https://github.com/mealisohail/agentbuddy/releases/download/v#{version}/AgentBuddy.zip"
  name "AgentBuddy"
  desc "Notch island that watches your Claude Code sessions and answers their prompts"
  homepage "https://github.com/mealisohail/agentbuddy"

  depends_on macos: :sonoma

  app "AgentBuddy.app"

  # Not notarized (no paid Apple Developer account): clear the download quarantine so macOS lets it open.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/AgentBuddy.app"]
  end

  # Take our PermissionRequest hook back out of ~/.claude/settings.json before the app disappears.
  uninstall_preflight_steps do
    run "AgentBuddy.app/Contents/MacOS/AgentBuddy",
        args:           ["--uninstall-hook"],
        base:           :appdir,
        must_succeed:   false,
        writable_paths: [".claude"],
        writable_base:  :home
  end
  uninstall quit: "dev.agentbuddy.app"

  zap trash: [
    "~/.agentbuddy",
    "~/Library/Preferences/dev.agentbuddy.app.plist",
  ]
end
