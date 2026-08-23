cask "pi-helicopter" do
  version "0.1.1"
  sha256 "a0caab6e6e01b514cf9944a6a667cc3249d5f7e8a6fd7c2d2cec095dbcfa96dc"

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
