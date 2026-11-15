cask "agentbuddy" do
  version "1.0.1"
  sha256 "b031ba7907ead386e956902acddc44a168bcf4dcbf1c7efd623294b07b01d7ba"

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
