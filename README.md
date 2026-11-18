# Temp Cleaner for Windows

**See how much space temporary files are using and clear them safely in one click.**
A free desktop widget by **V-Sharp AI Labs Limited**.

Haven't cleared your temp files in a while? Apps and Windows leave temporary files behind and rarely remove them — over months this can grow to several gigabytes. A nearly full drive can slow Windows down and stop updates installing.

- Runs only on your PC — **collects no data, no internet connection**, no account
- **No admin rights** needed
- Files in use are never touched, so open apps are not affected
- Only your own Temp folder is cleaned — nothing else

Works on Windows 10 and 11.

## Download

Get the latest **TempCleaner-x.y.z.zip** from [Releases](../../releases/latest).

## Install

1. Extract the zip.
2. Right-click **Install.ps1** → **Run with PowerShell**.

   If that option doesn't appear or the window closes straight away, open **PowerShell** and run
   (change the path to where you extracted it):
   ```powershell
   powershell -ExecutionPolicy Bypass -File "C:\Users\<you>\Downloads\TempCleaner\Install.ps1"
   ```
3. The widget appears at the top-right of your desktop and starts with Windows.

> Windows may warn that the file came from the internet. This is normal for free tools that are not code-signed — the full code is in this repository for you to check.

**Update:** download the new version and run **Install.ps1** again — your settings are kept.
**Uninstall:** *Settings → Apps → Installed apps → Temp Cleaner → Uninstall*.

## Use

- Click **Clean now** and confirm. When it finishes it shows how much space was freed.
- Deleted files do **not** go to the Recycle Bin. Temporary files are not needed, but if you saved something important in Temp, move it first.
- Close other apps (especially installers) for the best result.

Right-click the widget for:

| Option | Choices |
|---|---|
| Clean mode | Only files older than 1 day *(default, safest)* · Everything not in use |
| Automatic clean | Off *(default)* · Each time the widget starts · Once a day |
| Check size | Every 1 hour *(default)* · 3 · 6 · 12 · 24 hours · On demand only |
| Start with Windows | Start automatically at startup · Do not start automatically at startup |
| Also | Clean now · Refresh size · Open Temp folder · About · Hide · Exit |

Settings like the "older than" days can be changed at the top of
`%LOCALAPPDATA%\TempCleaner\TempCleaner.ps1`.

## FAQ

**Will it make my PC faster?**
It frees disk space. If your drive was nearly full, that can make Windows feel faster and let updates install again. If you already have plenty of free space, you won't notice a speed difference.

**Is it safe to delete temp files?**
Yes — they are temporary by design. Temp Cleaner skips files in use and, by default, anything changed in the last day.

**Does it clean `C:\Windows\Temp`?**
No — that needs administrator rights. Only your own Temp folder is cleaned.

**Mac or Linux?** No, Windows only.

**Something went wrong?** Details are in `%APPDATA%\TempCleaner\error.log`. Please [open an issue](../../issues).

## Privacy

No data is collected. See [PRIVACY.md](PRIVACY.md).

## Licence

[MIT](LICENSE) © 2026 V-Sharp AI Labs Limited
