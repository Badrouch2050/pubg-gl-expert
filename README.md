# PUBG GL Expert

Keep the **old GameLoop** for PUBG Mobile, without forced updates or the switch to GameLoop 7.
An 8-step wizard installs the old GameLoop, sets up protections, locks updates and startup launch, tunes PUBG's display and launches the game.

**Website / Guide (FR · EN · AR):** https://badrouch2050.github.io/pubg-gl-expert/
**Download:** [PUBG-GL-Expert-v4.1.zip](download/PUBG-GL-Expert-v4.1.zip)
**Contact:** [Discord](https://discord.gg/qVRBMt74h)

Developed by **TNL YORYO**.

---

## Français
Gardez l'ancien GameLoop pour PUBG Mobile, sans mises à jour forcées ni passage à GameLoop 7.
1. Téléchargez le zip depuis [download/PUBG-GL-Expert-v4.1.zip](download/PUBG-GL-Expert-v4.1.zip) et extrayez-le.
2. Lancez « PUBG GL Expert.exe » et acceptez la demande administrateur.
3. Suivez l'assistant en 8 étapes. Ne redémarrez pas avant l'étape 5 « Verrouillage final ».

## العربية
احتفظ بـ GameLoop القديم للعبة PUBG Mobile بدون تحديثات إجبارية أو انتقال إلى GameLoop 7.
1. حمّل ملف zip من [download/PUBG-GL-Expert-v4.1.zip](download/PUBG-GL-Expert-v4.1.zip) واستخرجه.
2. شغّل «PUBG GL Expert.exe» ووافق على طلب صلاحيات المسؤول.
3. اتبع المساعد المكون من 8 خطوات. لا تعد تشغيل الكمبيوتر قبل الخطوة 5 «القفل النهائي».

---

## Build from source
Windows only, no extra tools needed (uses the .NET Framework `csc.exe` built into Windows).
1. Optional: put the old GameLoop online installer at `gameloop\GLP_installer.exe` to embed it.
2. Run `Construire-exe.bat`. It produces `PUBG GL Expert.exe`.

| File | Role |
|---|---|
| `src/PubgSetup.ps1` | The tool (PowerShell 5.1 + WPF) |
| `src/Launcher.cs` | Small exe that runs the embedded script |
| `src/app.manifest` | Requests administrator rights |
| `index.html` | The website (GitHub Pages) |

The anti-cheat (`Updater32.exe`) and PUBG files are never modified. Every block can be undone from Expert mode.

*Independent free tool, not affiliated with Tencent, Krafton, Level Infinite or GameLoop. Use at your own risk.*
