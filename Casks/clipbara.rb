cask "clipbara" do
  version "1.3.2"
  sha256 "7a1edd3b21353c5fa3d87454c83bacef008c6ef0e5f79f95ec51ebd05614d942"

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
