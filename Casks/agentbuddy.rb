cask "agentbuddy" do
  version "1.0.0"
  sha256 "42360b6e4a6730a525efe4af26dfde82e102abe239ee4e77f93035bb8c9a6872"

  url "https://github.com/mealisohail/agentbuddy/releases/download/v#{version}/AgentBuddy.zip"
  name "AgentBuddy"
  desc "Notch island that watches your Claude Code sessions and answers their prompts"
  homepage "https://github.com/mealisohail/agentbuddy"

  depends_on macos: ">= :sonoma"

  app "AgentBuddy.app"

  # Not notarized (no paid Apple Developer account): clear the download quarantine so macOS lets it open.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/AgentBuddy.app"]
  end

  # Take our PermissionRequest hook back out of ~/.claude/settings.json before the app disappears.
  uninstall_preflight do
    system_command "#{appdir}/AgentBuddy.app/Contents/MacOS/AgentBuddy", args: ["--uninstall-hook"]
  end
  uninstall quit: "dev.agentbuddy.app"

  zap trash: [
    "~/.agentbuddy",
    "~/Library/Preferences/dev.agentbuddy.app.plist",
  ]
end
