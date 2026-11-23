## Install

1. Download **Relay-1.0.zip** below and double-click it to unzip.
2. Drag **Relay.app** into your **Applications** folder.
3. Open it. macOS blocks the first launch because Relay isn't notarized:
   open **System Settings › Privacy & Security**, scroll down, and click **Open Anyway** next to Relay.
   (Or in Terminal: `xattr -dr com.apple.quarantine /Applications/Relay.app`)
4. Relay asks two things:
   - **Add to Dock**: adds three blank spaces at the right end of the Dock and restarts it once.
   - **Accessibility access**: turn Relay on under *Privacy & Security › Accessibility*, so it can find those spaces.

The bar then appears in the Dock. Click it for the full readout; right-click it for the menu.

Requires **macOS 26 (Tahoe)** or later. Universal binary: Apple Silicon and Intel.
