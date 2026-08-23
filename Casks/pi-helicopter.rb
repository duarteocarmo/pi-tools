cask "pi-helicopter" do
  version "0.1.0"
  sha256 "7210ddc99c65fe7ad805170604acd0e2e0589060356f6757397ca7a16beec0c0"

  url "https://github.com/duarteocarmo/pi-tools/releases/download/pi-helicopter-v#{version}/Pi-Helicopter-#{version}.zip"
  name "Pi Helicopter"
  desc "Show local Pi usage and costs in the menu bar"
  homepage "https://github.com/duarteocarmo/pi-tools/tree/master/packages/pi-helicopter"

  depends_on macos: :ventura

  app "Pi Helicopter.app"

  uninstall quit: "com.duarteocarmo.pi-helicopter"

  zap trash: "~/Library/Preferences/com.duarteocarmo.pi-helicopter.plist"

  caveats <<~EOS
    Pi Helicopter is not notarized. Open Applications in Finder, Control-click Pi Helicopter, select Open, then confirm Open.
  EOS
end
