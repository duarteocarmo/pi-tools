cask "pi-helicopter" do
  version "0.1.3"
  sha256 "c60f82f5784bb93595fff901801a2f75c17b09e3456a48a0225d8296c2cceeb3"

  url "https://github.com/duarteocarmo/pi-tools/releases/download/pi-helicopter-v#{version}/Pi-Helicopter-#{version}.zip"
  name "Pi Helicopter"
  desc "Show local Pi usage and costs in the menu bar"
  homepage "https://github.com/duarteocarmo/pi-tools/tree/master/packages/pi-helicopter"

  depends_on macos: :ventura

  app "Pi Helicopter.app"

  uninstall quit: "com.duarteocarmo.pi-helicopter"

  zap trash: "~/Library/Preferences/com.duarteocarmo.pi-helicopter.plist"

  caveats <<~EOS
    Pi Helicopter is ad hoc signed. If macOS blocks the first launch, open System Settings and select Privacy & Security. Scroll to Security, click Open Anyway for Pi Helicopter, then confirm Open.
  EOS
end
