cask "clipbara" do
  version "1.2.0"
  sha256 "9fcb1ac2d071a722a65cd8334c185c79958f2a9cce3623929685fc973307eb48"

  url "https://github.com/mobrava/Clipbara/releases/download/v#{version}/Clipbara-v#{version}.dmg"
  name "Clipbara"
  desc "Free, open-source clipboard manager for macOS (formerly PasteClip)"
  homepage "https://github.com/mobrava/Clipbara"

  depends_on macos: ">= :sonoma"

  app "Clipbara.app"

  zap trash: [
    "~/Library/Application Support/com.minsang.PasteClip",
    "~/Library/Preferences/com.minsang.PasteClip.plist",
  ]
end
