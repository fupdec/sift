# Sift

Free macOS utility built with SwiftUI. Organizes files in a folder by **creation age** or by **extension**.

## MVP features

- Choose a folder (button or drag & drop)
- Modes: by age / by extension
- Option to include subfolders
- Preview moves before applying
- Creates folders and moves files
- Unique names on conflicts (`file (2).pdf`)
- Automator workflow and scheduled runs (same rules as in the window)
- UI languages: English, Spanish, Chinese, Russian

### By age
Thresholds are set in the **Timing** dialog (defaults):
- younger than **3 days** — stay in the folder
- **3–7 days** → `7 days`
- **8–30 days** → `30 days`
- older than **30 days** → `Archive`

Folder names follow the selected app language.

### By extension
Groups such as `Images`, `PDF`, `Documents`, `Code`, or a folder named after the extension.

## Run

1. Open `Sift.xcodeproj` in Xcode
2. Select the **Sift** scheme
3. Run (`⌘R`)

Requirements: macOS 13+, Xcode 15+

## Automator and schedule

1. Choose a folder and mode (age / extension, subfolders, thresholds in **Timing**).
2. Click **Add to Automator**.
3. Pick an interval: every hour, every day, or every week.

Sift saves the folder, installs an Automator workflow, and runs the same organize pass in the background.

- Services: `Organize Files (Sift)` — assign a hotkey in System Settings
- Calendar alarm: `~/Library/Workflows/Applications/Calendar/Sift.workflow`
- Background launch: Login Item / LaunchAgent; results arrive as a notification

If macOS asks for permission, enable Sift under **Settings → General → Login Items & Extensions**. Allow notifications when prompted.

## Safety

- Moves only inside the selected folder
- App Sandbox + access to user-selected files
- Offline — no network, no accounts
