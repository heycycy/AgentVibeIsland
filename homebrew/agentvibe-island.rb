cask "agentvibe-island" do
  version "0.1.0"
  sha256 :no_check # update with real sha256 on first release

  url "https://github.com/clarkyao_microsoft/AgentVibeIsland/releases/download/v#{version}/AgentVibeIsland-#{version}.dmg"
  name "Agent Vibe Island"
  desc "Notch-anchored permission hub for coding agents"
  homepage "https://github.com/clarkyao_microsoft/AgentVibeIsland"

  app "AgentVibeIsland.app"

  zap trash: [
    "~/.agentvibeisland",
    "~/Library/Preferences/com.clarkyao.AgentVibeIsland.plist",
  ]
end
