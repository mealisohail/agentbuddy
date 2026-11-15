cask "agentbuddy" do
  version "1.0.2"
  sha256 "c8d15cf6e08466906050f7d83cf279af0fe84018e21f9c2755b80e95bf67e767"

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
