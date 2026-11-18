# Privacy

**Temp Cleaner collects no data.**

- It has no internet code: it never connects to the internet or sends anything anywhere.
- No account, sign-in, analytics, tracking, ads or telemetry.
- Everything runs locally on your PC.

## What it reads and changes on your PC

| What | Why |
|---|---|
| Your Temp folder (`%TEMP%`) | Measures its size; deletes temporary files only when you click **Clean now** or turn on automatic cleaning |
| `%LOCALAPPDATA%\TempCleaner` | The program itself |
| `%APPDATA%\TempCleaner` | Your settings (clean mode, widget position, last clean time) and an error log |
| Desktop and Startup shortcuts | To open the widget and, if you choose, start it with Windows |
| One entry in *Settings > Apps > Installed apps* | So you can see and uninstall it |

It does not need administrator rights and does not touch any other folder.
Uninstalling removes everything listed above.

The code is open: you can read `TempCleaner.ps1` in Notepad to check all of this.

Questions: open an issue on this repository.

© 2026 V-Sharp AI Labs Limited
