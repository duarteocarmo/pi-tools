cask "pi-helicopter" do
  version "0.1.2"
  sha256 "959e39565159122a443c65fd97ae7fc7e9da4600faa6719bce2dfc19a1af172c"

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
