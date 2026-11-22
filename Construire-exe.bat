@echo off
rem Construit "PUBG GL Expert.exe" avec le compilateur C# inclus dans Windows (.NET Framework 4).
rem Aucun telechargement. Si gameloop\GLP_installer.exe existe, il est integre dans l'exe.
setlocal
set "OUT=%~dp0PUBG GL Expert.exe"
echo Fermeture des anciennes copies...
taskkill /im "PUBG GL Expert.exe" /f >nul 2>&1
taskkill /im PubgSetup.exe /f >nul 2>&1
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.ProcessId -ne $PID -and $_.CommandLine -like '*PubgSetup\app\PubgSetup.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
ping -n 2 127.0.0.1 >nul
if exist "%OUT%" del /f "%OUT%"
if exist "%OUT%" goto :busy
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" goto :nocsc
set "RES="
set "INSTMSG=non integre (placez GLP_installer.exe dans le dossier gameloop puis reconstruisez)"
if exist "%~dp0gameloop\GLP_installer.exe" set RES=/resource:"%~dp0gameloop\GLP_installer.exe",GLP_installer.exe
if exist "%~dp0gameloop\GLP_installer.exe" set "INSTMSG=integre dans l'exe"
"%CSC%" /nologo /target:winexe /optimize+ /out:"%OUT%" /win32icon:"%~dp0src\app.ico" /win32manifest:"%~dp0src\app.manifest" /resource:"%~dp0src\PubgSetup.ps1",PubgSetup.ps1 %RES% /r:System.Windows.Forms.dll "%~dp0src\Launcher.cs"
if errorlevel 1 goto :fail
echo.
echo PUBG GL Expert v4.1 est pret : %OUT%
echo Installateur de l'ancien GameLoop : %INSTMSG%
echo Ce seul fichier suffit sur un autre PC. Il demande les droits administrateur au lancement.
pause
exit /b 0
:busy
echo "PUBG GL Expert.exe" est encore utilise. Fermez-le ou redemarrez le PC, puis relancez ce fichier.
pause
exit /b 1
:nocsc
echo Compilateur C# introuvable. Installez .NET Framework 4.8.
pause
exit /b 1
:fail
echo.
echo Echec de la compilation.
pause
exit /b 1
