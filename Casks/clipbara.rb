cask "clipbara" do
  version "1.1.11"
  sha256 "69ae94d7adc6b69aad52865e4ad3b38cd9ab97059d5221de254175c0f7d6ecce"

  url "https://github.com/mobrava/Clipbara/releases/download/v#{version}/PasteClip-v#{version}.dmg"
  name "Clipbara"
  desc "Free, open-source clipboard manager for macOS (formerly PasteClip)"
  homepage "https://github.com/mobrava/Clipbara"

  depends_on macos: ">= :sonoma"

  # v1.1.11 still ships as PasteClip.app; the bundle is renamed in v1.2.0
  app "PasteClip.app"

  zap trash: [
    "~/Library/Application Support/com.minsang.PasteClip",
    "~/Library/Preferences/com.minsang.PasteClip.plist",
  ]
end
