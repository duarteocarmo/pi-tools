cask "pi-helicopter" do
  version "0.1.4"
  sha256 "0c0cac554b36e76b4a0873d850595679a74741b65f3b55c0a59781f0258cc4c8"

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
