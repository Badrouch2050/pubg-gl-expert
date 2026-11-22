<#
  PUBG GL Expert  -  v4.1  (developed by TNL YORYO ; assistant pas a pas en 8 etapes, interface WPF, portable, moniteur Metrics, blocage MAJ GameLoop, blocage au demarrage, fermeture complete, mode jeu)
  Reglages PUBG Mobile pour GameLoop : préréglages intelligents, resolution / DPI,
  modele d'appareil, FPS et qualite par version, keymap, lancement, restauration.

  Securite :
  - N'ecrit que dans HKCU\Software\Tencent\MobileGamePC, uniquement les valeurs de
    la liste blanche, et seulement si elles existent deja (type conserve).
  - Export .reg automatique + apercu + confirmation avant toute ecriture.
  - GameLoop doit etre ferme pour appliquer.
  - Ne touche jamais : ano_tmp, tersafe, authentification, binaires, sauvegardes du jeu.
  - Donnees de l'outil : %LOCALAPPDATA%\PubgSetup (profils, sauvegardes, journaux).
#>
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$ErrorActionPreference = 'Stop'
$AppVersion = '4.1'

$RegPath   = 'HKCU:\Software\Tencent\MobileGamePC'
$RegNative = 'HKCU\Software\Tencent\MobileGamePC'
$DataRoot  = Join-Path $env:LOCALAPPDATA 'PubgSetup'
$Dirs = @{
  Profiles = Join-Path $DataRoot 'profiles'
  Backups  = Join-Path $DataRoot 'backups'
  Keymaps  = Join-Path $DataRoot 'keymaps'
  Logs     = Join-Path $DataRoot 'logs'
}
$Dirs.Values | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }
$LogFile = Join-Path $Dirs.Logs ("pubgsetup-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))

$Builds = [ordered]@{
  'Global'        = 'com.tencent.ig'
  'Vietnam'       = 'com.vng.pubgmobile'
  'Coree / Japon' = 'com.pubg.krmobile'
  'Taiwan'        = 'com.rekoo.pubgm'
}
$Allowed   = '^(VMResWidth|VMResHeight|VMDPI|VMDeviceModel|VMDeviceManufacturer|FxaaQuality|GraphicsCardEnabled|ShaderCacheEnabled|LocalShaderCacheEnabled|(com\.tencent\.ig|com\.vng\.pubgmobile|com\.pubg\.krmobile|com\.rekoo\.pubgm)_(FPSLevel|RenderQuality))$'
$Forbidden = 'ano_tmp|tersafe|tp3helper|imsdk|msdk|login|token|cookie|account'
$GameLoopProcs = 'AndroidEmulator','AndroidEmulatorEn','AndroidEmulatorEx','AndroidRenderer','AppMarket','aow_exe'

# ---------------- Utilitaires ----------------
function Log([string]$m) {
  $line = "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
  Add-Content -Path $LogFile -Value $line -Encoding UTF8
  if ($script:LogBox) { $script:LogBox.AppendText($line + "`r`n"); $script:LogBox.ScrollToEnd() }
}
function Ask([string]$msg) { [System.Windows.MessageBox]::Show($msg, 'PUBG GL Expert', 'YesNo', 'Question') -eq 'Yes' }
function AskNo([string]$msg) { [System.Windows.MessageBox]::Show($msg, 'PUBG GL Expert', 'YesNo', 'Warning', 'No') -eq 'Yes' }
function Info([string]$msg, [string]$icon = 'Information') { [void][System.Windows.MessageBox]::Show($msg, 'PUBG GL Expert', 'OK', $icon) }

# ---------------- Detection de GameLoop (n'importe quel PC) ----------------
$SettingsFile = Join-Path $DataRoot 'settings.json'
function Test-GameLoopUi([string]$p) {
  if (-not $p -or -not (Test-Path $p)) { return $null }
  foreach ($cand in @($p, (Join-Path $p 'ui'), (Join-Path (Split-Path $p -Parent) 'ui'))) {
    if ($cand -and ((Test-Path (Join-Path $cand 'AndroidEmulatorEx.exe')) -or (Test-Path (Join-Path $cand 'AndroidEmulatorEn.exe')) -or (Test-Path (Join-Path $cand 'AndroidEmulator.exe')))) {
      return (Resolve-Path $cand).Path
    }
  }
  $null
}
function Find-GameLoopUi {
  $script:FoundBy = ''
  # 1. Dossier choisi a la main et memorise
  if (Test-Path $SettingsFile) {
    try { $cfg = Get-Content $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json; $r = Test-GameLoopUi $cfg.GameLoopUi; if ($r) { $script:FoundBy = 'dossier memorise'; return $r } } catch { }
  }
  # 2. GameLoop en cours d'execution
  foreach ($pr in @(Get-Process -Name $GameLoopProcs -ErrorAction SilentlyContinue)) {
    try { $r = Test-GameLoopUi (Split-Path $pr.Path -Parent); if ($r) { $script:FoundBy = 'processus en cours'; return $r } } catch { }
  }
  # 3. Registre : desinstallation et cles Tencent (chemins seulement)
  $cands = New-Object System.Collections.Generic.List[string]
  foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
    Get-ItemProperty $k -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -match 'GameLoop|Gaming Buddy|TxGameAssistant|MobileGamePC|Tencent' } |
      ForEach-Object {
        if ($_.InstallLocation) { $cands.Add($_.InstallLocation) }
        foreach ($v in @($_.UninstallString, $_.DisplayIcon)) { if ($v -match '([A-Za-z]:\\[^"]+?)\\[^\\"]+\.(exe|ico)') { $cands.Add($Matches[1]) } }
      }
  }
  foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Tencent', 'HKLM:\SOFTWARE\Tencent', 'HKCU:\Software\Tencent') {
    if (-not (Test-Path $k)) { continue }
    foreach ($key in @(Get-ChildItem $k -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'MobileGamePC|TxGameAssistant|GameLoop|AppMarket' })) {
      foreach ($n in $key.GetValueNames()) {
        if ($n -match 'Path|Dir|Install|Location') {
          $v = [string]$key.GetValue($n)
          if ($v -match '^[A-Za-z]:\\') { $cands.Add(($v -replace '\\[^\\]+\.exe$', '')) }
        }
      }
    }
  }
  foreach ($c in $cands) { $r = Test-GameLoopUi $c; if ($r) { $script:FoundBy = 'registre Windows'; return $r } }
  # 4. Raccourcis GameLoop (bureau et menu Demarrer)
  try {
    $sh = New-Object -ComObject WScript.Shell
    $lnkDirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'),
                 [Environment]::GetFolderPath('StartMenu'), [Environment]::GetFolderPath('CommonStartMenu'))
    foreach ($d in $lnkDirs | Where-Object { $_ -and (Test-Path $_) }) {
      foreach ($l in @(Get-ChildItem $d -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue)) {
        $t = $sh.CreateShortcut($l.FullName).TargetPath
        if ($t -match 'AppMarket\.exe|AndroidEmulator\w*\.exe|TxGameAssistant') {
          $r = Test-GameLoopUi (Split-Path $t -Parent); if ($r) { $script:FoundBy = 'raccourci'; return $r }
        }
      }
    }
  } catch { }
  # 5. Emplacements courants sur tous les disques
  foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
    foreach ($sub in 'Program Files\TxGameAssistant', 'Program Files (x86)\TxGameAssistant', 'TxGameAssistant', 'GameLoop\TxGameAssistant', 'Games\TxGameAssistant') {
      $r = Test-GameLoopUi (Join-Path $d.Root $sub); if ($r) { $script:FoundBy = 'recherche sur les disques'; return $r }
    }
  }
  $null
}
function Set-GameLoopUi([string]$p) {
  $script:GameLoopUi = $p
  $script:Adb = if ($p -and (Test-Path (Join-Path $p 'adb.exe'))) { Join-Path $p 'adb.exe' } else { $null }
}
function Choose-GameLoopFolder {
  Add-Type -AssemblyName System.Windows.Forms
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description = 'Choisissez le dossier d''installation de GameLoop (souvent TxGameAssistant).'
  if ($dlg.ShowDialog() -ne 'OK') { return $false }
  $r = Test-GameLoopUi $dlg.SelectedPath
  if (-not $r) { Info "Ce dossier ne contient pas GameLoop (AndroidEmulator*.exe introuvable)." 'Warning'; return $false }
  @{ GameLoopUi = $r } | ConvertTo-Json | Set-Content $SettingsFile -Encoding UTF8
  Set-GameLoopUi $r; $script:FoundBy = 'choisi a la main'
  Log "Dossier GameLoop choisi : $r"
  $true
}
Set-GameLoopUi (Find-GameLoopUi)
# v4 : plus de question au demarrage, l'assistant guide l'installation ou le choix du dossier.
$script:Serial = '127.0.0.1:5555'
$script:AdbServerArgs = @()

# ---------------- Registre ----------------
function Get-RegValue([string]$name) {
  if (-not (Test-Path $RegPath)) { return $null }
  $k = Get-Item $RegPath
  if ($k.GetValueNames() -notcontains $name) { return $null }
  [pscustomobject]@{ Name = $name; Value = $k.GetValue($name); Kind = $k.GetValueKind($name) }
}
function Test-GameLoopRunning { @(Get-Process -Name $GameLoopProcs -ErrorAction SilentlyContinue).Count -gt 0 }
function Backup-Registry([string]$tag) {
  if (-not (Test-Path $RegPath)) { throw "Cle $RegNative absente : rien a sauvegarder." }
  $file = Join-Path $Dirs.Backups ("reg-{0}-{1}.reg" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $tag)
  $p = Start-Process reg.exe -ArgumentList @('export', $RegNative, "`"$file`"", '/y') -Wait -PassThru -WindowStyle Hidden
  if ($p.ExitCode -ne 0 -or -not (Test-Path $file)) { throw "Echec de la sauvegarde du registre (code $($p.ExitCode))." }
  Log "Sauvegarde registre : $(Split-Path $file -Leaf)"
  $file
}
function Convert-ForKind($value, $kind) {
  switch ([string]$kind) {
    'DWord'        { return [int]$value }
    'QWord'        { return [long]$value }
    'String'       { return [string]$value }
    'ExpandString' { return [string]$value }
    default        { throw "type $kind non pris en charge" }
  }
}

# ---------------- Appareils ----------------
$Devices = [ordered]@{}
if ($GameLoopUi) {
  $df = Join-Path $GameLoopUi 'phone_device_oversea.json'
  if (-not (Test-Path $df)) { $df = Join-Path $GameLoopUi 'phone_device.json' }
  if (Test-Path $df) {
    try {
      $json = Get-Content $df -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($p in $json.PSObject.Properties) { $Devices[$p.Name] = $p.Value }
    } catch { }
  }
}
function Resolve-DeviceValues([string]$deviceName) {
  $d = $Devices[$deviceName]
  $cur = Get-RegValue 'VMDeviceModel'
  $model = $deviceName
  if ($cur) {
    foreach ($k in $Devices.Keys) { if ([string]$cur.Value -eq [string]$Devices[$k].'ro.product.model') { $model = $d.'ro.product.model' } }
  }
  @{ VMDeviceModel = $model; VMDeviceManufacturer = $d.'ro.product.manufacturer' }
}
$TopDevice = @($Devices.Keys | Where-Object { $_ -match 'ROG' }) + @($Devices.Keys) | Select-Object -First 1

# ---------------- ADB ----------------
function Invoke-Adb([string[]]$adbArgs, [int]$TimeoutMs = 8000) {
  if (-not $Adb) { throw "GameLoop introuvable sur ce PC." }
  $psi = New-Object System.Diagnostics.ProcessStartInfo $Adb
  $psi.Arguments = ($adbArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($TimeoutMs)) { try { $p.Kill() } catch { }; return '(delai depasse)' }
  # Si adb vient de demarrer son serveur, celui-ci garde les sorties ouvertes : on n'attend pas plus.
  [void]$o.Wait(1500); [void]$e.Wait(1500)
  $txt = ''
  if ($o.IsCompleted) { $txt += $o.Result }
  if ($e.IsCompleted) { $txt += "`n" + $e.Result }
  $txt.Trim()
}
function Get-ListenPorts([string[]]$procNames) {
  $pids = @(Get-Process -Name $procNames -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
  if (-not $pids) { return @() }
  try {
    @(Get-NetTCPConnection -State Listen -ErrorAction Stop |
      Where-Object { $pids -contains $_.OwningProcess -and $_.LocalAddress -match '^(127\.0\.0\.1|0\.0\.0\.0|::|::1)$' } |
      ForEach-Object { [int]$_.LocalPort } | Sort-Object -Unique)
  } catch { @() }
}
function Get-OnlineDevice([string]$text) {
  $l = $text -split "`r?`n" | Where-Object { $_ -match '^(\S+)\s+device\s*$' } | Select-Object -First 1
  if ($l -and $l -match '^(\S+)\s+device\s*$') { $Matches[1] } else { $null }
}
function Connect-Android {
  if (-not (Test-GameLoopRunning)) { throw "GameLoop n'est pas ouvert. Lancez-le et attendez l'ecran d'accueil." }
  $dis = Get-RegValue 'AdbDisable'
  if ($dis -and [string]$dis.Value -ne '0') { Log "Attention : AdbDisable = $($dis.Value) dans le registre GameLoop." }
  $tries = New-Object System.Collections.Generic.List[string]

  # 1. Serveur adb par defaut (port 5037)
  [void](Invoke-Adb @('start-server') 10000)
  $dev = Get-OnlineDevice (Invoke-Adb @('devices'))
  if ($dev) { $script:Serial = $dev; $script:AdbServerArgs = @(); Log "Android trouve : $dev"; return }

  # 2. Serveur adb lance par GameLoop sur un autre port
  foreach ($sp in @(Get-ListenPorts @('adb')) | Where-Object { $_ -ne 5037 }) {
    $r = Invoke-Adb @('-P', "$sp", 'devices') 5000
    $tries.Add("serveur $sp : " + ($r -replace '\s+', ' '))
    $dev = Get-OnlineDevice $r
    if ($dev) { $script:Serial = $dev; $script:AdbServerArgs = @('-P', "$sp"); Log "Android trouve via le serveur adb de GameLoop (port $sp) : $dev"; return }
  }

  # 3. adb connect sur 5555 puis sur les ports ouverts par l'emulateur
  $ports = New-Object System.Collections.Generic.List[int]
  foreach ($x in @(5555) + @(Get-ListenPorts $GameLoopProcs) + @(5556, 5557, 5565, 5575)) { if (-not $ports.Contains([int]$x)) { $ports.Add([int]$x) } }
  foreach ($port in ($ports | Select-Object -First 16)) {
    $s = "127.0.0.1:$port"
    $r = Invoke-Adb @('connect', $s) 6000
    $tries.Add("$s : " + ($r -replace '\s+', ' '))
    if ((Invoke-Adb @('-s', $s, 'get-state') 4000) -eq 'device') { $script:Serial = $s; $script:AdbServerArgs = @(); Log "Android connecte sur $s"; return }
  }
  $tries | ForEach-Object { Log "  essai ADB  $_" }
  if ($dis -and [string]$dis.Value -ne '0') { throw "L'ADB est desactive dans GameLoop (AdbDisable = $($dis.Value)). La detection des versions en a besoin ; le lancement du jeu, lui, fonctionne sans." }
  throw "Android n'est pas joignable par ADB. $($tries.Count) essais, details dans l'onglet Journal."
}
function Invoke-Shell([string]$cmd, [int]$TimeoutMs = 10000) {
  Invoke-Adb (@($script:AdbServerArgs) + @('-s', $script:Serial, 'shell', $cmd)) $TimeoutMs
}
function Get-InstalledBuilds {
  Connect-Android
  $pk = Invoke-Shell 'pm list packages'
  $res = [ordered]@{}
  foreach ($b in $Builds.Keys) { $res[$b] = ($pk -match [regex]::Escape("package:$($Builds[$b])")) }
  $res['PlayStore'] = ($pk -match 'package:com\.android\.vending')
  $res
}
function Start-AndroidPackage([string]$pkg) {
  # Methode officielle de GameLoop (comme ses raccourcis de bureau) : pas besoin d'ADB.
  $glr = Get-GameLoopRoot
  $am = if ($glr) { Join-Path $glr 'AppMarket\AppMarket.exe' } else { $null }
  if ($am -and (Test-Path $am)) {
    Start-Process -FilePath $am -ArgumentList @('-startpkg', $pkg, '-from', 'DesktopLink')
    Log "Lancement de $pkg via GameLoop (AppMarket -startpkg)"
    return
  }
  # Repli : ADB, si GameLoop l'autorise
  Connect-Android
  $installed = Invoke-Shell "pm list packages $pkg"
  if ($installed -notmatch [regex]::Escape("package:$pkg")) { throw "$pkg n'est pas installe dans GameLoop." }
  Invoke-Shell "monkey -p $pkg -c android.intent.category.LAUNCHER 1" | Out-Null
  Log "Lancement de $pkg via ADB"
}

# ---------------- Recommandation selon la carte graphique ----------------
function Get-Recommendation {
  $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
  $name = ($gpus | Where-Object { $_ -match 'NVIDIA|GeForce|Radeon RX|Arc' } | Select-Object -First 1)
  if (-not $name) { $name = $gpus | Select-Object -First 1 }
  $tier = 'Competitif'
  if ($name -match 'RTX\s*(30|40|50)\d\d|RX\s*(6[7-9]|7[6-9]|9\d)\d\d|Arc\s*A7') { $tier = 'Qualite' }
  elseif ($name -match 'RTX\s*20\d\d|GTX\s*(9[7-8]0|10[6-8]0|16\d0)|RX\s*(5[5-9]|5[6-7]\d0|6[4-6]\d0)') { $tier = 'Equilibre' }
  [pscustomobject]@{ Gpu = $name; Tier = $tier }
}
$Presets = [ordered]@{
  'Competitif' = @{ W = 1280; H = 720;  Dpi = 240; Label = 'Competitif 720p' }
  'Equilibre'  = @{ W = 1600; H = 900;  Dpi = 240; Label = 'Equilibre 900p' }
  'Qualite'    = @{ W = 1920; H = 1080; Dpi = 320; Label = 'Qualite 1080p' }
  'Ipad720'    = @{ W = 960;  H = 720;  Dpi = 240; Label = 'Vue iPad 720' }
  'Ipad1080'   = @{ W = 1440; H = 1080; Dpi = 320; Label = 'Vue iPad 1080' }
  'Ipad2K'     = @{ W = 1920; H = 1440; Dpi = 320; Label = 'Vue iPad 2K' }
}

# ---------------- Keymap par taille ----------------
# GameLoop garde les keymaps personnalisees dans %APPDATA%\AndroidTbox\TVM_*.xml.
# L'outil en garde une copie par taille d'ecran et remet la bonne copie quand la taille change.
$KeymapLive = Join-Path $env:APPDATA 'AndroidTbox'
function Get-LiveKeymapFiles {
  if (-not (Test-Path $KeymapLive)) { return @() }
  @(Get-ChildItem $KeymapLive -Filter 'TVM_*.xml' -File -ErrorAction SilentlyContinue)
}
function Get-SizeKey { "{0}x{1}" -f $ui.tbW.Text.Trim(), $ui.tbH.Text.Trim() }
function Get-SizeDir([string]$size) { Join-Path $Dirs.Keymaps $size }
function Save-KeymapForSize {
  $size = Get-SizeKey
  if ($size -notmatch '^\d{3,5}x\d{3,5}$') { Info 'Indiquez d''abord une largeur et une hauteur.'; return }
  $files = Get-LiveKeymapFiles
  if (-not $files) { Info "Aucune keymap GameLoop trouvee dans $KeymapLive.`nOuvrez PUBG une fois dans GameLoop et reglez vos touches, puis reessayez." 'Warning'; return }
  $dir = Get-SizeDir $size
  if ((Test-Path $dir) -and -not (Ask "Une keymap est deja associee a $size. La remplacer ?")) { return }
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  Get-ChildItem $dir -File | Remove-Item
  foreach ($f in $files) { Copy-Item -LiteralPath $f.FullName -Destination $dir }
  @{ Size = $size; Saved = (Get-Date).ToString('s'); Files = @($files | ForEach-Object { $_.Name }) } | ConvertTo-Json | Set-Content (Join-Path $dir 'info.json') -Encoding UTF8
  Log "Keymap actuelle associee a la taille $size ($($files.Count) fichier(s))."
  Refresh-KeymapPanel
}
function Restore-KeymapForSize([string]$size, [bool]$quiet = $false) {
  $dir = Get-SizeDir $size
  $saved = @(Get-ChildItem $dir -Filter 'TVM_*.xml' -File -ErrorAction SilentlyContinue)
  if (-not $saved) { if (-not $quiet) { Info "Aucune keymap associee a $size." }; return $false }
  if (Test-GameLoopRunning) { Info 'Fermez GameLoop avant de changer de keymap.' 'Warning'; return $false }
  New-Item -ItemType Directory -Force -Path $KeymapLive | Out-Null
  $bak = Join-Path $Dirs.Keymaps ("_avant-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
  New-Item -ItemType Directory -Force -Path $bak | Out-Null
  foreach ($f in Get-LiveKeymapFiles) { Copy-Item -LiteralPath $f.FullName -Destination $bak }
  foreach ($f in $saved) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $KeymapLive $f.Name) -Force }
  Log "Keymap de la taille $size remise en place (ancienne copie : $(Split-Path $bak -Leaf))."
  $true
}
function Refresh-KeymapPanel {
  $size = Get-SizeKey
  $info = Join-Path (Get-SizeDir $size) 'info.json'
  if (Test-Path $info) {
    $i = Get-Content $info -Raw -Encoding UTF8 | ConvertFrom-Json
    $ui.tbKmState.Text = "Taille $size : keymap associee le $($i.Saved -replace 'T', ' a ')"
    $ui.tbKmState.Foreground = '#0E7C66'
  } else {
    $ui.tbKmState.Text = "Taille $size : aucune keymap associee"
    $ui.tbKmState.Foreground = '#B45309'
  }
  $ui.lbKmSizes.Items.Clear()
  Get-ChildItem $Dirs.Keymaps -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+x\d+$' } |
    ForEach-Object { [void]$ui.lbKmSizes.Items.Add($_.Name) }
  $ui.tbKmLive.Text = if (Get-LiveKeymapFiles) { "Keymaps GameLoop : $KeymapLive" } else { "Keymaps GameLoop introuvables ($KeymapLive)" }
}

# ---------------- Interface (une seule vue) ----------------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PUBG GL Expert" Width="1200" Height="780" MinWidth="1060" MinHeight="700"
        WindowStartupLocation="CenterScreen" Background="#F4F5F7" FontFamily="Segoe UI" FontSize="13" Foreground="#1F2937">
  <Window.Resources>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Background" Value="White"/><Setter Property="Foreground" Value="#1F2937"/>
      <Setter Property="BorderBrush" Value="#D5D9DF"/><Setter Property="Padding" Value="12,7"/>
      <Setter Property="Margin" Value="0,0,8,8"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                  BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#0E7C66"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#0E7C66"/><Setter Property="Foreground" Value="White"/><Setter Property="BorderBrush" Value="#0E7C66"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="Card" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Width" Value="168"/><Setter Property="Height" Value="74"/><Setter Property="Padding" Value="12,8"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
    </Style>
    <Style x:Key="Panel" TargetType="Border">
      <Setter Property="Background" Value="White"/><Setter Property="CornerRadius" Value="12"/>
      <Setter Property="BorderBrush" Value="#E5E7EB"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="16,14"/><Setter Property="Margin" Value="0,0,0,12"/>
    </Style>
    <Style x:Key="H2" TargetType="TextBlock"><Setter Property="FontSize" Value="14"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Margin" Value="0,0,0,8"/></Style>
    <Style x:Key="Muted" TargetType="TextBlock"><Setter Property="Foreground" Value="#6B7280"/><Setter Property="TextWrapping" Value="Wrap"/><Setter Property="FontSize" Value="12"/></Style>
    <Style x:Key="Lbl" TargetType="TextBlock"><Setter Property="Foreground" Value="#4B5563"/><Setter Property="Margin" Value="0,0,0,3"/><Setter Property="FontSize" Value="12"/></Style>
    <Style TargetType="TextBox"><Setter Property="Padding" Value="6,5"/><Setter Property="BorderBrush" Value="#D5D9DF"/><Setter Property="MinWidth" Value="72"/></Style>
    <Style TargetType="ComboBox"><Setter Property="Padding" Value="6,5"/><Setter Property="MinWidth" Value="110"/></Style>
    <Style TargetType="ListBox"><Setter Property="BorderBrush" Value="#E5E7EB"/></Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="96"/></Grid.RowDefinitions>

    <!-- Barre du haut -->
    <Border Background="#151B21" Padding="20,12">
      <DockPanel>
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="Version de PUBG" Foreground="#9CA3AF" VerticalAlignment="Center" Margin="0,0,8,0"/>
          <ComboBox x:Name="cbBuild" MinWidth="150" Margin="0,0,10,0"/>
          <Button x:Name="btnMonitor" Style="{StaticResource Primary}" Content="Metrics" Margin="0,0,10,0" ToolTip="Reduit PUBG GL Expert et affiche un petit moniteur GPU / CPU en temps reel"/>
          <Button x:Name="btnChooseFolder" Style="{StaticResource Btn}" Content="Dossier GameLoop" Margin="0"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="PUBG GL Expert" Foreground="White" FontSize="20" FontWeight="Bold" VerticalAlignment="Center"/>
          <TextBlock x:Name="tbVersion" Foreground="#7C8896" FontSize="11" VerticalAlignment="Bottom" Margin="8,0,24,3"/>
          <Ellipse x:Name="dotInstall" Width="9" Height="9" Fill="#6B7280" Margin="0,0,6,0"/><TextBlock x:Name="tbInstall" Foreground="#D1D5DB" VerticalAlignment="Center" Margin="0,0,18,0"/>
          <Ellipse x:Name="dotRun" Width="9" Height="9" Fill="#6B7280" Margin="0,0,6,0"/><TextBlock x:Name="tbRun" Foreground="#D1D5DB" VerticalAlignment="Center" Margin="0,0,18,0"/>
          <Ellipse x:Name="dotAdb" Width="9" Height="9" Fill="#6B7280" Margin="0,0,6,0"/><TextBlock x:Name="tbAdb" Foreground="#D1D5DB" VerticalAlignment="Center"/>
        </StackPanel>
      </DockPanel>
    </Border>

    <Grid Grid.Row="1" Margin="18,14,18,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="1.35*"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

      <!-- Colonne gauche : reglages -->
      <ScrollViewer VerticalScrollBarVisibility="Auto">
        <StackPanel>
          <Border Style="{StaticResource Panel}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="Préréglages"/>
              <TextBlock x:Name="tbReco" Style="{StaticResource Muted}" Margin="0,0,0,8"/>
              <WrapPanel>
                <Button x:Name="btnPresetCompetitif" Style="{StaticResource Card}"><StackPanel><TextBlock Text="Competitif" FontWeight="SemiBold"/><TextBlock Text="1280 x 720 - 16:9" Foreground="#6B7280" FontSize="12"/><TextBlock x:Name="recCompetitif" Text="Conseille pour ce PC" Foreground="#0E7C66" FontSize="11" FontWeight="SemiBold" Visibility="Collapsed"/></StackPanel></Button>
                <Button x:Name="btnPresetEquilibre" Style="{StaticResource Card}"><StackPanel><TextBlock Text="Equilibre" FontWeight="SemiBold"/><TextBlock Text="1600 x 900 - 16:9" Foreground="#6B7280" FontSize="12"/><TextBlock x:Name="recEquilibre" Text="Conseille pour ce PC" Foreground="#0E7C66" FontSize="11" FontWeight="SemiBold" Visibility="Collapsed"/></StackPanel></Button>
                <Button x:Name="btnPresetQualite" Style="{StaticResource Card}"><StackPanel><TextBlock Text="Qualite" FontWeight="SemiBold"/><TextBlock Text="1920 x 1080 - 16:9" Foreground="#6B7280" FontSize="12"/><TextBlock x:Name="recQualite" Text="Conseille pour ce PC" Foreground="#0E7C66" FontSize="11" FontWeight="SemiBold" Visibility="Collapsed"/></StackPanel></Button>
                <Button x:Name="btnPresetIpad720" Style="{StaticResource Card}"><StackPanel><TextBlock Text="Vue iPad 720" FontWeight="SemiBold"/><TextBlock Text="960 x 720 - 4:3" Foreground="#6B7280" FontSize="12"/></StackPanel></Button>
                <Button x:Name="btnPresetIpad1080" Style="{StaticResource Card}"><StackPanel><TextBlock Text="Vue iPad 1080" FontWeight="SemiBold"/><TextBlock Text="1440 x 1080 - 4:3" Foreground="#6B7280" FontSize="12"/></StackPanel></Button>
                <Button x:Name="btnPresetIpad2K" Style="{StaticResource Card}"><StackPanel><TextBlock Text="Vue iPad 2K" FontWeight="SemiBold"/><TextBlock Text="1920 x 1440 - 4:3" Foreground="#6B7280" FontSize="12"/></StackPanel></Button>
              </WrapPanel>
              <TextBlock Style="{StaticResource Muted}" Text="La vue iPad (4:3) montre plus d'image en hauteur. Un préréglage remplit le formulaire : rien n'est ecrit avant Appliquer."/>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Panel}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="Affichage et FPS"/>
              <WrapPanel>
                <StackPanel Margin="0,0,12,8"><TextBlock Style="{StaticResource Lbl}" Text="Taille"/><ComboBox x:Name="cbRes" MinWidth="190"/></StackPanel>
                <StackPanel Margin="0,0,12,8"><TextBlock Style="{StaticResource Lbl}" Text="Largeur"/><TextBox x:Name="tbW"/></StackPanel>
                <StackPanel Margin="0,0,12,8"><TextBlock Style="{StaticResource Lbl}" Text="Hauteur"/><TextBox x:Name="tbH"/></StackPanel>
                <StackPanel Margin="0,0,12,8"><TextBlock Style="{StaticResource Lbl}" Text="DPI"/><ComboBox x:Name="cbDpi" IsEditable="True" MinWidth="80"/></StackPanel>
                <StackPanel Margin="0,0,0,8" VerticalAlignment="Bottom"><TextBlock x:Name="tbRatio" Style="{StaticResource Muted}" Margin="0,0,0,6"/></StackPanel>
              </WrapPanel>
              <WrapPanel>
                <StackPanel Margin="0,0,12,8"><TextBlock Style="{StaticResource Lbl}" Text="Modele d'appareil"/><ComboBox x:Name="cbDevice" MinWidth="230"/></StackPanel>
                <StackPanel Margin="0,0,12,8"><TextBlock Style="{StaticResource Lbl}" Text="Niveau FPS"/><TextBox x:Name="tbFps"/></StackPanel>
                <StackPanel Margin="0,0,12,8"><TextBlock Style="{StaticResource Lbl}" Text="Qualite"/><TextBox x:Name="tbQuality"/></StackPanel>
                <StackPanel Margin="0,0,0,8"><TextBlock Style="{StaticResource Lbl}" Text="FXAA"/><TextBox x:Name="tbFxaa"/></StackPanel>
              </WrapPanel>
              <TextBlock x:Name="tbDeviceNow" Style="{StaticResource Muted}" Margin="0,0,0,6"/>
              <WrapPanel Margin="0,0,0,10">
                <CheckBox x:Name="chkShader" Content="Cache de shaders" Margin="0,0,20,0"/>
                <CheckBox x:Name="chkGpu" Content="Carte graphique dediee" Margin="0,0,20,0"/>
                <CheckBox x:Name="chkAutoKm" Content="Mettre la keymap de cette taille" IsChecked="True"/>
              </WrapPanel>
              <WrapPanel>
                <Button x:Name="btnApply" Style="{StaticResource Primary}" Content="Appliquer avec sauvegarde"/>
                <Button x:Name="btnReload" Style="{StaticResource Btn}" Content="Relire les valeurs actuelles"/>
              </WrapPanel>
            </StackPanel>
          </Border>
        </StackPanel>
      </ScrollViewer>

      <!-- Colonne droite : actions -->
      <ScrollViewer Grid.Column="2" VerticalScrollBarVisibility="Auto">
        <StackPanel>
          <Border Style="{StaticResource Panel}" BorderBrush="#0E7C66">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="Optimisation en un clic"/>
              <CheckBox x:Name="optModel"    IsChecked="True" Margin="0,2" Content="Modele d'appareil Samsung SM-X910"/>
              <CheckBox x:Name="optProcs"    IsChecked="True" Margin="0,2" Content="Fermer les processus GameLoop secondaires"/>
              <CheckBox x:Name="optShortcut" IsChecked="True" Margin="0,2" Content="Raccourci bureau AndroidEmulatorEn.exe -vm 100"/>
              <CheckBox x:Name="optPriority" IsChecked="True" Margin="0,2" Content="Priorite haute (AppMarket, emulateur, aow_exe)"/>
              <CheckBox x:Name="optAffinity" IsChecked="False" Margin="0,2" Content="Affinite CPU : laisser 2 coeurs a Windows"/>
              <CheckBox x:Name="optTemp"     IsChecked="True" Margin="0,2,0,8" Content="Nettoyer les fichiers temporaires (temp, %temp%, prefetch)"/>
              <WrapPanel>
                <Button x:Name="btnOptimize" Style="{StaticResource Primary}" Content="Optimiser"/>
              </WrapPanel>
              <TextBlock Style="{StaticResource Lbl}" Margin="0,4,0,4" Text="Reglages Windows (a faire a la main, reversibles)"/>
              <WrapPanel>
                <Button x:Name="btnWinPagefile" Style="{StaticResource Btn}" Content="Memoire virtuelle"/>
                <Button x:Name="btnWinUpdate"   Style="{StaticResource Btn}" Content="Windows Update"/>
                <Button x:Name="btnWinDrivers"  Style="{StaticResource Btn}" Content="Pilotes auto"/>
                <Button x:Name="btnGpuDriver"   Style="{StaticResource Btn}" Content="Pilote GPU"/>
              </WrapPanel>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Panel}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="Lancer"/>
              <WrapPanel>
                <Button x:Name="btnGameMode" Style="{StaticResource Btn}" Content="Mode jeu" ToolTip="Fermer les applications non Windows avant de jouer (vous choisissez lesquelles)"/>
                <Button x:Name="btnLaunchGame" Style="{StaticResource Primary}" Content="Lancer PUBG"/>
                <Button x:Name="btnLaunchStore" Style="{StaticResource Btn}" Content="Play Store"/>
                <Button x:Name="btnCloseAll" Style="{StaticResource Btn}" Content="Tout fermer" Foreground="#B91C1C" ToolTip="Ferme PUBG, GameLoop (AppMarket) et tous leurs processus"/>
                <Button x:Name="btnDetect" Style="{StaticResource Btn}" Content="Detecter les versions"/>
              </WrapPanel>
              <TextBlock x:Name="tbInstalled" Style="{StaticResource Muted}" Text="Le lancement passe par GameLoop (sans ADB). La detection des versions demande l'ADB."/>
              <WrapPanel Margin="0,10,0,0">
                <Button x:Name="btnInstallOld" Style="{StaticResource Primary}" Content="Installer l'ancien GameLoop" ToolTip="Installe l'ancien GameLoop (GLP_installer.exe) avec les protections contre la migration et le demarrage auto"/>
                <Button x:Name="btnUpdBlock" Style="{StaticResource Btn}" Content="Bloquer les MAJ GameLoop" ToolTip="Empeche GameLoop de se mettre a jour (reversible)"/>
                <Button x:Name="btnStartBlock" Style="{StaticResource Btn}" Content="Bloquer GameLoop au demarrage" ToolTip="Empeche GameLoop de se lancer tout seul au demarrage du PC (reversible)"/>
              </WrapPanel>
              <TextBlock x:Name="tbUpdState" Style="{StaticResource Muted}"/>
              <TextBlock x:Name="tbStartState" Style="{StaticResource Muted}"/>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Panel}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="Keymap par taille d'ecran"/>
              <TextBlock x:Name="tbKmState" FontWeight="SemiBold" Margin="0,0,0,6"/>
              <WrapPanel>
                <Button x:Name="btnKmSave" Style="{StaticResource Primary}" Content="Associer la keymap actuelle"/>
                <Button x:Name="btnKmRestore" Style="{StaticResource Btn}" Content="Remettre celle de cette taille"/>
              </WrapPanel>
              <TextBlock Style="{StaticResource Lbl}" Text="Tailles deja associees"/>
              <ListBox x:Name="lbKmSizes" Height="64"/>
              <TextBlock x:Name="tbKmLive" Style="{StaticResource Muted}" Margin="0,6,0,0"/>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Panel}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="Profils et sauvegardes"/>
              <WrapPanel>
                <ComboBox x:Name="cbProfiles" MinWidth="170" Margin="0,0,8,8"/>
                <Button x:Name="btnProfLoad" Style="{StaticResource Btn}" Content="Charger"/>
                <Button x:Name="btnProfDelete" Style="{StaticResource Btn}" Content="Supprimer"/>
              </WrapPanel>
              <WrapPanel>
                <TextBox x:Name="tbProfileName" MinWidth="170" Margin="0,0,8,8"/>
                <Button x:Name="btnProfSave" Style="{StaticResource Btn}" Content="Enregistrer le formulaire"/>
              </WrapPanel>
              <WrapPanel>
                <ComboBox x:Name="cbBackups" MinWidth="170" Margin="0,0,8,8"/>
                <Button x:Name="btnRestore" Style="{StaticResource Btn}" Content="Restaurer"/>
                <Button x:Name="btnBackupNow" Style="{StaticResource Btn}" Content="Sauvegarder"/>
                <Button x:Name="btnOpenFolder" Style="{StaticResource Btn}" Content="Dossier"/>
              </WrapPanel>
            </StackPanel>
          </Border>
        </StackPanel>
      </ScrollViewer>
    </Grid>

    <!-- Journal -->
    <Border Grid.Row="2" Background="#151B21" Padding="14,8">
      <TextBox x:Name="tbLog" IsReadOnly="True" TextWrapping="Wrap" BorderThickness="0" Background="#151B21" Foreground="#C8D0D8"
               VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="12"/>
    </Border>
  </Grid>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
$xaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object {
  $n = $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
  if ($n) { $ui[$n] = $win.FindName($n) }
}
$script:LogBox = $ui.tbLog
$script:Front = $win
$ui.tbVersion.Text = "v$AppVersion · developed by TNL YORYO"

$Resolutions = [ordered]@{
  '1280 x 720 (16:9)'        = @(1280, 720)
  '1600 x 900 (16:9)'        = @(1600, 900)
  '1920 x 1080 (16:9)'       = @(1920, 1080)
  '2560 x 1440 (16:9)'       = @(2560, 1440)
  '960 x 720 (iPad 4:3)'     = @(960, 720)
  '1440 x 1080 (iPad 4:3)'   = @(1440, 1080)
  '1920 x 1440 (iPad 4:3)'   = @(1920, 1440)
  'Personnalisee'            = $null
}
$Builds.Keys      | ForEach-Object { [void]$ui.cbBuild.Items.Add($_) }
$Resolutions.Keys | ForEach-Object { [void]$ui.cbRes.Items.Add($_) }
160, 240, 280, 320, 480 | ForEach-Object { [void]$ui.cbDpi.Items.Add([string]$_) }
[void]$ui.cbDevice.Items.Add('(ne pas changer)')
$Devices.Keys | ForEach-Object { [void]$ui.cbDevice.Items.Add($_) }
$ui.cbBuild.SelectedIndex = 0

function Current-Pkg { $Builds[[string]$ui.cbBuild.SelectedItem] }
function Set-Dot($dot, $label, [bool]$ok, [string]$text) {
  $ui[$dot].Fill = if ($ok) { '#22C55E' } else { '#EF4444' }
  $ui[$label].Text = $text
}
function Update-Status {
  Set-Dot 'dotInstall' 'tbInstall' ([bool]$GameLoopUi) $(if ($GameLoopUi) { 'GameLoop installe' } else { 'GameLoop introuvable' })
  $run = Test-GameLoopRunning
  Set-Dot 'dotRun' 'tbRun' $run $(if ($run) { 'Emulateur ouvert' } else { 'Emulateur ferme' })
  if ($ui.tbAdb.Text -eq '') { $ui.dotAdb.Fill = '#6B7280'; $ui.tbAdb.Text = 'ADB non verifie' }
}
function Update-Ratio {
  $w = 0; $h = 0
  if ([int]::TryParse($ui.tbW.Text, [ref]$w) -and [int]::TryParse($ui.tbH.Text, [ref]$h) -and $h -gt 0) {
    $r = $w / $h
    $ui.tbRatio.Text = if ([math]::Abs($r - 4/3) -lt 0.02) { 'Format 4:3 (vue iPad)' } elseif ([math]::Abs($r - 16/9) -lt 0.02) { 'Format 16:9' } elseif ([math]::Abs($r - 16/10) -lt 0.02) { 'Format 16:10' } else { "Format {0:N2}:1" -f $r }
  } else { $ui.tbRatio.Text = '' }
  Refresh-KeymapPanel
}

function Load-Current {
  $pkg = Current-Pkg
  $w = Get-RegValue 'VMResWidth'; $h = Get-RegValue 'VMResHeight'; $d = Get-RegValue 'VMDPI'
  $script:Loading = $true
  $ui.tbW.Text   = if ($w) { [string]$w.Value } else { '' }
  $ui.tbH.Text   = if ($h) { [string]$h.Value } else { '' }
  $ui.cbDpi.Text = if ($d) { [string]$d.Value } else { '' }
  $sel = 'Personnalisee'
  foreach ($k in $Resolutions.Keys) {
    $r = $Resolutions[$k]
    if ($r -and $w -and $h -and $r[0] -eq [int]$w.Value -and $r[1] -eq [int]$h.Value) { $sel = $k }
  }
  $ui.cbRes.SelectedItem = $sel
  $script:Loading = $false
  $m = Get-RegValue 'VMDeviceModel'
  $ui.tbDeviceNow.Text = if ($m) { "Modele actuel : $($m.Value)" } else { 'Modele actuel : non defini' }
  $ui.cbDevice.SelectedIndex = 0
  $f = Get-RegValue "${pkg}_FPSLevel"; $q = Get-RegValue "${pkg}_RenderQuality"; $x = Get-RegValue 'FxaaQuality'
  $ui.tbFps.Text     = if ($f) { [string]$f.Value } else { '' }
  $ui.tbQuality.Text = if ($q) { [string]$q.Value } else { '' }
  $ui.tbFxaa.Text    = if ($x) { [string]$x.Value } else { '' }
  $s = Get-RegValue 'ShaderCacheEnabled'; $g = Get-RegValue 'GraphicsCardEnabled'
  $ui.chkShader.IsChecked = [bool]($s -and [int]$s.Value -ne 0)
  $ui.chkGpu.IsChecked    = [bool]($g -and [int]$g.Value -ne 0)
  Update-Ratio
}

function Apply-Preset([string]$name) {
  $p = $Presets[$name]
  $script:Loading = $true
  $ui.tbW.Text = [string]$p.W; $ui.tbH.Text = [string]$p.H; $ui.cbDpi.Text = [string]$p.Dpi
  $match = $Resolutions.Keys | Where-Object { $Resolutions[$_] -and $Resolutions[$_][0] -eq $p.W -and $Resolutions[$_][1] -eq $p.H } | Select-Object -First 1
  $ui.cbRes.SelectedItem = if ($match) { $match } else { 'Personnalisee' }
  $script:Loading = $false
  if ($TopDevice) { $ui.cbDevice.SelectedItem = $TopDevice }
  $ui.chkShader.IsChecked = $true; $ui.chkGpu.IsChecked = $true
  Update-Ratio
  Log "Préréglage $($p.Label) charge dans le formulaire (pas encore applique)."
}

function Get-FormSettings {
  $pkg = Current-Pkg
  $s = [ordered]@{}
  if ($ui.tbW.Text.Trim())   { $s['VMResWidth']  = $ui.tbW.Text.Trim() }
  if ($ui.tbH.Text.Trim())   { $s['VMResHeight'] = $ui.tbH.Text.Trim() }
  if ($ui.cbDpi.Text.Trim()) { $s['VMDPI']       = $ui.cbDpi.Text.Trim() }
  if ($ui.cbDevice.SelectedIndex -gt 0) {
    $dv = Resolve-DeviceValues ([string]$ui.cbDevice.SelectedItem)
    foreach ($k in $dv.Keys) { if ($dv[$k]) { $s[$k] = $dv[$k] } }
  }
  if ($ui.tbFps.Text.Trim())     { $s["${pkg}_FPSLevel"]      = $ui.tbFps.Text.Trim() }
  if ($ui.tbQuality.Text.Trim()) { $s["${pkg}_RenderQuality"] = $ui.tbQuality.Text.Trim() }
  if ($ui.tbFxaa.Text.Trim())    { $s['FxaaQuality']          = $ui.tbFxaa.Text.Trim() }
  $s['ShaderCacheEnabled']  = [int][bool]$ui.chkShader.IsChecked
  $s['GraphicsCardEnabled'] = [int][bool]$ui.chkGpu.IsChecked
  $s
}

function Apply-Settings($settings) {
  if (Test-GameLoopRunning) { Info "Fermez completement GameLoop avant d'appliquer (sinon il peut reecrire ses reglages en quittant)." 'Warning'; return }
  if (-not (Test-Path $RegPath)) { Info "La cle $RegNative est absente. Lancez GameLoop une fois sur ce PC, puis reessayez." 'Warning'; return }
  foreach ($n in @('VMResWidth','VMResHeight','VMDPI')) {
    if ($settings.Contains($n) -and $settings[$n] -notmatch '^\d{2,5}$') { Info "Valeur invalide pour $n : $($settings[$n])" 'Warning'; return }
  }
  $plan = @(); $skipped = @()
  foreach ($n in @($settings.Keys)) {
    if ($n -notmatch $Allowed -or $n -match $Forbidden) { $skipped += "$n (hors liste blanche)"; continue }
    $cur = Get-RegValue $n
    if (-not $cur) { $skipped += "$n (absent du registre, non cree)"; continue }
    try { $new = Convert-ForKind $settings[$n] $cur.Kind } catch { $skipped += "$n ($($_.Exception.Message))"; continue }
    if ([string]$cur.Value -ne [string]$new) { $plan += [pscustomobject]@{ Name = $n; Old = $cur.Value; New = $new; Kind = $cur.Kind } }
  }
  $size = Get-SizeKey
  $kmPlanned = [bool]$ui.chkAutoKm.IsChecked -and (Test-Path (Join-Path (Get-SizeDir $size) 'info.json'))
  if ($plan.Count -eq 0 -and -not $kmPlanned) {
    $msg = 'Aucun changement a appliquer.'
    if ($skipped) { $msg += "`n`nIgnore :`n - " + ($skipped -join "`n - ") }
    Info $msg; return
  }
  $preview = if ($plan) { ($plan | ForEach-Object { " - $($_.Name) : $($_.Old)  ->  $($_.New)" }) -join "`n" } else { ' - (aucun reglage du registre)' }
  if ($kmPlanned) { $preview += "`n - Keymap : celle associee a $size" }
  if ($skipped) { $preview += "`n`nIgnore :`n - " + ($skipped -join "`n - ") }
  if (-not (Ask "Changements prevus (une sauvegarde est faite avant) :`n`n$preview`n`nContinuer ?")) { Log 'Application annulee.'; return }
  if ($plan) {
    Backup-Registry 'avant-application' | Out-Null
    foreach ($p in $plan) {
      Set-ItemProperty -Path $RegPath -Name $p.Name -Value $p.New -Type $p.Kind
      Log "Ecrit $($p.Name) = $($p.New)"
    }
  }
  if ($kmPlanned) { [void](Restore-KeymapForSize $size $true) }
  elseif ($ui.chkAutoKm.IsChecked) { Log "Aucune keymap associee a $size : la keymap actuelle reste en place." }
  Info 'Reglages appliques. Lancez GameLoop pour les voir.'
  Refresh-Backups
}

# ---------------- Profils ----------------
function Refresh-Profiles {
  $ui.cbProfiles.Items.Clear()
  Get-ChildItem $Dirs.Profiles -Filter '*.json' | ForEach-Object { [void]$ui.cbProfiles.Items.Add($_.BaseName) }
  if ($ui.cbProfiles.Items.Count) { $ui.cbProfiles.SelectedIndex = 0 }
}
function Save-Profile {
  $name = $ui.tbProfileName.Text.Trim()
  if ($name -notmatch '^[\w \-\.]{1,50}$') { Info 'Nom de profil invalide (lettres, chiffres, espace, - . _).'; return }
  $p = [ordered]@{
    Build = [string]$ui.cbBuild.SelectedItem; Width = $ui.tbW.Text; Height = $ui.tbH.Text; Dpi = $ui.cbDpi.Text
    Device = [string]$ui.cbDevice.SelectedItem; FpsLevel = $ui.tbFps.Text; RenderQuality = $ui.tbQuality.Text
    Fxaa = $ui.tbFxaa.Text; ShaderCache = [bool]$ui.chkShader.IsChecked; DedicatedGpu = [bool]$ui.chkGpu.IsChecked
  }
  $p | ConvertTo-Json | Set-Content (Join-Path $Dirs.Profiles "$name.json") -Encoding UTF8
  Log "Profil enregistre : $name"; Refresh-Profiles; $ui.cbProfiles.SelectedItem = $name
}
function Load-Profile {
  $name = [string]$ui.cbProfiles.SelectedItem
  if (-not $name) { Info 'Aucun profil.'; return }
  $p = Get-Content (Join-Path $Dirs.Profiles "$name.json") -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($Builds.Contains([string]$p.Build)) { $ui.cbBuild.SelectedItem = [string]$p.Build }
  $script:Loading = $true
  $ui.tbW.Text = $p.Width; $ui.tbH.Text = $p.Height; $ui.cbDpi.Text = $p.Dpi
  $ui.cbRes.SelectedItem = 'Personnalisee'
  $script:Loading = $false
  if ($ui.cbDevice.Items.Contains([string]$p.Device)) { $ui.cbDevice.SelectedItem = [string]$p.Device } else { $ui.cbDevice.SelectedIndex = 0 }
  $ui.tbFps.Text = $p.FpsLevel; $ui.tbQuality.Text = $p.RenderQuality; $ui.tbFxaa.Text = $p.Fxaa
  $ui.chkShader.IsChecked = [bool]$p.ShaderCache; $ui.chkGpu.IsChecked = [bool]$p.DedicatedGpu
  $ui.tbProfileName.Text = $name
  Update-Ratio
  Log "Profil charge : $name (pas encore applique)."
}
function Delete-Profile {
  $name = [string]$ui.cbProfiles.SelectedItem
  if (-not $name) { return }
  if (Ask "Supprimer le profil $name ?") { Remove-Item (Join-Path $Dirs.Profiles "$name.json"); Log "Profil supprime : $name"; Refresh-Profiles }
}

# ---------------- Sauvegardes du registre ----------------
function Refresh-Backups {
  $ui.cbBackups.Items.Clear()
  Get-ChildItem $Dirs.Backups -Filter 'reg-*.reg' | Sort-Object Name -Descending | ForEach-Object { [void]$ui.cbBackups.Items.Add($_.Name) }
  if ($ui.cbBackups.Items.Count) { $ui.cbBackups.SelectedIndex = 0 }
}
function Restore-Backup {
  $name = [string]$ui.cbBackups.SelectedItem
  if (-not $name) { Info 'Aucune sauvegarde.'; return }
  if (Test-GameLoopRunning) { Info 'Fermez GameLoop avant de restaurer.' 'Warning'; return }
  $file = Join-Path $Dirs.Backups $name
  $content = Get-Content $file -Raw
  $keys = [regex]::Matches($content, '(?m)^\[([^\]]+)\]') | ForEach-Object { $_.Groups[1].Value }
  if ($keys | Where-Object { $_ -notmatch '^HKEY_CURRENT_USER\\Software\\Tencent\\MobileGamePC' }) {
    Info 'Ce fichier contient d''autres cles que MobileGamePC : restauration refusee.' 'Error'; return
  }
  if (-not (Ask "Restaurer $name ?`nL'etat actuel sera sauvegarde avant.")) { return }
  Backup-Registry 'avant-restauration' | Out-Null
  $p = Start-Process reg.exe -ArgumentList @('import', "`"$file`"") -Wait -PassThru -WindowStyle Hidden
  if ($p.ExitCode -eq 0) { Log "Restaure : $name"; Info 'Sauvegarde restauree.'; Load-Current } else { Info "Echec de reg import (code $($p.ExitCode))." 'Error' }
  Refresh-Backups
}


# ---------------- Optimisation en un clic ----------------
# Processus indispensables (jamais fermes) et tout ce qui touche a la securite du jeu (jamais touche).
$EssentialProcs = 'AndroidEmulator','AndroidEmulatorEn','AndroidEmulatorEx','AndroidRenderer','AppMarket','aow_exe','QMEmulatorService','adb'
$ProtectedProcs = 'tersafe|tp3|ano|tss|mgdetector|tencentdl|cef_frame|qqexternal'
$PriorityProcs  = 'AppMarket','AndroidEmulatorEx','AndroidEmulatorEn','aow_exe'

function Get-GameLoopRoot {
  if ($GameLoopUi) { return (Split-Path $GameLoopUi -Parent) }
  # AppMarket installe mais emulateur (ui) pas encore telecharge
  foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if ($pf -and (Test-Path -LiteralPath (Join-Path $pf 'TxGameAssistant\AppMarket\AppMarket.exe'))) { return (Join-Path $pf 'TxGameAssistant') }
  }
  $null
}

function Get-SecondaryGameLoopProcs {
  $root = Get-GameLoopRoot
  if (-not $root) { return @() }
  @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
      $path = $null; try { $path = $_.Path } catch { }
      $path -and $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -and
      ($EssentialProcs -notcontains $_.ProcessName) -and ($_.ProcessName -notmatch $ProtectedProcs)
  })
}

function Set-ModelSMX910 {
  # GameLoop stocke le modele soit sous son nom de liste, soit sous ro.product.model.
  $cur = Get-RegValue 'VMDeviceModel'
  if (-not $cur) { return 'Modele : valeur VMDeviceModel absente, a choisir dans GameLoop > Parametres > Modele.' }
  $wanted = $null
  foreach ($k in $Devices.Keys) {
    if ($k -match 'SM-X910|Tab S9 Ultra' -or [string]$Devices[$k].'ro.product.model' -match 'SM-X910') { $wanted = $k }
  }
  if ($wanted) {
    $dv = Resolve-DeviceValues $wanted
    $plan = @{ VMDeviceModel = $dv.VMDeviceModel; VMDeviceManufacturer = $dv.VMDeviceManufacturer }
  } else {
    $usesProp = $false
    foreach ($k in $Devices.Keys) { if ([string]$cur.Value -eq [string]$Devices[$k].'ro.product.model') { $usesProp = $true } }
    if (-not $usesProp) { return "Modele : SM-X910 n'est pas dans la liste de GameLoop sur ce PC. Choisissez-le dans GameLoop > Parametres > Modele (et cliquez Annuler si GameLoop propose ASUS_I001DA)." }
    $plan = @{ VMDeviceModel = 'SM-X910'; VMDeviceManufacturer = 'samsung' }
  }
  $done = @()
  foreach ($n in $plan.Keys) {
    $c = Get-RegValue $n
    if (-not $c) { continue }
    $new = Convert-ForKind $plan[$n] $c.Kind
    if ([string]$c.Value -ne [string]$new) { Set-ItemProperty -Path $RegPath -Name $n -Value $new -Type $c.Kind; $done += "$n=$new" }
  }
  if ($done) { "Modele : " + ($done -join ', ') } else { 'Modele : deja SM-X910.' }
}

function New-VmShortcut {
  $exe = Join-Path $GameLoopUi 'AndroidEmulatorEn.exe'
  if (-not (Test-Path $exe)) { $exe = Join-Path $GameLoopUi 'AndroidEmulatorEx.exe' }
  if (-not (Test-Path $exe)) { return 'Raccourci : AndroidEmulatorEn.exe introuvable.' }
  $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'GameLoop PUBG (vm 100).lnk'
  $sh = New-Object -ComObject WScript.Shell
  $sc = $sh.CreateShortcut($lnk)
  $sc.TargetPath = $exe
  $sc.Arguments = '-vm 100'
  $sc.WorkingDirectory = $GameLoopUi
  $sc.IconLocation = "$exe,0"
  $sc.Description = 'GameLoop lance directement sur la machine virtuelle 100 (cree par PUBG GL Expert)'
  $sc.Save()
  "Raccourci : $lnk ($(Split-Path $exe -Leaf) -vm 100). Supprimez-le pour annuler."
}

function Set-ProcessBoost([bool]$affinity) {
  $out = @()
  $n = [Environment]::ProcessorCount
  $mask = $null
  if ($affinity -and $n -gt 4) { $all = [int64]([math]::Pow(2, $n) - 1); $mask = [IntPtr]($all -band (-bnot [int64]3)) }
  foreach ($p in @(Get-Process -Name $PriorityProcs -ErrorAction SilentlyContinue)) {
    try {
      $p.PriorityClass = 'High'
      if ($mask) { $p.ProcessorAffinity = $mask }
      $out += $p.ProcessName
    } catch { Log "  priorite impossible pour $($p.ProcessName) : $($_.Exception.Message)" }
  }
  if (-not $out) { return 'Priorite : aucun processus GameLoop ouvert (lancez GameLoop puis recliquez Optimiser).' }
  $txt = "Priorite haute : " + (($out | Sort-Object -Unique) -join ', ')
  if ($mask) { $txt += " ; coeurs 0-1 laisses a Windows ($n coeurs logiques)" }
  "$txt (temporaire : revient a la normale quand GameLoop redemarre)."
}

function Clear-TempFiles {
  $dirs = @($env:TEMP, (Join-Path $env:WINDIR 'Temp'), (Join-Path $env:WINDIR 'Prefetch'))
  $freed = 0; $count = 0; $denied = @()
  foreach ($d in $dirs | Select-Object -Unique) {
    if (-not (Test-Path $d)) { continue }
    $items = @(Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue)
    if (-not $items -and -not (Test-Path $d -PathType Container)) { continue }
    try { [void](Get-ChildItem -LiteralPath $d -ErrorAction Stop | Select-Object -First 1) } catch { $denied += $d; continue }
    foreach ($i in $items) {
      if ($i.FullName -match '\\PubgSetup') { continue }
      $size = 0
      try { $size = if ($i.PSIsContainer) { (Get-ChildItem -LiteralPath $i.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } else { $i.Length } } catch { }
      try { Remove-Item -LiteralPath $i.FullName -Recurse -Force -ErrorAction Stop; $freed += [int64]$size; $count++ } catch { }
    }
  }
  $txt = "Nettoyage : $count element(s), {0:N0} Mo liberes (les fichiers en cours d'utilisation sont ignores)." -f ($freed / 1MB)
  if ($denied) { $txt += " Acces refuse (lancez PUBG GL Expert en administrateur pour eux) : " + ($denied -join ', ') }
  $txt
}

function Invoke-Optimize {
  if (-not $GameLoopUi) { Info "GameLoop introuvable : choisissez d'abord son dossier." 'Warning'; return }
  $steps = @()
  if ($ui.optModel.IsChecked)    { $steps += '- Modele d''appareil Samsung SM-X910 (sauvegarde du registre avant)' }
  if ($ui.optProcs.IsChecked) {
    $sec = Get-SecondaryGameLoopProcs
    $names = if ($sec) { (($sec | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', ') } else { 'aucun ouvert' }
    $steps += "- Fermer les processus GameLoop secondaires : $names"
  }
  if ($ui.optShortcut.IsChecked) { $steps += '- Creer le raccourci bureau AndroidEmulatorEn.exe -vm 100' }
  if ($ui.optPriority.IsChecked) { $steps += '- Priorite haute' + $(if ($ui.optAffinity.IsChecked) { ' + affinite CPU' } else { '' }) }
  if ($ui.optTemp.IsChecked)     { $steps += '- Vider temp, %temp% et prefetch' }
  if (-not $steps) { Info 'Cochez au moins une etape.'; return }
  if (-not (Ask ("PUBG GL Expert va faire :`n`n" + ($steps -join "`n") + "`n`nLes processus anti-triche et les fichiers du jeu ne sont jamais touches.`nContinuer ?"))) { Log 'Optimisation annulee.'; return }

  $report = @()
  if ($ui.optModel.IsChecked) {
    if (Test-GameLoopRunning) { $report += 'Modele : non change, fermez GameLoop puis recliquez Optimiser (GameLoop reecrit ce reglage en quittant).' }
    elseif (-not (Test-Path $RegPath)) { $report += 'Modele : registre GameLoop absent.' }
    else { Backup-Registry 'avant-optimisation' | Out-Null; $report += Set-ModelSMX910 }
  }
  if ($ui.optProcs.IsChecked) {
    $stopped = @()
    foreach ($p in Get-SecondaryGameLoopProcs) { try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; $stopped += $p.ProcessName } catch { Log "  impossible de fermer $($p.ProcessName)" } }
    $report += if ($stopped) { "Processus fermes : " + (($stopped | Sort-Object -Unique) -join ', ') } else { 'Processus : aucun processus secondaire ouvert.' }
  }
  if ($ui.optShortcut.IsChecked) { $report += New-VmShortcut }
  if ($ui.optPriority.IsChecked) { $report += Set-ProcessBoost ([bool]$ui.optAffinity.IsChecked) }
  if ($ui.optTemp.IsChecked)     { $report += Clear-TempFiles }
  $report | ForEach-Object { Log $_ }
  Info ("Optimisation terminee :`n`n" + ($report -join "`n`n"))
  Refresh-Backups; Load-Current; Update-Status
}

function Open-GpuDriverPage {
  $g = (Get-Recommendation).Gpu
  $url = if ($g -match 'NVIDIA|GeForce') { 'https://www.nvidia.com/Download/index.aspx' }
         elseif ($g -match 'AMD|Radeon') { 'https://www.amd.com/en/support/download/drivers.html' }
         elseif ($g -match 'Intel|Arc') { 'https://www.intel.com/content/www/us/en/download-center/home.html' }
         else { 'https://www.nvidia.com/Download/index.aspx' }
  Log "Pilote GPU ($g) : $url"
  Start-Process $url
}

# ---------------- Blocage des mises a jour de GameLoop ----------------
# Constate (analyse des fichiers, 2026-11-21) : AppMarket.exe interroge le serveur de MAJ client
# (.../syzsclient/update/clientupdate) puis lance AppMarket\GF186\TUpdate.exe (-ForceUpdate ...),
# qui telecharge et installe la nouvelle version. Le blocage :
#   1. renomme TUpdate.exe en TUpdate.exe.bloque (reversible) ;
#   2. ajoute une regle du pare-feu Windows qui bloque TUpdate.exe en sortie.
# Ne touche PAS a l'anti-triche (plugins\Updater32.exe), ni au jeu, ni a AppMarket.exe.
# Demande les droits administrateur (UAC) car le dossier est dans Program Files.
$UpdRuleName = 'PubgSetup - Bloquer MAJ GameLoop'
# 2026-11-22 : la migration vers le nouveau GameLoop 7 est passee par PcyybAssistant.exe
# (installateur com_tencent_gameloop_*.exe telecharge dans MobileGamePCShared), pas par TUpdate.
$UpdTargets = @('AppMarket\GF186\TUpdate.exe', 'AppMarket\PcyybAssistant.exe')
# Telechargeurs d'AppMarket : seulement bloques au pare-feu (pas renommes). C'est par eux que
# l'ancien AppMarket a retelecharge l'installateur du nouveau GameLoop le 2026-11-22.
$UpdFwOnly = @('AppMarket\DL\syzs_dl_svr.exe', 'AppMarket\GameDownload.exe')
$UpdSharedDir = 'C:\Temp\TxGameDownload\MobileGamePCShared'
$UpdBlockScript = @'
param([string]$Mode, [string]$Exes, [string]$FwOnly, [string]$Shared, [string]$Out)
$ErrorActionPreference = 'Stop'
$log = @()
try {
  Get-NetFirewallRule -DisplayName 'PubgSetup - Bloquer MAJ GameLoop*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  foreach ($Exe in ($Exes -split '\|')) {
    if (-not $Exe) { continue }
    $name = [IO.Path]::GetFileNameWithoutExtension($Exe)
    $off = "$Exe.bloque"
    Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force
    if ($Mode -eq 'Block') {
      if (Test-Path -LiteralPath $Exe) {
        if (Test-Path -LiteralPath $off) { Remove-Item -LiteralPath $off -Force }
        Rename-Item -LiteralPath $Exe -NewName ([IO.Path]::GetFileName($off))
      }
      New-NetFirewallRule -DisplayName "PubgSetup - Bloquer MAJ GameLoop ($name)" -Group 'PubgSetup' -Direction Outbound -Action Block -Program $Exe -Profile Any | Out-Null
      $log += "bloque : $name"
    } else {
      if ((Test-Path -LiteralPath $off) -and -not (Test-Path -LiteralPath $Exe)) { Rename-Item -LiteralPath $off -NewName ([IO.Path]::GetFileName($Exe)) }
      $log += "autorise : $name"
    }
  }
  if ($Mode -eq 'Block') {
    foreach ($Exe in ($FwOnly -split '\|')) {
      if (-not $Exe) { continue }
      $name = [IO.Path]::GetFileNameWithoutExtension($Exe)
      New-NetFirewallRule -DisplayName "PubgSetup - Bloquer MAJ GameLoop ($name)" -Group 'PubgSetup' -Direction Outbound -Action Block -Program $Exe -Profile Any | Out-Null
      $log += "telechargeur bloque (pare-feu) : $name"
    }
  }
  if ($Shared -and (Test-Path -LiteralPath $Shared)) {
    if ($Mode -eq 'Block') { & icacls.exe $Shared /deny '*S-1-1-0:(OI)(IO)(X)' | Out-Null; $log += "execution interdite dans MobileGamePCShared" }
    else { & icacls.exe $Shared /remove:d '*S-1-1-0' | Out-Null; $log += "execution de nouveau permise dans MobileGamePCShared" }
  }
  if ($Mode -eq 'Block' -and $Shared -and (Test-Path -LiteralPath $Shared)) {
    foreach ($f in @(Get-ChildItem -LiteralPath $Shared -Filter 'com_tencent_gameloop_*.exe' -File -ErrorAction SilentlyContinue)) {
      Rename-Item -LiteralPath $f.FullName -NewName ($f.Name + '.bloque') -Force
      $log += "installateur neutralise : $($f.Name)"
    }
  }
  Set-Content -LiteralPath $Out -Value ('OK' + "`r`n" + ($log -join "`r`n"))
} catch {
  Set-Content -LiteralPath $Out -Value ('ERREUR : ' + $_.Exception.Message)
}
'@

function Get-UpdFwOnlyPaths {
  $r = Get-GameLoopRoot
  # seulement quand l'emulateur est installe (sinon AppMarket ne pourrait plus l'installer)
  if (-not $r -or -not (Test-EngineInstalled)) { return @() }
  @($UpdFwOnly | ForEach-Object { Join-Path $r $_ })
}
function Test-EngineInstalled { $r = Get-GameLoopRoot; [bool]($r -and (Test-Path -LiteralPath (Join-Path $r 'ui'))) }
function Get-UpdTargetPaths {
  $r = Get-GameLoopRoot
  if (-not $r) { return @() }
  # Tant que l'emulateur n'est pas installe, TUpdate doit rester actif (il installe l'emulateur) :
  # on ne bloque alors que la migration (PcyybAssistant).
  $t = if (Test-EngineInstalled) { $UpdTargets } else { @($UpdTargets | Where-Object { $_ -notmatch 'TUpdate' }) }
  @($t | ForEach-Object { Join-Path $r $_ })
}
function Get-TUpdatePath { $r = Get-GameLoopRoot; if ($r) { Join-Path $r 'AppMarket\GF186\TUpdate.exe' } else { $null } }

function Test-SharedNoExec {
  try {
    $acl = Get-Acl -LiteralPath $UpdSharedDir
    [bool](@($acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' -and $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -eq 'S-1-1-0' -and ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ExecuteFile) }).Count)
  } catch { $false }
}
function Get-UpdateBlockState {
  $paths = Get-UpdTargetPaths
  if (-not $paths -or -not (Test-Path -LiteralPath (Join-Path (Get-GameLoopRoot) 'AppMarket'))) { return 'unknown' }
  $rules = @()
  try { $rules = @(Get-NetFirewallRule -DisplayName 'PubgSetup - Bloquer MAJ GameLoop*' -ErrorAction SilentlyContinue) } catch { }
  $present = @($paths | Where-Object { Test-Path -LiteralPath $_ })
  $offs = @($paths | Where-Object { Test-Path -LiteralPath "$_.bloque" })
  $pending = @()
  if (Test-Path -LiteralPath $UpdSharedDir) { $pending = @(Get-ChildItem -LiteralPath $UpdSharedDir -Filter 'com_tencent_gameloop_*.exe' -File -ErrorAction SilentlyContinue) }
  if (-not $present -and -not $offs) { return 'missing' }
  $need = $paths.Count + @(Get-UpdFwOnlyPaths).Count
  if (-not $present -and $rules.Count -ge $need -and -not $pending -and (Test-SharedNoExec)) { if (Test-EngineInstalled) { return 'blocked' } else { return 'migr' } }
  if ($offs -or $rules) { return 'partial' }
  'open'
}

function Update-UpdateBlockUi {
  switch (Get-UpdateBlockState) {
    'blocked' { $ui.btnUpdBlock.Content = 'MAJ bloquees  -  autoriser a nouveau'; $ui.tbUpdState.Text = 'OK : MAJ GameLoop BLOQUEES (TUpdate + PcyybAssistant desactives, telechargeurs bloques au pare-feu). Pour une grosse mise a jour de PUBG, il faudra debloquer temporairement. Ne cliquez pas sur le bouton si vous voulez rester bloque.'; $ui.tbUpdState.Foreground = '#0E7C66' }
    'partial' { $ui.btnUpdBlock.Content = 'Bloquer les MAJ GameLoop'; $ui.tbUpdState.Text = 'Blocage incomplet (fichier remis par GameLoop ou nouvel installateur telecharge). Cliquez pour bloquer a nouveau.'; $ui.tbUpdState.Foreground = '#B45309' }
    'migr'    { $ui.btnUpdBlock.Content = 'Bloquer les MAJ GameLoop'; $ui.tbUpdState.Text = 'Migration bloquee. Emulateur pas encore installe : lancez GameLoop, laissez-le installer l''emulateur, puis recliquez ici pour bloquer aussi TUpdate.'; $ui.tbUpdState.Foreground = '#B45309' }
    'missing' { $ui.btnUpdBlock.Content = 'Bloquer les MAJ GameLoop'; $ui.tbUpdState.Text = 'Programmes de mise a jour introuvables dans AppMarket.'; $ui.tbUpdState.Foreground = '#B45309' }
    'unknown' { $ui.btnUpdBlock.Content = 'Bloquer les MAJ GameLoop'; $ui.tbUpdState.Text = 'Dossier GameLoop non trouve : choisissez-le en haut.'; $ui.tbUpdState.Foreground = '#6B7280' }
    default   { $ui.btnUpdBlock.Content = 'Bloquer les MAJ GameLoop'; $ui.tbUpdState.Text = 'MAJ GameLoop autorisees.'; $ui.tbUpdState.Foreground = '#6B7280' }
  }
}

function Switch-UpdateBlock {
  $state = Get-UpdateBlockState
  if ($state -eq 'unknown') { Info 'Dossier GameLoop introuvable. Choisissez-le avec le bouton "Dossier GameLoop".' 'Warning'; return }
  $block = $state -ne 'blocked' -and $state -ne 'migr'
  if ($state -eq 'migr') { $block = $true }
  $exe = Get-TUpdatePath
  if ($block) {
    $msg = "Bloquer les mises a jour de GameLoop ?`n`n" +
           "- TUpdate.exe et PcyybAssistant.exe (mise a jour / migration vers le nouveau GameLoop) seront renommes en .bloque`n" +
           "- des regles du pare-feu Windows leur interdiront Internet`n" +
           "- les installateurs deja telecharges dans MobileGamePCShared seront neutralises, et plus aucun programme ne pourra s'y executer`n" +
           "- les telechargeurs d'AppMarket (syzs_dl_svr, GameDownload) seront bloques au pare-feu (si l'emulateur est installe)`n`n" +
           "A savoir :`n" +
           "- Windows va demander l'autorisation administrateur.`n" +
           "- Si GameLoop exige une mise a jour obligatoire, il peut refuser de demarrer : cliquez alors sur 'Debloquer'.`n" +
           "- Les mises a jour de PUBG (dans le jeu) et de l'anti-triche ne sont pas concernees.`n" +
           "- Une reinstallation ou une reparation de GameLoop peut annuler le blocage."
  } else {
    $msg = "ATTENTION : les mises a jour de GameLoop sont actuellement BLOQUEES.`n`nVoulez-vous vraiment les AUTORISER a nouveau ?`nLes programmes seront remis en place et GameLoop pourra se mettre a jour (et migrer vers le nouveau GameLoop).`n`nRepondez Non pour rester bloque."
  }
  $okGo = if ($block) { Ask $msg } else { AskNo $msg }
  if (-not $okGo) { return }
  $dir = Join-Path $DataRoot 'app'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $ps1 = Join-Path $dir 'gameloop-update-block.ps1'
  $out = Join-Path $dir 'gameloop-update-block.result.txt'
  Set-Content -LiteralPath $ps1 -Value $UpdBlockScript -Encoding UTF8
  Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
  $mode = if ($block) { 'Block' } else { 'Unblock' }
  $argLine = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1`" -Mode $mode -Exes `"$((Get-UpdTargetPaths) -join '|')`" -FwOnly `"$((Get-UpdFwOnlyPaths) -join '|')`" -Shared `"$UpdSharedDir`" -Out `"$out`""
  try {
    Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $argLine -Verb RunAs -WindowStyle Hidden -Wait
  } catch {
    Log 'MAJ GameLoop : autorisation administrateur refusee, rien n''a ete change.'
    return
  }
  $res = if (Test-Path -LiteralPath $out) { (Get-Content -LiteralPath $out -Raw).Trim() } else { 'aucun resultat (operation annulee ?)' }
  ($res -split "`r?`n") | ForEach-Object { Log "MAJ GameLoop ($mode) : $_" }
  Update-UpdateBlockUi
  if ($res -match '^OK' -and $res -notmatch 'ERREUR') {
    Info $(if ($block) { 'Mises a jour de GameLoop bloquees.' } else { 'Mises a jour de GameLoop debloquees.' })
  } else { Info $res 'Warning' }
}

# ---------------- Blocage du lancement de GameLoop au demarrage du PC ----------------
# Cherche les lancements automatiques de GameLoop : cles Run (HKCU, HKLM, WOW6432Node),
# dossiers Demarrage, taches planifiees. Les desactive comme le Gestionnaire des taches
# (onglet Demarrage, valeurs StartupApproved) et Disable-ScheduledTask : rien n'est supprime.
# Les services Windows ne sont pas modifies.
$StartupLib = @'
$SuPattern = 'TxGameAssistant|GameLoop|MobileGamePC|AndroidEmulatorE[nx]?\.exe|QMEmulatorService'
$SuRunKeys = @(
  @{ Run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';             Appr = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' },
  @{ Run = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';             Appr = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' },
  @{ Run = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Appr = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' }
)
$SuFolders = @(
  @{ Dir = [Environment]::GetFolderPath('Startup');       Appr = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' },
  @{ Dir = [Environment]::GetFolderPath('CommonStartup'); Appr = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
)
function Test-SuApprovedOff([string]$appr, [string]$name) {
  try { $b = (Get-ItemProperty -LiteralPath $appr -Name $name -ErrorAction Stop).$name; return [bool]($b -and ($b[0] -band 1)) } catch { return $false }
}
function Get-StartupItems {
  $items = @()
  foreach ($k in $SuRunKeys) {
    $p = Get-ItemProperty -LiteralPath $k.Run -ErrorAction SilentlyContinue
    if (-not $p) { continue }
    foreach ($prop in $p.PSObject.Properties) {
      if ($prop.Name -in 'PSPath','PSParentPath','PSChildName','PSDrive','PSProvider') { continue }
      if ([string]$prop.Value -match $SuPattern) {
        $items += [pscustomobject]@{ Kind = 'Run'; Name = $prop.Name; Where = $k.Run; Appr = $k.Appr; Off = (Test-SuApprovedOff $k.Appr $prop.Name); Detail = [string]$prop.Value }
      }
    }
  }
  $sh = $null
  try { $sh = New-Object -ComObject WScript.Shell } catch { }
  foreach ($f in $SuFolders) {
    if (-not $f.Dir -or -not (Test-Path -LiteralPath $f.Dir)) { continue }
    foreach ($l in @(Get-ChildItem -LiteralPath $f.Dir -File -ErrorAction SilentlyContinue)) {
      $t = ''
      if ($sh -and $l.Extension -eq '.lnk') { try { $t = $sh.CreateShortcut($l.FullName).TargetPath } catch { } }
      if ("$($l.Name) $t" -match $SuPattern) {
        $items += [pscustomobject]@{ Kind = 'Folder'; Name = $l.Name; Where = $f.Dir; Appr = $f.Appr; Off = (Test-SuApprovedOff $f.Appr $l.Name); Detail = $t }
      }
    }
  }
  try {
    foreach ($t in @(Get-ScheduledTask -ErrorAction Stop)) {
      $cmd = (@($t.Actions) | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' '
      if ("$($t.TaskName) $cmd" -match $SuPattern) {
        $items += [pscustomobject]@{ Kind = 'Task'; Name = $t.TaskName; Where = $t.TaskPath; Appr = ''; Off = ([string]$t.State -eq 'Disabled'); Detail = $cmd }
      }
    }
  } catch { }
  # GameLoop : le service QMEmulatorService (demarrage auto) lance 'AppMarket.exe -launchtray'
  # a l'ouverture de session si la valeur AutoStart de ...\Tencent\MobileGamePC\AppMarket est active.
  $autoFound = $false
  foreach ($rk in 'HKLM:\SOFTWARE\WOW6432Node\Tencent\MobileGamePC\AppMarket','HKLM:\SOFTWARE\Tencent\MobileGamePC\AppMarket','HKCU:\Software\Tencent\MobileGamePC\AppMarket') {
    $v = $null
    try { $v = (Get-ItemProperty -LiteralPath $rk -Name AutoStart -ErrorAction Stop).AutoStart } catch { continue }
    $autoFound = $true
    $items += [pscustomobject]@{ Kind = 'Auto'; Name = 'AutoStart'; Where = $rk; Appr = [string]$v; Off = ([string]$v -eq '0'); Detail = 'QMEmulatorService -> AppMarket.exe -launchtray' }
  }
  if (-not $autoFound) {
    try {
      $svc = Get-CimInstance Win32_Service -Filter "Name='QMEmulatorService'" -ErrorAction Stop
      if ($svc) { $items += [pscustomobject]@{ Kind = 'Service'; Name = 'QMEmulatorService'; Where = $svc.StartMode; Appr = ''; Off = ($svc.StartMode -ne 'Auto'); Detail = $svc.PathName } }
    } catch { }
  }
  ,$items
}
function Set-SuApproved([string]$appr, [string]$name, [bool]$off) {
  if (-not (Test-Path -LiteralPath $appr)) { New-Item -Path $appr -Force | Out-Null }
  $b = New-Object byte[] 12
  if ($off) { $b[0] = 3; [BitConverter]::GetBytes([DateTime]::Now.ToFileTime()).CopyTo($b, 4) } else { $b[0] = 2 }
  New-ItemProperty -LiteralPath $appr -Name $name -PropertyType Binary -Value $b -Force | Out-Null
}
function Switch-SuItem($i, [bool]$off) {
  if ($i.Kind -eq 'Auto') {
    $kind = (Get-Item -LiteralPath $i.Where).GetValueKind('AutoStart')
    $val = if ($off) { 0 } elseif ($i.Appr -and $i.Appr -ne '0') { $i.Appr } else { 1 }
    if ($kind -eq 'String') { $val = [string]$val }
    New-ItemProperty -LiteralPath $i.Where -Name 'AutoStart' -PropertyType $kind -Value $val -Force | Out-Null
    return
  }
  if ($i.Kind -eq 'Service') {
    Set-Service -Name $i.Name -StartupType $(if ($off) { 'Manual' } else { 'Automatic' }) -ErrorAction Stop
    return
  }
  if ($i.Kind -eq 'Task') {
    if ($off) { Disable-ScheduledTask -TaskName $i.Name -TaskPath $i.Where -ErrorAction Stop | Out-Null }
    else      { Enable-ScheduledTask  -TaskName $i.Name -TaskPath $i.Where -ErrorAction Stop | Out-Null }
  } else { Set-SuApproved $i.Appr $i.Name $off }
}
function Read-SuState([string]$f) {
  if (-not (Test-Path -LiteralPath $f)) { return $null }
  try { ,@((Get-Content -LiteralPath $f -Raw | ConvertFrom-Json) | ForEach-Object { $_ }) } catch { ,@() }
}
function Set-StartupBlock([bool]$block, [string]$stateFile) {
  $log = New-Object System.Collections.Generic.List[string]
  if ($block) {
    $changed = @()
    foreach ($i in @(Get-StartupItems | ForEach-Object { $_ } | Where-Object { -not $_.Off })) {
      try { Switch-SuItem $i $true; $changed += ($i | Select-Object Kind, Name, Where, Appr); $log.Add("Desactive : $($i.Kind) $($i.Name)") }
      catch { $log.Add("ERREUR $($i.Kind) $($i.Name) : $($_.Exception.Message)") }
    }
    $old = Read-SuState $stateFile
    if ($null -eq $old) { $old = @() }
    ConvertTo-Json -InputObject @($old + $changed) -Depth 3 | Set-Content -LiteralPath $stateFile
    if (-not $changed) { $log.Add('Rien a desactiver : aucun lancement automatique de GameLoop actif.') }
  } else {
    $list = Read-SuState $stateFile
    if ($null -eq $list) { $list = @(Get-StartupItems | ForEach-Object { $_ } | Where-Object { $_.Off -and $_.Kind -ne 'Task' }) }
    foreach ($i in $list) {
      try { Switch-SuItem $i $false; $log.Add("Reactive : $($i.Kind) $($i.Name)") }
      catch { $log.Add("ERREUR $($i.Kind) $($i.Name) : $($_.Exception.Message)") }
    }
    Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue
    if (-not $list) { $log.Add('Rien a reactiver.') }
  }
  ,$log.ToArray()
}
'@
$StartupMain = @'
$ErrorActionPreference = 'Stop'
try {
  $r = Set-StartupBlock ($Mode -eq 'Block') $State
  Set-Content -LiteralPath $Out -Value ('OK' + "`r`n" + ($r -join "`r`n"))
} catch {
  Set-Content -LiteralPath $Out -Value ('ERREUR : ' + $_.Exception.Message)
}
'@
. ([scriptblock]::Create($StartupLib))
$StartupStateFile = Join-Path $DataRoot 'startup-block.json'

function Get-StartupBlockState {
  $items = @(Get-StartupItems | ForEach-Object { $_ })
  if (-not $items) { return 'none' }
  if (@($items | Where-Object { -not $_.Off }).Count) { 'active' } else { 'blocked' }
}
function Update-StartupBlockUi {
  switch (Get-StartupBlockState) {
    'blocked' { $ui.btnStartBlock.Content = 'Demarrage bloque  -  reactiver'; $ui.tbStartState.Text = 'OK : GameLoop ne se lance plus au demarrage du PC.'; $ui.tbStartState.Foreground = '#0E7C66' }
    'active'  { $ui.btnStartBlock.Content = 'Bloquer GameLoop au demarrage'; $ui.tbStartState.Text = 'GameLoop se lance au demarrage du PC.'; $ui.tbStartState.Foreground = '#B45309' }
    default   {
      $ui.btnStartBlock.Content = $(if (Test-Path -LiteralPath $StartupStateFile) { 'Reactiver GameLoop au demarrage' } else { 'Bloquer GameLoop au demarrage' })
      $ui.tbStartState.Text = 'Aucun lancement automatique de GameLoop trouve.'; $ui.tbStartState.Foreground = '#6B7280'
    }
  }
}
function Switch-StartupBlock {
  $items = @(Get-StartupItems | ForEach-Object { $_ })
  $active = @($items | Where-Object { -not $_.Off })
  $block = [bool]$active.Count
  if (-not $block -and -not (Test-Path -LiteralPath $StartupStateFile) -and -not $items) {
    Info 'Aucun lancement automatique de GameLoop trouve (cles Run, dossier Demarrage, taches planifiees). Rien a bloquer.'
    return
  }
  $kinds = @{ Run = 'Demarrage Windows'; Folder = 'Dossier Demarrage'; Task = 'Tache planifiee'; Auto = 'Lancement auto par le service GameLoop'; Service = 'Service GameLoop (passe en manuel)' }
  if ($block) {
    $list = ($active | ForEach-Object { "- $($kinds[$_.Kind]) : $($_.Name)" }) -join "`n"
    $msg = "Desactiver le lancement de GameLoop au demarrage du PC ?`n`n$list`n`n" +
           "Comme le Gestionnaire des taches (onglet Demarrage) : rien n'est supprime, tout peut etre reactive.`n" +
           "Windows va demander l'autorisation administrateur."
  } else {
    $msg = "ATTENTION : le lancement de GameLoop au demarrage est actuellement BLOQUE.`n`nVoulez-vous vraiment le REACTIVER ?`n`nRepondez Non pour rester bloque."
  }
  $okGo = if ($block) { Ask $msg } else { AskNo $msg }
  if (-not $okGo) { return }
  $dir = Join-Path $DataRoot 'app'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $ps1 = Join-Path $dir 'gameloop-startup-block.ps1'
  $out = Join-Path $dir 'gameloop-startup-block.result.txt'
  Set-Content -LiteralPath $ps1 -Value ("param([string]`$Mode, [string]`$State, [string]`$Out)`r`n" + $StartupLib + "`r`n" + $StartupMain) -Encoding UTF8
  Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
  $mode = if ($block) { 'Block' } else { 'Unblock' }
  $argLine = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1`" -Mode $mode -State `"$StartupStateFile`" -Out `"$out`""
  try {
    Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $argLine -Verb RunAs -WindowStyle Hidden -Wait
  } catch {
    Log 'Demarrage GameLoop : autorisation administrateur refusee, rien n''a ete change.'
    return
  }
  $res = if (Test-Path -LiteralPath $out) { (Get-Content -LiteralPath $out -Raw).Trim() } else { 'aucun resultat (operation annulee ?)' }
  ($res -split "`r?`n") | ForEach-Object { Log "Demarrage GameLoop : $_" }
  Update-StartupBlockUi
  if ($res -match '^OK' -and $res -notmatch 'ERREUR') {
    Info $(if ($block) { 'GameLoop ne se lancera plus au demarrage du PC.' } else { 'Lancement de GameLoop au demarrage reactive.' })
  } else { Info $res 'Warning' }
}

# ---------------- Fermeture complete de PUBG / GameLoop ----------------
# Ferme tous les processus lances depuis le dossier GameLoop (AppMarket, emulateur, aow_exe,
# rendu, PUBG dans l'emulateur, aides) + les noms connus, et arrete les services GameLoop
# en cours (sans changer leur type de demarrage). Droits administrateur demandes (UAC)
# car GameLoop tourne en administrateur.
$CloseAllScript = @'
param([string]$Root, [string]$Out)
$names = 'AndroidEmulator','AndroidEmulatorEn','AndroidEmulatorEx','AndroidRenderer','AppMarket','aow_exe',
         'QMEmulatorService','TUpdate','GameDownload','GameLogin','TxGaDcc','QQExternal','QQPCExternal',
         'cef_frame_render','cef_frame_demo','PcyybAssistant','MGDetector','TSettingCenter'
$useRoot = $Root -and (Test-Path -LiteralPath (Join-Path $Root 'AppMarket'))
if ($useRoot) { $Root = $Root.TrimEnd('\') + '\' }
function Test-InRoot([string]$p) { $useRoot -and $p -and $p.Trim().TrimStart('"').StartsWith($Root, [StringComparison]::OrdinalIgnoreCase) }
function Get-Targets {
  @(Get-CimInstance Win32_Process | Where-Object {
      $_.ProcessId -ne $PID -and ((Test-InRoot $_.ExecutablePath) -or ($names -contains [IO.Path]::GetFileNameWithoutExtension([string]$_.Name)))
  })
}
$log = New-Object System.Collections.Generic.List[string]
try {
  $closed = @{}
  for ($pass = 0; $pass -lt 3; $pass++) {
    $procs = Get-Targets
    if (-not $procs) { break }
    foreach ($p in $procs) {
      try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; $closed[[string]$p.Name] = 1 } catch { }
    }
    Start-Sleep -Milliseconds 800
  }
  foreach ($s in @(Get-CimInstance Win32_Service | Where-Object { $_.State -eq 'Running' -and (Test-InRoot $_.PathName) })) {
    try { Stop-Service -Name $s.Name -Force -ErrorAction Stop; $log.Add("Service arrete : $($s.Name)") }
    catch { $log.Add("ERREUR service $($s.Name) : $($_.Exception.Message)") }
  }
  if ($closed.Count) { $log.Insert(0, 'Fermes : ' + (($closed.Keys | Sort-Object) -join ', ')) } else { $log.Insert(0, 'Aucun processus GameLoop ouvert.') }
  $left = Get-Targets
  if ($left) { $log.Add('ENCORE OUVERTS : ' + ((@($left | ForEach-Object { $_.Name }) | Sort-Object -Unique) -join ', ')) }
  $log.Insert(0, 'OK')
} catch { $log.Insert(0, 'ERREUR : ' + $_.Exception.Message) }
if ($Out) { Set-Content -LiteralPath $Out -Value ($log -join "`r`n") } else { $log }
'@

function Close-AllGameLoop {
  if (-not (Ask "Fermer completement PUBG et GameLoop ?`n`nTous les processus GameLoop (AppMarket, emulateur, PUBG, rendu, aides) seront fermes et ses services arretes.`nUne partie en cours sera perdue. Windows va demander l'autorisation administrateur.")) { return }
  $root = Get-GameLoopRoot
  if (-not $root) { $root = 'none' }
  $dir = Join-Path $DataRoot 'app'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $ps1 = Join-Path $dir 'gameloop-close-all.ps1'
  $out = Join-Path $dir 'gameloop-close-all.result.txt'
  Set-Content -LiteralPath $ps1 -Value $CloseAllScript -Encoding UTF8
  Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
  $argLine = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1`" -Root `"$root`" -Out `"$out`""
  $elevated = $true
  try {
    Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $argLine -Verb RunAs -WindowStyle Hidden -Wait
  } catch { $elevated = $false }
  if ($elevated) {
    $res = if (Test-Path -LiteralPath $out) { (Get-Content -LiteralPath $out -Raw).Trim() } else { 'aucun resultat' }
  } else {
    Log 'Fermeture : autorisation administrateur refusee, essai sans droits administrateur.'
    $res = (& ([scriptblock]::Create($CloseAllScript)) $root '') -join "`r`n"
  }
  ($res -split "`r?`n") | ForEach-Object { Log "Fermeture : $_" }
  Update-Status
  if ($res -match 'ENCORE OUVERTS|ERREUR') { Info ("Fermeture incomplete :`n`n" + $res) 'Warning' }
  else { Info 'PUBG et GameLoop sont completement fermes.' }
}

# ---------------- Mode jeu : fermer les applications non Windows ----------------
# Liste les programmes de la session (hors dossier Windows, hors GameLoop, hors pilotes,
# antivirus, peripheriques et anti-triche), l'utilisateur coche ceux a fermer.
# Fermeture propre d'abord (comme cliquer sur X), forcee seulement pour les applis sans fenetre.
# Les pilotes ne sont jamais touches : les decharger peut bloquer le PC (ecran, son, clavier, reseau).
$GameModeFile = Join-Path $DataRoot 'gamemode-apps.txt'
$GameModeProtected = '^(explorer|dwm|csrss|winlogon|ctfmon|sihost|taskhostw|ShellExperienceHost|StartMenuExperienceHost|SearchHost|SearchApp|RuntimeBroker|TextInputHost|SecurityHealth.*|MsMpEng|NisSrv|smartscreen|audiodg|conhost|OpenConsole|WindowsTerminal|powershell|pwsh|PubgSetup|Claude.*|cowork.*)$' +
  '|nvcontainer|NVDisplay|nvsphelper|NVIDIA|nvcplui|Radeon|AMDRS|amdow|atiesrxx|atieclxx|igfx|IntelGraphics|' +
  'Realtek|RtkAud|RAVBg|Nahimic|Waves|Dolby|' +
  'Logitech|LGHUB|Razer|Synapse|Corsair|iCUE|SteelSeries|Wooting|HyperX|ArmouryCrate|MSIAfterburner|RTSS|' +
  'avast|avg|kaspersky|avp|bdagent|bitdefender|norton|mcafee|\bESET\b|egui|ekrn|malwarebytes|mbam|sophos|' +
  'SGuard|ACE-|TenProtect|tp3helper|TxGa|QQPC'

function Get-GameModeCandidates {
  $sess = (Get-Process -Id $PID).SessionId
  $winDir = $env:WINDIR.TrimEnd('\') + '\'
  $root = Get-GameLoopRoot
  $parent = $null
  try { $parent = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId } catch { }
  $list = @{}
  foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
    if ($p.Id -eq $PID -or $p.Id -eq $parent -or $p.SessionId -ne $sess) { continue }
    $path = $null; try { $path = $p.Path } catch { }
    if (-not $path) { continue }
    if ($path.StartsWith($winDir, [StringComparison]::OrdinalIgnoreCase)) { continue }
    if ($root -and $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { continue }
    if ($p.ProcessName -match $GameModeProtected) { continue }
    $desc = ''; try { $desc = $p.MainModule.FileVersionInfo.FileDescription } catch { }
    if ($desc -match $GameModeProtected) { continue }
    $k = $p.ProcessName
    if (-not $list.ContainsKey($k)) {
      $list[$k] = [pscustomobject]@{ Name = $k; Desc = $(if ($desc) { $desc } else { $k }); Ram = 0; Window = $false; Ids = @() }
    }
    $list[$k].Ram += $p.WorkingSet64
    $list[$k].Ids += $p.Id
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $list[$k].Window = $true }
  }
  @($list.Values | Sort-Object Ram -Descending)
}

function Close-GameModeApps($items) {
  $closed = @(); $left = @(); $freed = 0
  foreach ($it in $items) {
    $procs = @(Get-Process -Name $it.Name -ErrorAction SilentlyContinue)
    foreach ($p in $procs) {
      try { if ($p.MainWindowHandle -ne [IntPtr]::Zero) { [void]$p.CloseMainWindow() } } catch { }
    }
  }
  Start-Sleep -Seconds 3
  foreach ($it in $items) {
    $procs = @(Get-Process -Name $it.Name -ErrorAction SilentlyContinue)
    if (-not $procs) { $closed += $it.Name; $freed += $it.Ram; continue }
    $hasWin = @($procs | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }).Count -gt 0
    if ($hasWin) { $left += "$($it.Name) (fenetre encore ouverte : sauvegarde demandee ?)"; continue }
    $ok = $true
    foreach ($p in $procs) { try { $p.Kill() } catch { $ok = $false } }
    if ($ok) { $closed += $it.Name; $freed += $it.Ram } else { $left += "$($it.Name) (acces refuse)" }
  }
  [pscustomobject]@{ Closed = $closed; Left = $left; FreedMB = [int]($freed / 1MB) }
}

function Show-GameModeDialog {
  $items = Get-GameModeCandidates
  if (-not $items) { Info 'Aucune application non Windows a fermer.'; return }
  $saved = @()
  if (Test-Path -LiteralPath $GameModeFile) { $saved = @(Get-Content -LiteralPath $GameModeFile -ErrorAction SilentlyContinue) }
  $first = -not (Test-Path -LiteralPath $GameModeFile)

  $dlg = New-Object System.Windows.Window
  $dlg.Title = 'Mode jeu - fermer les applications'
  $dlg.Width = 560; $dlg.Height = 600; $dlg.WindowStartupLocation = 'CenterOwner'; $dlg.Owner = $script:Front
  $dlg.FontFamily = 'Segoe UI'; $dlg.FontSize = 13; $dlg.Background = '#F4F5F7'
  $dock = New-Object System.Windows.Controls.DockPanel
  $dock.Margin = '16'
  $head = New-Object System.Windows.Controls.TextBlock
  $head.TextWrapping = 'Wrap'; $head.Margin = '0,0,0,10'
  $head.Text = "Cochez les applications a fermer avant de jouer. Vos choix sont retenus pour la prochaine fois.`n" +
               "Pilotes, Windows, antivirus, peripheriques (souris, casque), anti-triche et GameLoop ne sont pas proposes."
  [System.Windows.Controls.DockPanel]::SetDock($head, 'Top')
  [void]$dock.Children.Add($head)

  $bar = New-Object System.Windows.Controls.StackPanel
  $bar.Orientation = 'Horizontal'; $bar.HorizontalAlignment = 'Right'; $bar.Margin = '0,10,0,0'
  [System.Windows.Controls.DockPanel]::SetDock($bar, 'Bottom')
  $bOk = New-Object System.Windows.Controls.Button
  $bOk.Content = 'Fermer la selection'; $bOk.Padding = '14,7'; $bOk.Margin = '0,0,8,0'; $bOk.IsDefault = $true
  $bOk.Background = '#0E7C66'; $bOk.Foreground = 'White'; $bOk.FontWeight = 'SemiBold'
  $bNo = New-Object System.Windows.Controls.Button
  $bNo.Content = 'Annuler'; $bNo.Padding = '14,7'; $bNo.IsCancel = $true
  [void]$bar.Children.Add($bOk); [void]$bar.Children.Add($bNo)
  [void]$dock.Children.Add($bar)

  $sv = New-Object System.Windows.Controls.ScrollViewer
  $sv.VerticalScrollBarVisibility = 'Auto'; $sv.Background = 'White'; $sv.Padding = '10,6'
  $stack = New-Object System.Windows.Controls.StackPanel
  $checks = @()
  foreach ($it in $items) {
    $cb = New-Object System.Windows.Controls.CheckBox
    $mb = [int]($it.Ram / 1MB)
    $cb.Content = "{0}  -  {1} Mo{2}" -f $it.Desc, $mb, $(if ($it.Window) { '' } else { '  (arriere-plan)' })
    $cb.ToolTip = $it.Name
    $cb.Margin = '0,3'
    $cb.Tag = $it
    $cb.IsChecked = if ($first) { $it.Window } else { $saved -contains $it.Name }
    [void]$stack.Children.Add($cb)
    $checks += $cb
  }
  $sv.Content = $stack
  [void]$dock.Children.Add($sv)
  $dlg.Content = $dock

  $bOk.Add_Click({ param($s, $e) [System.Windows.Window]::GetWindow($s).DialogResult = $true })
  if (-not $dlg.ShowDialog()) { return }

  $sel = @($checks | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
  # retenir les choix : coches ajoutes, decoches retires
  $keep = @($saved | Where-Object { $n = $_; -not ($items | Where-Object { $_.Name -eq $n }) })
  try { Set-Content -LiteralPath $GameModeFile -Value (@($keep) + @($sel | ForEach-Object { $_.Name })) } catch { }
  if (-not $sel) { return }

  $win.Cursor = 'Wait'
  try { $r = Close-GameModeApps $sel } finally { $win.Cursor = $null }
  Log ("Mode jeu : fermes = " + $(if ($r.Closed) { $r.Closed -join ', ' } else { 'aucun' }) + " ; environ $($r.FreedMB) Mo liberes")
  foreach ($l in $r.Left) { Log "Mode jeu : non ferme : $l" }
  $msg = "$(@($r.Closed).Count) application(s) fermee(s), environ $($r.FreedMB) Mo de memoire liberes."
  if ($r.Left) { $msg += "`n`nNon fermees :`n- " + ($r.Left -join "`n- ") }
  Info $msg
}

# ---------------- Installation protegee de l'ancien GameLoop ----------------
# Constat 2026-11-22 : l'ancien AppMarket recoit "Update required" et telecharge puis lance
# lui-meme l'installateur du nouveau GameLoop 7 (com_tencent_gameloop_yybinstaller_*.exe,
# dans MobileGamePCShared). Ce bouton pose les protections AVANT d'installer :
#   - verrous (dossiers au nom exact des installateurs connus) dans MobileGamePCShared ;
#   - pare-feu : PcyybAssistant.exe et les installateurs connus n'ont pas acces a Internet ;
# puis lance GLP_installer.exe, et apres l'installation :
#   - PcyybAssistant.exe renomme en .bloque ;
#   - AutoStart = 0 (plus de lancement au demarrage du PC).
$MigrInstallers = @(
  'com_tencent_gameloop_yybinstaller_c7a66d25e52b80eb_up_client_4022b26f4756390ebbceae42200df177.exe',
  'com_tencent_gameloop_silent_update_up_client_0b614910774666bb9a9828e889169dd8.exe'
)
$OldInstallScript = @'
param([string]$Installer, [string]$Root, [string]$Shared, [string]$Out)
$log = New-Object System.Collections.Generic.List[string]
function W { Set-Content -LiteralPath $Out -Value ($log -join "`r`n") }
try {
  # 1. interdire l'execution de tout .exe dans MobileGamePCShared (c'est la que l'ancien AppMarket
  #    telecharge puis lance l'installateur du nouveau GameLoop, sous un nom qui peut changer)
  if (-not (Test-Path -LiteralPath $Shared)) { New-Item -ItemType Directory -Force -Path $Shared | Out-Null }
  & icacls.exe $Shared /deny '*S-1-1-0:(OI)(IO)(X)' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "icacls a echoue ($LASTEXITCODE)" }
  $log.Add("execution interdite dans $Shared")
  # 2. pare-feu (les regles par chemin marchent meme si le fichier n'existe pas encore)
  Get-NetFirewallRule -DisplayName 'PubgSetup - Anti-migration*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  $fw = @((Join-Path $Root 'AppMarket\PcyybAssistant.exe'))
  foreach ($p in $fw) {
    New-NetFirewallRule -DisplayName ("PubgSetup - Anti-migration (" + [IO.Path]::GetFileName($p) + ")") -Group 'PubgSetup' -Direction Outbound -Action Block -Program $p -Profile Any | Out-Null
  }
  $log.Add("pare-feu : $($fw.Count) regle(s) anti-migration")
  W
  # 3. installation (on attend seulement l'installateur, pas GameLoop qu'il peut lancer a la fin)
  $proc = Start-Process -FilePath $Installer -PassThru
  $proc.WaitForExit()
  $log.Add("installateur termine (code $($proc.ExitCode))")
  # 4. PcyybAssistant
  $pa = Join-Path $Root 'AppMarket\PcyybAssistant.exe'
  for ($i = 0; $i -lt 30 -and -not (Test-Path -LiteralPath $pa); $i++) { Start-Sleep -Seconds 1 }
  if (Test-Path -LiteralPath $pa) {
    Get-Process -Name PcyybAssistant -ErrorAction SilentlyContinue | Stop-Process -Force
    if (Test-Path -LiteralPath "$pa.bloque") { Remove-Item -LiteralPath "$pa.bloque" -Force }
    Rename-Item -LiteralPath $pa -NewName 'PcyybAssistant.exe.bloque'
    $log.Add('PcyybAssistant desactive')
  } else { $log.Add('PcyybAssistant absent (AppMarket pas encore installe ?)') }
  # 5. AutoStart = 0
  $done = $false
  foreach ($rk in 'HKLM:\SOFTWARE\WOW6432Node\Tencent\MobileGamePC\AppMarket', 'HKLM:\SOFTWARE\Tencent\MobileGamePC\AppMarket') {
    if ($null -ne (Get-ItemProperty -LiteralPath $rk -Name AutoStart -ErrorAction SilentlyContinue)) {
      $kind = (Get-Item -LiteralPath $rk).GetValueKind('AutoStart')
      $v = if ($kind -eq 'String') { '0' } else { 0 }
      New-ItemProperty -LiteralPath $rk -Name AutoStart -PropertyType $kind -Value $v -Force | Out-Null
      $log.Add("AutoStart = 0 ($rk)"); $done = $true
    }
  }
  if (-not $done) { $log.Add('AutoStart introuvable : cliquez "Bloquer GameLoop au demarrage" apres le premier lancement') }
  $log.Insert(0, 'OK')
} catch { $log.Insert(0, 'ERREUR : ' + $_.Exception.Message) }
W
'@

function Find-OldInstaller {
  if ($script:InstallerPath -and (Test-Path -LiteralPath $script:InstallerPath)) { return $script:InstallerPath }
  # installateur integre dans l'exe (extrait par le lanceur)
  if ($env:PUBGSETUP_INSTALLER -and (Test-Path -LiteralPath $env:PUBGSETUP_INSTALLER)) { return $env:PUBGSETUP_INSTALLER }
  $dirs = @()
  if ($env:PUBGSETUP_EXEDIR) { $dirs += (Join-Path $env:PUBGSETUP_EXEDIR 'gameloop'); $dirs += $env:PUBGSETUP_EXEDIR }
  $dirs += (Join-Path $env:USERPROFILE 'Downloads')
  foreach ($d in $dirs) {
    if (-not (Test-Path -LiteralPath $d)) { continue }
    $f = Get-ChildItem -LiteralPath $d -Filter 'GLP_installer*.exe' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($f) { return $f.FullName }
  }
  $null
}

function Install-OldGameLoop {
  $newGl = Join-Path $env:ProgramFiles 'Tencent\GameLoop\Application'
  if (Test-Path -LiteralPath (Join-Path $newGl 'GameLoopLauncher.exe')) {
    Info "Le nouveau GameLoop 7 est encore installe ($newGl).`nDesinstallez-le d'abord (Parametres Windows > Applications), puis recliquez ici." 'Warning'
    return
  }
  $inst = Find-OldInstaller
  if (-not $inst) {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Choisissez l'installateur de l'ancien GameLoop (GLP_installer.exe)"
    $dlg.Filter = 'Installateur (*.exe)|*.exe'
    if ($dlg.ShowDialog() -ne 'OK') { return }
    $inst = $dlg.FileName
  }
  $root = Join-Path $env:ProgramFiles 'TxGameAssistant'
  $msg = "Installer l'ancien GameLoop, protege contre la migration ?`n`nInstallateur : $inst`n`n" +
         "Avant l'installation :`n- aucun programme ne pourra plus s'executer depuis MobileGamePCShared (la ou GameLoop telecharge l'installateur du nouveau GameLoop)`n- pare-feu : PcyybAssistant sans Internet`n`n" +
         "Apres l'installation :`n- PcyybAssistant desactive`n- plus de lancement au demarrage du PC`n`n" +
         "Ensuite : lancez GameLoop, laissez-le installer l'emulateur et PUBG, puis cliquez 'Bloquer les MAJ GameLoop'.`n`nWindows va demander l'autorisation administrateur."
  if (-not (Ask $msg)) { return }
  $dir = Join-Path $DataRoot 'app'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $ps1 = Join-Path $dir 'gameloop-install-old.ps1'
  $out = Join-Path $dir 'gameloop-install-old.result.txt'
  Set-Content -LiteralPath $ps1 -Value $OldInstallScript -Encoding UTF8
  Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
  $argLine = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1`" -Installer `"$inst`" -Root `"$root`" -Shared `"$UpdSharedDir`" -Out `"$out`""
  Log "Installation de l'ancien GameLoop : $inst"
  $win.Cursor = 'Wait'
  try {
    $p = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $argLine -Verb RunAs -WindowStyle Hidden -PassThru
    # attendre sans geler la fenetre, et sans attendre GameLoop que l'installateur peut lancer
    while (-not $p.HasExited) {
      Start-Sleep -Milliseconds 250
      $win.Dispatcher.Invoke([Action]{ }, [System.Windows.Threading.DispatcherPriority]::Background)
    }
  } catch {
    Log 'Installation : autorisation administrateur refusee, rien n''a ete fait.'
    return
  } finally { $win.Cursor = $null }
  $res = if (Test-Path -LiteralPath $out) { (Get-Content -LiteralPath $out -Raw).Trim() } else { 'aucun resultat' }
  ($res -split "`r?`n") | ForEach-Object { Log "Installation : $_" }
  # GameLoop installe : on le recherche
  Set-GameLoopUi (Find-GameLoopUi)
  Update-Status; Update-UpdateBlockUi; Update-StartupBlockUi
  if ($res -match '^OK') {
    Info ("Installation terminee avec protections.`n`n" + $res + "`n`nEtape suivante : lancez GameLoop, laissez-le installer l'emulateur et PUBG.`nSi une fenetre propose une mise a jour ou le nouveau GameLoop, fermez-la.`nPuis cliquez 'Bloquer les MAJ GameLoop'.")
  } else { Info $res 'Warning' }
}

# ---------------- Metrics : moniteur leger en temps reel ----------------
# Les mesures tournent dans un fil separe (pas de gel de l'interface).
# Lecture seule : compteurs Windows, nvidia-smi s'il existe. Rien n'est ecrit dans GameLoop.
$MonitorSampler = @'
param($S)
$cores = [Environment]::ProcessorCount
$smi = @("$env:WINDIR\System32\nvidia-smi.exe", "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe") |
  Where-Object { Test-Path $_ } | Select-Object -First 1
$filter = "Name LIKE 'AndroidEmulator%' OR Name LIKE 'aow_exe%' OR Name LIKE 'AndroidRenderer%' OR Name LIKE 'AppMarket%'"
while ($S.Run) {
  $t0 = [DateTime]::UtcNow
  try {
    $p = @(Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -ErrorAction Stop)
    $S.Cpu    = [int](($p | Where-Object { $_.Name -eq '_Total' }).PercentProcessorTime)
    $S.CpuMax = [int](($p | Where-Object { $_.Name -ne '_Total' } | Measure-Object PercentProcessorTime -Maximum).Maximum)
  } catch { $S.Cpu = $null; $S.CpuMax = $null }
  try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $S.RamUsed  = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB
    $S.RamTotal = $os.TotalVisibleMemorySize / 1MB
  } catch { $S.RamUsed = $null }
  $gpuOk = $false
  if ($smi) {
    try {
      $line = & $smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,clocks.gr --format=csv,noheader,nounits 2>$null | Select-Object -First 1
      $v = @(([string]$line) -split ',' | ForEach-Object { $_.Trim() })
      if ($v.Count -ge 5 -and $v[0] -match '^\d+$') {
        $S.Gpu = [int]$v[0]; $S.GpuTemp = [int]$v[1]; $S.VramUsed = [int]$v[2]; $S.VramTotal = [int]$v[3]
        $S.GpuClock = [int]$v[4]; $S.GpuSrc = 'nvidia-smi'; $gpuOk = $true
      }
    } catch { }
  }
  if (-not $gpuOk) {
    try {
      $agg = @{}
      foreach ($e in @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop)) {
        if ($e.Name -match '(luid_0x[0-9A-Fa-f]+_0x[0-9A-Fa-f]+_phys_\d+_eng_\d+)') { $agg[$Matches[1]] += [double]$e.UtilizationPercentage }
      }
      $S.Gpu = if ($agg.Count) { [int][math]::Min(100, ($agg.Values | Measure-Object -Maximum).Maximum) } else { 0 }
      $mem = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory -ErrorAction SilentlyContinue)
      $S.VramUsed = if ($mem) { [int](($mem | Measure-Object DedicatedUsage -Maximum).Maximum / 1MB) } else { $null }
      $S.VramTotal = $null; $S.GpuTemp = $null; $S.GpuClock = $null; $S.GpuSrc = 'compteurs Windows'
    } catch { $S.Gpu = $null; $S.GpuSrc = 'indisponible' }
  }
  try {
    $pp = @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Filter $filter -ErrorAction Stop)
    $S.EmuRunning = $pp.Count -gt 0
    $S.EmuCpu = [int](($pp | Measure-Object PercentProcessorTime -Sum).Sum / $cores)
    $S.EmuRam = ($pp | Measure-Object WorkingSetPrivate -Sum).Sum / 1GB
  } catch { $S.EmuRunning = $null }
  $S.Stamp = [DateTime]::UtcNow
  $wait = 1000 - [int]([DateTime]::UtcNow - $t0).TotalMilliseconds
  if ($wait -gt 50) { Start-Sleep -Milliseconds $wait }
}
'@

[xml]$MonXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Metrics" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="True" ResizeMode="NoResize" SizeToContent="WidthAndHeight"
        FontFamily="Segoe UI" FontSize="12">
  <Window.Resources>
    <Style x:Key="Mini" TargetType="Button">
      <Setter Property="Foreground" Value="#9CA3AF"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Margin" Value="6,0,0,0"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="#22FFFFFF" CornerRadius="5" Padding="7,1">
            <ContentPresenter VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#55FFFFFF"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="L" TargetType="TextBlock"><Setter Property="Foreground" Value="#9CA3AF"/><Setter Property="Margin" Value="0,1,14,1"/></Style>
    <Style x:Key="V" TargetType="TextBlock"><Setter Property="Foreground" Value="#F3F4F6"/><Setter Property="FontFamily" Value="Consolas"/><Setter Property="FontSize" Value="13"/><Setter Property="Margin" Value="0,1,0,1"/></Style>
  </Window.Resources>
  <Border Background="#E6151B21" CornerRadius="10" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="12,8,12,10" MinWidth="250">
    <StackPanel>
      <DockPanel Margin="0,0,0,6">
        <Button x:Name="mClose" DockPanel.Dock="Right" Style="{StaticResource Mini}" Content="X" ToolTip="Fermer le moniteur et rouvrir PUBG GL Expert"/>
        <Button x:Name="mSetup" DockPanel.Dock="Right" Style="{StaticResource Mini}" Content="App" ToolTip="Rouvrir PUBG GL Expert"/>
        <Button x:Name="mMin" DockPanel.Dock="Right" Style="{StaticResource Mini}" Content="_" ToolTip="Reduire Metrics dans la barre des taches"/>
        <TextBlock Text="METRICS" Foreground="#4ADE80" FontWeight="Bold" FontSize="13" VerticalAlignment="Center"/>
      </DockPanel>
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
          <RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Style="{StaticResource L}" Text="GPU"/>          <TextBlock Grid.Row="0" Grid.Column="1" x:Name="vGpu"  Style="{StaticResource V}" Text="..."/>
        <TextBlock Grid.Row="1" Style="{StaticResource L}" Text="Temp. GPU"/>    <TextBlock Grid.Row="1" Grid.Column="1" x:Name="vTemp" Style="{StaticResource V}" Text="..."/>
        <TextBlock Grid.Row="2" Style="{StaticResource L}" Text="VRAM"/>         <TextBlock Grid.Row="2" Grid.Column="1" x:Name="vVram" Style="{StaticResource V}" Text="..."/>
        <TextBlock Grid.Row="3" Style="{StaticResource L}" Text="CPU"/>          <TextBlock Grid.Row="3" Grid.Column="1" x:Name="vCpu"  Style="{StaticResource V}" Text="..."/>
        <TextBlock Grid.Row="4" Style="{StaticResource L}" Text="Coeur max"/>    <TextBlock Grid.Row="4" Grid.Column="1" x:Name="vCore" Style="{StaticResource V}" Text="..."/>
        <TextBlock Grid.Row="5" Style="{StaticResource L}" Text="Emulateur"/>    <TextBlock Grid.Row="5" Grid.Column="1" x:Name="vEmu"  Style="{StaticResource V}" Text="..."/>
        <TextBlock Grid.Row="6" Style="{StaticResource L}" Text="RAM PC"/>       <TextBlock Grid.Row="6" Grid.Column="1" x:Name="vRam"  Style="{StaticResource V}" Text="..."/>
      </Grid>
      <TextBlock x:Name="vDiag" Margin="0,7,0,0" FontWeight="SemiBold" TextWrapping="Wrap" MaxWidth="260" Foreground="#9CA3AF" Text="Mesure en cours..."/>
      <TextBlock x:Name="vSrc" Margin="0,2,0,0" FontSize="10" Foreground="#6B7280"/>
    </StackPanel>
  </Border>
</Window>
'@

$script:Mon = $null
$script:MonPs = $null
$MonPosFile = Join-Path $DataRoot 'monitor-position.txt'

function Get-LoadColor($v, [double]$warn, [double]$bad) {
  if ($null -eq $v) { '#9CA3AF' } elseif ($v -ge $bad) { '#F87171' } elseif ($v -ge $warn) { '#FBBF24' } else { '#4ADE80' }
}
function Set-MonValue([string]$name, [string]$text, [string]$color) {
  $script:mu[$name].Text = $text
  if ($color) { $script:mu[$name].Foreground = $color }
}

function Start-MonitorSampler {
  $script:MonSync = [hashtable]::Synchronized(@{ Run = $true })
  $rs = [runspacefactory]::CreateRunspace()
  $rs.Open()
  $ps = [powershell]::Create()
  $ps.Runspace = $rs
  [void]$ps.AddScript($MonitorSampler).AddArgument($script:MonSync)
  [void]$ps.BeginInvoke()
  $script:MonPs = $ps
}
function Stop-MonitorSampler {
  if (-not $script:MonPs) { return }
  $script:MonSync.Run = $false
  try { [void]$script:MonPs.BeginStop($null, $null) } catch { }
  $script:MonPs = $null
}

function Update-Monitor {
  $S = $script:MonSync
  if (-not $S -or -not $S.Stamp) { return }
  if (([DateTime]::UtcNow - $S.Stamp).TotalSeconds -gt 5) { $script:mu.vDiag.Text = 'Mesures en retard...'; return }
  # moyennes glissantes pour le diagnostic (evite les faux pics)
  if ($null -ne $S.Gpu)    { $script:EmaGpu  = if ($null -eq $script:EmaGpu)  { $S.Gpu }    else { 0.6 * $script:EmaGpu  + 0.4 * $S.Gpu } }
  if ($null -ne $S.CpuMax) { $script:EmaCore = if ($null -eq $script:EmaCore) { $S.CpuMax } else { 0.6 * $script:EmaCore + 0.4 * $S.CpuMax } }

  if ($null -ne $S.Gpu) {
    $clk = if ($S.GpuClock) { "  $($S.GpuClock) MHz" } else { '' }
    Set-MonValue 'vGpu' ("{0,3} %{1}" -f $S.Gpu, $clk) (Get-LoadColor $S.Gpu 80 95)
  } else { Set-MonValue 'vGpu' 'indisponible' '#9CA3AF' }
  if ($null -ne $S.GpuTemp) { Set-MonValue 'vTemp' ("{0,3} C" -f $S.GpuTemp) (Get-LoadColor $S.GpuTemp 75 85) }
  else { Set-MonValue 'vTemp' 'n/d' '#6B7280' }
  if ($null -ne $S.VramUsed) {
    $tot = if ($S.VramTotal) { " / $($S.VramTotal)" } else { '' }
    $pct = if ($S.VramTotal) { 100 * $S.VramUsed / $S.VramTotal } else { $null }
    Set-MonValue 'vVram' ("{0} Mo{1}" -f $S.VramUsed, $tot) (Get-LoadColor $pct 80 92)
  } else { Set-MonValue 'vVram' 'n/d' '#6B7280' }
  if ($null -ne $S.Cpu) {
    Set-MonValue 'vCpu'  ("{0,3} %" -f $S.Cpu) (Get-LoadColor $S.Cpu 75 90)
    Set-MonValue 'vCore' ("{0,3} %" -f $S.CpuMax) (Get-LoadColor $S.CpuMax 85 97)
  }
  if ($S.EmuRunning) { Set-MonValue 'vEmu' ("CPU {0} %  |  {1:N1} Go" -f $S.EmuCpu, $S.EmuRam) '#F3F4F6' }
  else { Set-MonValue 'vEmu' 'ferme' '#6B7280' }
  if ($null -ne $S.RamUsed) {
    Set-MonValue 'vRam' ("{0:N1} / {1:N0} Go" -f $S.RamUsed, $S.RamTotal) (Get-LoadColor (100 * $S.RamUsed / $S.RamTotal) 80 92)
  }

  $g = $script:EmaGpu; $c = $script:EmaCore
  if (-not $S.EmuRunning) { $d = 'GameLoop ferme'; $col = '#9CA3AF' }
  elseif ($null -ne $S.GpuTemp -and $S.GpuTemp -ge 85) { $d = 'GPU tres chaud : verifier la ventilation'; $col = '#F87171' }
  elseif ($null -ne $g -and $g -ge 95) { $d = 'Limite : carte graphique (baisser resolution ou qualite)'; $col = '#FBBF24' }
  elseif ($null -ne $c -and $c -ge 90 -and ($null -eq $g -or $g -lt 70)) { $d = 'Limite : processeur / emulateur (un coeur sature)'; $col = '#FBBF24' }
  elseif ($null -ne $S.RamUsed -and $S.RamUsed / $S.RamTotal -ge 0.92) { $d = 'Memoire presque pleine'; $col = '#FBBF24' }
  else { $d = 'Marge disponible : les FPS sont limites par le jeu'; $col = '#4ADE80' }
  Set-MonValue 'vDiag' $d $col
  $script:mu.vSrc.Text = "GPU : $($S.GpuSrc)  |  " + (Get-Date -Format 'HH:mm:ss')
}

function Restore-MainWindow {
  $script:Front.WindowState = 'Normal'
  [void]$script:Front.Activate()
}

function Close-Monitor {
  if (-not $script:Mon) { return }
  try { Set-Content -LiteralPath $MonPosFile -Value ("{0};{1}" -f [int]$script:Mon.Left, [int]$script:Mon.Top) } catch { }
  $script:MonTimer.Stop()
  Stop-MonitorSampler
  $m = $script:Mon
  $script:Mon = $null
  $m.Close()
}

function Show-Monitor {
  if ($script:Mon) { [void]$script:Mon.Activate(); $script:Front.WindowState = 'Minimized'; return }
  $m = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $MonXaml))
  $script:mu = @{}
  foreach ($n in 'mClose','mSetup','mMin','vGpu','vTemp','vVram','vCpu','vCore','vEmu','vRam','vDiag','vSrc') { $script:mu[$n] = $m.FindName($n) }

  $wa = [System.Windows.SystemParameters]::WorkArea
  $m.Left = $wa.Left + 16; $m.Top = $wa.Top + 16
  if (Test-Path $MonPosFile) {
    $pos = (Get-Content -LiteralPath $MonPosFile -Raw).Trim() -split ';'
    $x = 0; $y = 0
    if ($pos.Count -eq 2 -and [int]::TryParse($pos[0], [ref]$x) -and [int]::TryParse($pos[1], [ref]$y) -and
        $x -ge [System.Windows.SystemParameters]::VirtualScreenLeft -and $y -ge [System.Windows.SystemParameters]::VirtualScreenTop -and
        $x -lt ([System.Windows.SystemParameters]::VirtualScreenLeft + [System.Windows.SystemParameters]::VirtualScreenWidth - 60) -and
        $y -lt ([System.Windows.SystemParameters]::VirtualScreenTop + [System.Windows.SystemParameters]::VirtualScreenHeight - 40)) {
      $m.Left = $x; $m.Top = $y
    }
  }
  $m.Add_MouseLeftButtonDown({ try { $script:Mon.DragMove() } catch { } })
  $script:mu.mSetup.Add_Click({ Safe { Restore-MainWindow } })
  $script:mu.mMin.Add_Click({ try { $script:Mon.WindowState = 'Minimized' } catch { } })
  $script:mu.mClose.Add_Click({ Safe { Close-Monitor; Restore-MainWindow } })
  $m.Add_Closed({ if ($script:Mon) { $script:Mon = $null; $script:MonTimer.Stop(); Stop-MonitorSampler; Restore-MainWindow } })

  $script:EmaGpu = $null; $script:EmaCore = $null
  $script:Mon = $m
  Start-MonitorSampler
  $script:MonTimer = New-Object System.Windows.Threading.DispatcherTimer
  $script:MonTimer.Interval = [TimeSpan]::FromMilliseconds(1000)
  $script:MonTimer.Add_Tick({ try { Update-Monitor } catch { } })
  $script:MonTimer.Start()
  $m.Show()
  $script:Front.WindowState = 'Minimized'
  Log 'Metrics : moniteur ouvert (PUBG GL Expert reduit).'
}

# ---------------- Evenements ----------------
function Safe([scriptblock]$sb) { try { & $sb } catch { Log "ERREUR : $($_.Exception.Message)"; Info $_.Exception.Message 'Error' } }

$ui.cbBuild.Add_SelectionChanged({ Safe { Load-Current } })
$ui.cbRes.Add_SelectionChanged({
  if ($script:Loading) { return }
  $r = $Resolutions[[string]$ui.cbRes.SelectedItem]
  if ($r) { $ui.tbW.Text = $r[0]; $ui.tbH.Text = $r[1]; Safe { Update-Ratio } }
})
$ui.tbW.Add_LostFocus({ Safe { Update-Ratio } })
$ui.tbH.Add_LostFocus({ Safe { Update-Ratio } })
foreach ($pn in $Presets.Keys) {
  $ui["btnPreset$pn"].Tag = $pn
  $ui["btnPreset$pn"].Add_Click({ param($sender, $e) Safe { Apply-Preset ([string]$sender.Tag) } })
}
$ui.btnReload.Add_Click({ Safe { Load-Current; Log 'Valeurs actuelles relues.' } })
$ui.btnApply.Add_Click({ Safe { Apply-Settings (Get-FormSettings); Update-Status } })
$ui.btnLaunchGame.Add_Click({ Safe { Start-AndroidPackage (Current-Pkg) } })
$ui.btnLaunchStore.Add_Click({ Safe { Start-AndroidPackage 'com.android.vending' } })
$ui.btnDetect.Add_Click({ Safe {
  Update-Status
  $r = Get-InstalledBuilds
  $ui.dotAdb.Fill = '#22C55E'; $ui.tbAdb.Text = 'ADB connecte'
  $found = @($Builds.Keys | Where-Object { $r[$_] })
  $ui.tbInstalled.Text = "Versions installees : " + $(if ($found) { $found -join ', ' } else { 'aucune' }) +
                         "   |   Play Store : " + $(if ($r['PlayStore']) { 'oui' } else { 'non' })
  if ($found -and -not $r[[string]$ui.cbBuild.SelectedItem]) { $ui.cbBuild.SelectedItem = $found[0] }
  Log $ui.tbInstalled.Text
} })
$ui.btnChooseFolder.Add_Click({ Safe { if (Choose-GameLoopFolder) { Update-Status; Update-UpdateBlockUi; Info "GameLoop : $GameLoopUi" } } })
$ui.btnKmSave.Add_Click({ Safe { Save-KeymapForSize } })
$ui.btnKmRestore.Add_Click({ Safe { if (Restore-KeymapForSize (Get-SizeKey)) { Info "Keymap de $(Get-SizeKey) remise en place." } } })
$ui.lbKmSizes.Add_MouseDoubleClick({ Safe {
  $sz = [string]$ui.lbKmSizes.SelectedItem
  if ($sz -match '^(\d+)x(\d+)$') { $script:Loading = $true; $ui.tbW.Text = $Matches[1]; $ui.tbH.Text = $Matches[2]; $ui.cbRes.SelectedItem = 'Personnalisee'; $script:Loading = $false; Update-Ratio }
} })
$ui.btnProfSave.Add_Click({ Safe { Save-Profile } })
$ui.btnProfLoad.Add_Click({ Safe { Load-Profile } })
$ui.btnProfDelete.Add_Click({ Safe { Delete-Profile } })
$ui.btnBackupNow.Add_Click({ Safe { Backup-Registry 'manuel' | Out-Null; Refresh-Backups } })
$ui.btnRestore.Add_Click({ Safe { Restore-Backup } })
$ui.btnOpenFolder.Add_Click({ Start-Process explorer.exe $DataRoot })
$ui.btnOptimize.Add_Click({ Safe { Invoke-Optimize } })
$ui.optAffinity.Add_Checked({ $ui.optPriority.IsChecked = $true })
$ui.btnWinPagefile.Add_Click({ Safe { Info "Dans la fenetre qui s'ouvre : onglet Avance > Modifier. Pour revenir en arriere, recochez 'Gestion automatique'."; Start-Process 'SystemPropertiesPerformance.exe' } })
$ui.btnWinUpdate.Add_Click({ Safe { Info "Utilisez 'Suspendre les mises a jour' plutot que de les couper : elles reprennent seules a la fin de la pause."; Start-Process 'ms-settings:windowsupdate' } })
$ui.btnWinDrivers.Add_Click({ Safe { Info "Dans la fenetre qui s'ouvre : 'Parametres d'installation de peripherique' > Non. Repassez sur Oui pour annuler."; Start-Process 'SystemPropertiesHardware.exe' } })
$ui.btnGpuDriver.Add_Click({ Safe { Open-GpuDriverPage } })
$ui.btnMonitor.Add_Click({ Safe { Show-Monitor } })
$ui.btnUpdBlock.Add_Click({ Safe { Switch-UpdateBlock } })
$ui.btnStartBlock.Add_Click({ Safe { Switch-StartupBlock } })
$ui.btnCloseAll.Add_Click({ Safe { Close-AllGameLoop } })
$ui.btnInstallOld.Add_Click({ Safe { Install-OldGameLoop } })
$ui.btnGameMode.Add_Click({ Safe { Show-GameModeDialog } })

# ---------------- Assistant pas a pas (v4) ----------------
# Fenetre principale de la v4 : 8 etapes, de l'installation protegee de l'ancien GameLoop
# jusqu'au lancement personnalise. Chaque etape reutilise les fonctions de l'outil (memes
# scripts administrateur que les boutons de la v3.5). L'ancienne fenetre reste disponible :
# bouton "Mode expert".
$WizardFile = Join-Path $DataRoot 'wizard.json'
$WzSteps = @('Diagnostic du PC', 'Protections', 'Installation GameLoop', 'Émulateur et PUBG', 'Verrouillage final', 'Affichage et touches', 'Optimisation', 'Lancement')
$WzColors = @{
  ok   = @('#4ADE80', '#1F3B2E'); warn = @('#FB923C', '#4A2716'); bad  = @('#F87171', '#4A1D1D')
  info = @('#8D96A8', '#232937'); run  = @('#F5B83D', '#3A3322'); todo = @('#5B6477', '#1B2029')
}
$WzGlyph = @{ ok = [string][char]0xE73E; warn = [string][char]0xE7BA; bad = [string][char]0xE711; info = [string][char]0xE946; run = [string][char]0xE895; todo = '' }
$script:WzOk = @{}
$script:WzPage = 1

# Protections avant installation (etape 2) : meme effet que le debut de l'installation protegee.
$ProtectScript = @'
param([string]$Root, [string]$Shared, [string]$Out)
$log = New-Object System.Collections.Generic.List[string]
try {
  if (-not (Test-Path -LiteralPath $Shared)) { New-Item -ItemType Directory -Force -Path $Shared | Out-Null }
  & icacls.exe $Shared /deny '*S-1-1-0:(OI)(IO)(X)' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "icacls a echoue ($LASTEXITCODE)" }
  $log.Add("execution interdite dans $Shared")
  foreach ($f in @(Get-ChildItem -LiteralPath $Shared -Filter 'com_tencent_gameloop_*.exe' -File -ErrorAction SilentlyContinue)) {
    Rename-Item -LiteralPath $f.FullName -NewName ($f.Name + '.bloque') -Force
    $log.Add("installateur neutralise : $($f.Name)")
  }
  Get-NetFirewallRule -DisplayName 'PubgSetup - Anti-migration*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  $pa = Join-Path $Root 'AppMarket\PcyybAssistant.exe'
  New-NetFirewallRule -DisplayName 'PubgSetup - Anti-migration (PcyybAssistant.exe)' -Group 'PubgSetup' -Direction Outbound -Action Block -Program $pa -Profile Any | Out-Null
  $log.Add('pare-feu : PcyybAssistant sans Internet')
  if (Test-Path -LiteralPath $pa) {
    Get-Process -Name PcyybAssistant -ErrorAction SilentlyContinue | Stop-Process -Force
    if (Test-Path -LiteralPath "$pa.bloque") { Remove-Item -LiteralPath "$pa.bloque" -Force }
    Rename-Item -LiteralPath $pa -NewName 'PcyybAssistant.exe.bloque'
    $log.Add('PcyybAssistant desactive')
  }
  foreach ($rk in 'HKLM:\SOFTWARE\WOW6432Node\Tencent\MobileGamePC\AppMarket', 'HKLM:\SOFTWARE\Tencent\MobileGamePC\AppMarket') {
    if ($null -ne (Get-ItemProperty -LiteralPath $rk -Name AutoStart -ErrorAction SilentlyContinue)) {
      $kind = (Get-Item -LiteralPath $rk).GetValueKind('AutoStart')
      $v = if ($kind -eq 'String') { '0' } else { 0 }
      New-ItemProperty -LiteralPath $rk -Name AutoStart -PropertyType $kind -Value $v -Force | Out-Null
      $log.Add("AutoStart = 0 ($rk)")
    }
  }
  $log.Insert(0, 'OK')
} catch { $log.Insert(0, 'ERREUR : ' + $_.Exception.Message) }
Set-Content -LiteralPath $Out -Value ($log -join "`r`n")
'@

# Verrouillage final (etape 5) : blocage des MAJ + blocage au demarrage, une seule demande UAC.
$LockScript = @'
param([string]$UpdPs1, [string]$StartPs1, [string]$Exes, [string]$FwOnly, [string]$Shared, [string]$State, [string]$Out)
$log = New-Object System.Collections.Generic.List[string]
try {
  & $UpdPs1 -Mode Block -Exes $Exes -FwOnly $FwOnly -Shared $Shared -Out "$Out.upd"
  $log.Add('MAJ : ' + ((Get-Content -LiteralPath "$Out.upd" -Raw).Trim() -replace "`r?`n", ' ; '))
  & $StartPs1 -Mode Block -State $State -Out "$Out.start"
  $log.Add('Demarrage : ' + ((Get-Content -LiteralPath "$Out.start" -Raw).Trim() -replace "`r?`n", ' ; '))
} catch { $log.Add('ERREUR : ' + $_.Exception.Message) }
Set-Content -LiteralPath $Out -Value ($log -join "`r`n")
'@

# Lance un script en administrateur (UAC) sans geler la fenetre. $null = autorisation refusee.
function Invoke-Elevated([string]$name, [string]$scriptText, [string]$argTail, [scriptblock]$onTick) {
  $dir = Join-Path $DataRoot 'app'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $ps1 = Join-Path $dir "$name.ps1"
  $out = Join-Path $dir "$name.result.txt"
  Set-Content -LiteralPath $ps1 -Value $scriptText -Encoding UTF8
  Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
  $argLine = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1`" $argTail -Out `"$out`""
  try {
    $p = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $argLine -Verb RunAs -WindowStyle Hidden -PassThru
  } catch { return $null }
  while (-not $p.HasExited) {
    Start-Sleep -Milliseconds 250
    if ($onTick -and (Test-Path -LiteralPath $out)) { try { & $onTick ([string](Get-Content -LiteralPath $out -Raw -ErrorAction Stop)) } catch { } }
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{ }, [System.Windows.Threading.DispatcherPriority]::Background)
  }
  if (Test-Path -LiteralPath $out) { (Get-Content -LiteralPath $out -Raw).Trim() } else { 'aucun resultat (operation annulee ?)' }
}

# ---------- Detection ----------
function Get-NewGameLoopDir {
  foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if (-not $pf) { continue }
    $app = Join-Path $pf 'Tencent\GameLoop\Application'
    if ((Test-Path -LiteralPath $app) -and @(Get-ChildItem -LiteralPath $app -Filter 'GameLoop*.exe' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue).Count) { return $app }
  }
  $null
}
function Test-OldInstalled { $r = Get-GameLoopRoot; [bool]($r -and (Test-Path -LiteralPath (Join-Path $r 'AppMarket\AppMarket.exe'))) }
function Sync-GameLoopUi {
  # l'emulateur vient d'etre installe : on le prend sans relancer la recherche complete
  if ($GameLoopUi) { return }
  $r = Get-GameLoopRoot
  if ($r) { $u = Test-GameLoopUi (Join-Path $r 'ui'); if ($u) { Set-GameLoopUi $u; Log "GameLoop detecte : $u" } }
}
function Test-AntiMigrRule {
  try { [bool]@(Get-NetFirewallRule -DisplayName 'PubgSetup - Anti-migration*' -ErrorAction SilentlyContinue).Count } catch { $false }
}
function Test-PcyybOff {
  $r = Get-GameLoopRoot
  if (-not $r -or -not (Test-Path -LiteralPath (Join-Path $r 'AppMarket'))) { return $null }
  -not (Test-Path -LiteralPath (Join-Path $r 'AppMarket\PcyybAssistant.exe'))
}
function Test-PubgPresent {
  if (-not (Test-Path $RegPath)) { return $false }
  [bool]@((Get-Item $RegPath).GetValueNames() | Where-Object { $_ -match '^(com\.tencent\.ig|com\.vng\.pubgmobile|com\.pubg\.krmobile|com\.rekoo\.pubgm)_' }).Count
}
function Get-WzSysInfo {
  $s = @{ Cpu = ''; RamGb = 0; Virt = $null; FreeGb = $null }
  try { $s.Cpu = ((Get-CimInstance Win32_Processor | Select-Object -First 1).Name -replace '\s+', ' ').Trim() } catch { }
  try { $s.RamGb = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB) } catch { }
  try {
    $v = [bool](Get-CimInstance Win32_Processor | Select-Object -First 1).VirtualizationFirmwareEnabled
    $h = [bool](Get-CimInstance Win32_ComputerSystem).HypervisorPresent
    $s.Virt = $v -or $h
  } catch { }
  try { $s.FreeGb = [math]::Round((Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))).Free / 1GB) } catch { }
  $s
}

# ---------- Reglages memorises de l'assistant ----------
function Read-WzCfg {
  $c = @{ Profile = 'ipad'; Build = 'Global'; GameMode = $false; Monitor = $true; Shader = $true; Gpu = $true; Keymap = $true }
  if (Test-Path -LiteralPath $WizardFile) {
    try { $j = Get-Content -LiteralPath $WizardFile -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $c[$p.Name] = $p.Value } } catch { }
  }
  $c
}
function Save-WzCfg {
  $c = $script:WzCfg
  $c.Build = [string]$wu.cbBuildW.SelectedItem
  $c.GameMode = [bool]$wu.chkLaunchGM.IsChecked; $c.Monitor = [bool]$wu.chkLaunchMon.IsChecked
  $c.Shader = [bool]$wu.chkShaderW.IsChecked; $c.Gpu = [bool]$wu.chkGpuW.IsChecked; $c.Keymap = [bool]$wu.chkKmW.IsChecked
  try { $c | ConvertTo-Json | Set-Content -LiteralPath $WizardFile -Encoding UTF8 } catch { }
}

# ---------- Interface ----------
[xml]$WzXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PUBG GL Expert" Width="1060" Height="720" MinWidth="980" MinHeight="660"
        WindowStartupLocation="CenterScreen" Background="#0E1117" Foreground="#E6E9EF"
        FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True">
  <Window.Resources>
    <Style x:Key="WBtn" TargetType="Button">
      <Setter Property="Background" Value="#1B2029"/><Setter Property="Foreground" Value="#C9CFDA"/>
      <Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Padding" Value="18,0"/>
      <Setter Property="Height" Value="42"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Margin" Value="0,0,10,0"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="10" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.85"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="WPrimary" TargetType="Button" BasedOn="{StaticResource WBtn}">
      <Setter Property="Background" Value="#F5B83D"/><Setter Property="Foreground" Value="#0E1117"/><Setter Property="FontWeight" Value="Bold"/>
    </Style>
    <Style x:Key="WNav" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Margin" Value="0,0,0,2"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button"><ContentPresenter/></ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="WCard" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/><Setter Property="Background" Value="#161B24"/><Setter Property="BorderBrush" Value="#161B24"/>
      <Setter Property="Foreground" Value="#E6E9EF"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="2" CornerRadius="14" Padding="16">
            <ContentPresenter/>
          </Border>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Kicker" TargetType="TextBlock"><Setter Property="Foreground" Value="#F5B83D"/><Setter Property="FontSize" Value="12"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Margin" Value="0,0,0,4"/></Style>
    <Style x:Key="H1" TargetType="TextBlock"><Setter Property="FontSize" Value="28"/><Setter Property="FontWeight" Value="Bold"/><Setter Property="FontFamily" Value="Segoe UI Variable Display, Segoe UI"/><Setter Property="Margin" Value="0,0,0,6"/></Style>
    <Style x:Key="Desc" TargetType="TextBlock"><Setter Property="Foreground" Value="#A9B1C1"/><Setter Property="FontSize" Value="14"/><Setter Property="TextWrapping" Value="Wrap"/><Setter Property="Margin" Value="0,0,0,18"/><Setter Property="MaxWidth" Value="640"/><Setter Property="HorizontalAlignment" Value="Left"/></Style>
    <Style x:Key="Sec" TargetType="TextBlock"><Setter Property="Foreground" Value="#8D96A8"/><Setter Property="FontSize" Value="11"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Margin" Value="0,0,0,8"/></Style>
    <Style x:Key="Box" TargetType="Border"><Setter Property="Background" Value="#161B24"/><Setter Property="CornerRadius" Value="14"/><Setter Property="Padding" Value="16"/></Style>
    <Style TargetType="CheckBox"><Setter Property="Foreground" Value="#E6E9EF"/><Setter Property="Margin" Value="0,0,0,10"/><Setter Property="Cursor" Value="Hand"/></Style>
  </Window.Resources>

  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="250"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

    <!-- Barre laterale -->
    <Border Background="#141821" BorderBrush="#232937" BorderThickness="0,0,1,0" Padding="16,22,16,16">
      <DockPanel>
        <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="6,0,0,22">
          <Border Width="34" Height="34" CornerRadius="9" Background="#F5B83D">
            <TextBlock Text="&#xEA18;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#0E1117" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
            <TextBlock Text="PUBG GL Expert" FontWeight="Bold" FontSize="16"/>
            <TextBlock x:Name="tbWzVer" Foreground="#8D96A8" FontSize="11"/>
          </StackPanel>
        </StackPanel>
        <StackPanel DockPanel.Dock="Bottom">
          <Border Background="#10141B" CornerRadius="10" Padding="12" Margin="0,0,0,10">
            <StackPanel>
              <TextBlock Text="PROTECTION ANTI-MIGRATION" Foreground="#8D96A8" FontSize="10" FontWeight="SemiBold" Margin="0,0,0,6"/>
              <StackPanel Orientation="Horizontal">
                <Ellipse x:Name="dotProt" Width="8" Height="8" Fill="#8D96A8" Margin="0,0,8,0" VerticalAlignment="Center"/>
                <TextBlock x:Name="tbProt" Text="..." Foreground="#C9CFDA" FontSize="12" TextWrapping="Wrap"/>
              </StackPanel>
            </StackPanel>
          </Border>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Button x:Name="btnWzMonitor" Style="{StaticResource WBtn}" Content="Metrics" Padding="6,0" Margin="0,0,5,0" ToolTip="Petit moniteur GPU / CPU en temps reel"/>
            <Button x:Name="btnWzExpert" Grid.Column="1" Style="{StaticResource WBtn}" Content="Mode expert" Padding="6,0" Margin="5,0,0,0" ToolTip="Ancienne fenetre avec tous les reglages"/>
          </Grid>
          <Button x:Name="btnDiscord" Style="{StaticResource WBtn}" Content="Contact · Discord" Background="#5865F2" Foreground="White" Height="36" Margin="0,10,0,0" ToolTip="https://discord.gg/qVRBMt74h"/>
          <TextBlock HorizontalAlignment="Center" FontSize="11" Foreground="#8D96A8" Margin="0,10,0,0"><Run Text="Developed by "/><Run Text="TNL YORYO" Foreground="#F5B83D" FontWeight="SemiBold"/></TextBlock>
        </StackPanel>
        <StackPanel x:Name="navPanel"/>
      </DockPanel>
    </Border>

    <!-- Contenu -->
    <Grid Grid.Column="1">
      <Grid.RowDefinitions><RowDefinition Height="4"/><RowDefinition Height="*"/><RowDefinition Height="78"/></Grid.RowDefinitions>
      <Grid Background="#1B2029">
        <Grid.ColumnDefinitions><ColumnDefinition x:Name="progC1" Width="1*"/><ColumnDefinition x:Name="progC2" Width="7*"/></Grid.ColumnDefinitions>
        <Border Background="#F5B83D"/>
      </Grid>

      <Grid x:Name="pages" Grid.Row="1" Margin="36,28,36,0">

        <!-- 1 Diagnostic -->
        <DockPanel x:Name="page1">
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Style="{StaticResource Kicker}" Text="ÉTAPE 1 SUR 8"/>
            <TextBlock Style="{StaticResource H1}" Text="Analyse de votre PC"/>
            <TextBlock Style="{StaticResource Desc}" Text="On vérifie que tout est prêt avant d'installer l'ancien GameLoop. Rien n'est modifié à cette étape."/>
          </StackPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="rows1"/></ScrollViewer>
        </DockPanel>

        <!-- 2 Protections -->
        <DockPanel x:Name="page2" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Style="{StaticResource Kicker}" Text="ÉTAPE 2 SUR 8"/>
            <TextBlock Style="{StaticResource H1}" Text="Protections anti-migration"/>
            <TextBlock Style="{StaticResource Desc}" Text="Avant l'installation, on empêche GameLoop de télécharger et lancer le nouveau GameLoop 7, même sous un autre nom. Tout est réversible depuis le mode expert."/>
          </StackPanel>
          <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,8,0,16">
            <Button x:Name="btnAct2" Style="{StaticResource WPrimary}" Content="Poser les protections"/>
            <TextBlock Text="Windows va demander l'autorisation administrateur." Foreground="#8D96A8" VerticalAlignment="Center" FontSize="12"/>
          </StackPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="rows2"/></ScrollViewer>
        </DockPanel>

        <!-- 3 Installation -->
        <DockPanel x:Name="page3" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Style="{StaticResource Kicker}" Text="ÉTAPE 3 SUR 8"/>
            <TextBlock Style="{StaticResource H1}" Text="Installation de l'ancien GameLoop"/>
            <TextBlock Style="{StaticResource Desc}" Text="Les protections sont reposées juste avant l'installation : GameLoop ne pourra ni se mettre à jour, ni installer GameLoop 7."/>
          </StackPanel>
          <Border DockPanel.Dock="Bottom" Background="#13201A" BorderBrush="#1F4030" BorderThickness="1" CornerRadius="12" Padding="14,10" Margin="0,8,0,16">
            <TextBlock Foreground="#BBF7D0" FontSize="13" TextWrapping="Wrap" Text="Si GameLoop affiche « Mise à niveau vers la dernière version », fermez simplement la fenêtre : elle ne pourra rien installer."/>
          </Border>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="230"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Border Style="{StaticResource Box}" VerticalAlignment="Top">
              <StackPanel>
                <TextBlock x:Name="tbInstBig" Text="Prêt" FontSize="22" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,6"/>
                <TextBlock x:Name="tbInstSub" Text="L'installateur de l'ancien GameLoop va être lancé." Foreground="#A9B1C1" TextWrapping="Wrap" Margin="0,0,0,14"/>
                <ProgressBar x:Name="pbInst" Height="6" Foreground="#F5B83D" Background="#232937" BorderThickness="0" Margin="0,0,0,16" Visibility="Hidden"/>
                <Button x:Name="btnAct3" Style="{StaticResource WPrimary}" Content="Installer" Margin="0"/>
              </StackPanel>
            </Border>
            <ScrollViewer Grid.Column="2" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="rows3"/></ScrollViewer>
          </Grid>
        </DockPanel>

        <!-- 4 Emulateur et PUBG -->
        <DockPanel x:Name="page4" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Style="{StaticResource Kicker}" Text="ÉTAPE 4 SUR 8"/>
            <TextBlock Style="{StaticResource H1}" Text="Émulateur et PUBG"/>
            <TextBlock Style="{StaticResource Desc}" Text="Ouvrez GameLoop et laissez-le installer le moteur Android, puis installez PUBG Mobile depuis GameLoop. Si une fenêtre propose une mise à niveau, fermez-la. Cette page se met à jour toute seule."/>
          </StackPanel>
          <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,8,0,16">
            <Button x:Name="btnAct4" Style="{StaticResource WPrimary}" Content="Ouvrir GameLoop"/>
            <TextBlock x:Name="tbAuto4" Text="Vérification automatique toutes les 4 secondes" Foreground="#8D96A8" VerticalAlignment="Center" FontSize="12"/>
          </StackPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="rows4"/></ScrollViewer>
        </DockPanel>

        <!-- 5 Verrouillage -->
        <DockPanel x:Name="page5" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Style="{StaticResource Kicker}" Text="ÉTAPE 5 SUR 8"/>
            <TextBlock Style="{StaticResource H1}" Text="Verrouillage final"/>
            <TextBlock Style="{StaticResource Desc}" Text="Maintenant que l'émulateur est installé, on bloque aussi le programme de mise à jour et le lancement au démarrage du PC. L'anti-triche n'est jamais touché."/>
          </StackPanel>
          <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,8,0,16">
            <Button x:Name="btnAct5" Style="{StaticResource WPrimary}" Content="Tout verrouiller"/>
            <TextBlock Text="Une seule autorisation administrateur pour tout." Foreground="#8D96A8" VerticalAlignment="Center" FontSize="12"/>
          </StackPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="rows5"/></ScrollViewer>
        </DockPanel>

        <!-- 6 Affichage -->
        <DockPanel x:Name="page6" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Style="{StaticResource Kicker}" Text="ÉTAPE 6 SUR 8 · FACULTATIF"/>
            <TextBlock Style="{StaticResource H1}" Text="Affichage et touches"/>
            <TextBlock Style="{StaticResource Desc}" Text="Choisissez votre vue. La keymap enregistrée pour cette taille est remise en place automatiquement."/>
          </StackPanel>
          <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,8,0,16">
            <Button x:Name="btnAct6" Style="{StaticResource WPrimary}" Content="Appliquer ces réglages"/>
            <TextBlock Text="GameLoop doit être fermé. Une sauvegarde est faite avant." Foreground="#8D96A8" VerticalAlignment="Center" FontSize="12"/>
          </StackPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto">
            <StackPanel>
              <Grid Margin="0,0,0,14">
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Button x:Name="cardWide" Style="{StaticResource WCard}" Tag="wide">
                  <StackPanel>
                    <Border Height="70" CornerRadius="8" Background="#10141B" Margin="0,0,0,12"><Border Width="100" Height="56" BorderBrush="#3A4254" BorderThickness="2" CornerRadius="4"/></Border>
                    <TextBlock Text="Plein écran 16:9" FontWeight="SemiBold" FontSize="14"/>
                    <TextBlock x:Name="subWide" Foreground="#8D96A8" FontSize="12" TextWrapping="Wrap"/>
                  </StackPanel>
                </Button>
                <Button x:Name="cardIpad" Grid.Column="2" Style="{StaticResource WCard}" Tag="ipad">
                  <StackPanel>
                    <Border Height="70" CornerRadius="8" Background="#10141B" Margin="0,0,0,12"><Border Width="75" Height="56" BorderBrush="#3A4254" BorderThickness="2" CornerRadius="4"/></Border>
                    <TextBlock Text="Vue iPad 4:3" FontWeight="SemiBold" FontSize="14"/>
                    <TextBlock x:Name="subIpad" Foreground="#8D96A8" FontSize="12" TextWrapping="Wrap"/>
                  </StackPanel>
                </Button>
                <Button x:Name="cardLight" Grid.Column="4" Style="{StaticResource WCard}" Tag="light">
                  <StackPanel>
                    <Border Height="70" CornerRadius="8" Background="#10141B" Margin="0,0,0,12"><Border Width="72" Height="40" BorderBrush="#3A4254" BorderThickness="2" CornerRadius="4"/></Border>
                    <TextBlock Text="Léger 720p" FontWeight="SemiBold" FontSize="14"/>
                    <TextBlock x:Name="subLight" Foreground="#8D96A8" FontSize="12" TextWrapping="Wrap"/>
                  </StackPanel>
                </Button>
              </Grid>
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Border Style="{StaticResource Box}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource Sec}" Text="VERSION DE PUBG"/>
                    <ComboBox x:Name="cbBuildW" Height="34" Margin="0,0,0,8" VerticalContentAlignment="Center"/>
                    <TextBlock Foreground="#8D96A8" FontSize="12" TextWrapping="Wrap" Text="Celle que vous avez installée dans GameLoop. Sert aux réglages et au lancement."/>
                  </StackPanel>
                </Border>
                <Border Grid.Column="2" Style="{StaticResource Box}">
                  <StackPanel>
                    <TextBlock Style="{StaticResource Sec}" Text="OPTIONS"/>
                    <CheckBox x:Name="chkKmW" Content="Remettre la keymap de cette taille"/>
                    <CheckBox x:Name="chkShaderW" Content="Cache de shaders (moins de saccades)"/>
                    <CheckBox x:Name="chkGpuW" Content="Utiliser la carte graphique dédiée" Margin="0"/>
                  </StackPanel>
                </Border>
              </Grid>
              <Border Style="{StaticResource Box}" Margin="0,12,0,0">
                <DockPanel>
                  <Button x:Name="btnGlSettings" DockPanel.Dock="Right" Style="{StaticResource WBtn}" Content="Paramètres GameLoop" Margin="12,0,0,0" VerticalAlignment="Center"/>
                  <StackPanel>
                    <TextBlock Style="{StaticResource Sec}" Text="DÉTECTÉ AUTOMATIQUEMENT DANS GAMELOOP"/>
                    <TextBlock x:Name="tbDetRender" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,2"/>
                    <TextBlock x:Name="tbDetFps" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,6"/>
                    <TextBlock x:Name="tbDetTip" Foreground="#8D96A8" FontSize="12" TextWrapping="Wrap"/>
                  </StackPanel>
                </DockPanel>
              </Border>
            </StackPanel>
          </ScrollViewer>
        </DockPanel>

        <!-- 7 Optimisation -->
        <DockPanel x:Name="page7" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Style="{StaticResource Kicker}" Text="ÉTAPE 7 SUR 8 · FACULTATIF"/>
            <TextBlock Style="{StaticResource H1}" Text="Optimisation"/>
            <TextBlock Style="{StaticResource Desc}" Text="Libérez de la mémoire et donnez la priorité au jeu. Les pilotes, l'antivirus et l'anti-triche ne sont jamais touchés."/>
          </StackPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto">
            <StackPanel>
              <Border Style="{StaticResource Box}" Margin="0,0,0,10">
                <DockPanel>
                  <Button x:Name="btnGameModeW" DockPanel.Dock="Right" Style="{StaticResource WPrimary}" Content="Choisir et fermer" Margin="12,0,0,0"/>
                  <StackPanel VerticalAlignment="Center">
                    <TextBlock Text="Mode jeu" FontWeight="SemiBold" FontSize="14"/>
                    <TextBlock Foreground="#8D96A8" FontSize="12" TextWrapping="Wrap" Text="Fermez les applications inutiles (navigateur, discussions, lanceurs). Vous cochez celles à fermer, vos choix sont retenus."/>
                  </StackPanel>
                </DockPanel>
              </Border>
              <Border Style="{StaticResource Box}" Margin="0,0,0,10">
                <DockPanel>
                  <Button x:Name="btnOptimizeW" DockPanel.Dock="Right" Style="{StaticResource WBtn}" Content="Optimiser" Margin="12,0,0,0"/>
                  <StackPanel VerticalAlignment="Center">
                    <TextBlock Text="Optimisation en un clic" FontWeight="SemiBold" FontSize="14"/>
                    <TextBlock Foreground="#8D96A8" FontSize="12" TextWrapping="Wrap" Text="Modèle d'appareil SM-X910, processus GameLoop secondaires fermés, priorité haute, fichiers temporaires nettoyés. Une sauvegarde du registre est faite avant."/>
                  </StackPanel>
                </DockPanel>
              </Border>
              <Border Style="{StaticResource Box}">
                <DockPanel>
                  <Button x:Name="btnGpuDrvW" DockPanel.Dock="Right" Style="{StaticResource WBtn}" Content="Pilote graphique" Margin="12,0,0,0"/>
                  <StackPanel VerticalAlignment="Center">
                    <TextBlock Text="Pilote de la carte graphique" FontWeight="SemiBold" FontSize="14"/>
                    <TextBlock x:Name="tbGpuW" Foreground="#8D96A8" FontSize="12" TextWrapping="Wrap"/>
                  </StackPanel>
                </DockPanel>
              </Border>
            </StackPanel>
          </ScrollViewer>
        </DockPanel>

        <!-- 8 Lancement -->
        <DockPanel x:Name="page8" Visibility="Collapsed">
          <StackPanel DockPanel.Dock="Top">
            <TextBlock x:Name="kick8" Style="{StaticResource Kicker}" Text="ÉTAPE 8 SUR 8"/>
            <TextBlock x:Name="h8" Style="{StaticResource H1}" Text="Tout est prêt, bon jeu"/>
            <WrapPanel x:Name="chips8" Margin="0,4,0,16"/>
          </StackPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="14"/><ColumnDefinition Width="250"/></Grid.ColumnDefinitions>
            <Border Style="{StaticResource Box}">
              <StackPanel>
                <TextBlock Style="{StaticResource Sec}" Text="AU LANCEMENT"/>
                <CheckBox x:Name="chkLaunchGM" Content="Mode jeu d'abord (choisir les applis à fermer)"/>
                <CheckBox x:Name="chkLaunchMon" Content="Ouvrir Metrics (GPU, CPU, mémoire) au-dessus du jeu"/>
                <Button x:Name="btnCloseAllW" Style="{StaticResource WBtn}" Content="Tout fermer (GameLoop et PUBG)" HorizontalAlignment="Left" Foreground="#F87171" Margin="0,6,0,0"/>
              </StackPanel>
            </Border>
            <Border Grid.Column="2" Style="{StaticResource Box}">
              <StackPanel>
                <TextBlock Style="{StaticResource Sec}" Text="VOTRE PROFIL"/>
                <TextBlock x:Name="tbProf" Foreground="#C9CFDA" FontSize="13" LineHeight="22" TextWrapping="Wrap"/>
              </StackPanel>
            </Border>
          </Grid>
            <Border Style="{StaticResource Box}" Margin="0,14,0,16">
              <StackPanel>
                <TextBlock Style="{StaticResource Sec}" Text="CONSEILS DANS PUBG · PARAMÈTRES &gt; GRAPHISMES"/>
                <TextBlock FontSize="13" Margin="0,0,0,4" TextWrapping="Wrap"><Run Text="Graphismes : " Foreground="#8D96A8"/><Run Text="Lisse" FontWeight="SemiBold"/><Run Text=" (plus d'images par seconde)" Foreground="#8D96A8"/></TextBlock>
                <TextBlock FontSize="13" Margin="0,0,0,4" TextWrapping="Wrap"><Run Text="Fréquence d'images : " Foreground="#8D96A8"/><Run Text="120 ips" FontWeight="SemiBold"/><Run Text=" si PUBG la propose, sinon la plus haute (90 / Extrême)" Foreground="#8D96A8"/></TextBlock>
                <TextBlock FontSize="13" Margin="0,0,0,4" TextWrapping="Wrap"><Run Text="Style : " Foreground="#8D96A8"/><Run Text="Coloré" FontWeight="SemiBold"/><Run Text=" (les ennemis ressortent mieux)" Foreground="#8D96A8"/></TextBlock>
                <TextBlock FontSize="13" Margin="0,0,0,4" TextWrapping="Wrap"><Run Text="Réglage : " Foreground="#8D96A8"/><Run Text="manuel" FontWeight="SemiBold"/><Run Text=", désactivez « Ajustement auto des graphismes »" Foreground="#8D96A8"/></TextBlock>
                <TextBlock FontSize="13" Margin="0,0,0,8" TextWrapping="Wrap"><Run Text="Anticrénelage et ombres : " Foreground="#8D96A8"/><Run Text="désactivés" FontWeight="SemiBold"/></TextBlock>
                <TextBlock FontSize="12" Foreground="#8D96A8" TextWrapping="Wrap" Text="Dans GameLoop, PUBG Global est limité à 90 ips (choix proposés : auto, 30, 40, 60, 90). Réglez GameLoop sur 90, puis le maximum dans PUBG."/>
              </StackPanel>
            </Border>
          </StackPanel>
          </ScrollViewer>
        </DockPanel>
      </Grid>

      <!-- Pied -->
      <Border x:Name="footer" Grid.Row="2" BorderBrush="#232937" BorderThickness="0,1,0,0" Padding="36,0">
        <DockPanel VerticalAlignment="Center">
          <Button x:Name="btnBack" DockPanel.Dock="Left" Style="{StaticResource WBtn}" Content="Retour"/>
          <Button x:Name="btnNext" DockPanel.Dock="Right" Style="{StaticResource WPrimary}" Content="Suivant" Margin="0" MinWidth="120"/>
          <Button x:Name="btnRecheck" DockPanel.Dock="Right" Style="{StaticResource WBtn}" Content="Revérifier"/>
          <TextBlock x:Name="tbFoot" Foreground="#8D96A8" FontSize="12" VerticalAlignment="Center" Margin="8,0" TextWrapping="Wrap"/>
        </DockPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
'@
$wz = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $WzXaml))
$wu = @{}
$WzXaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object {
  $n = $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
  if ($n) { $wu[$n] = $wz.FindName($n) }
}
$wu.tbWzVer.Text = "v$AppVersion · ancien GameLoop, sans MAJ"
$DiscordUrl = 'https://discord.gg/qVRBMt74h'

# ---------- Briques d'interface ----------
function New-WzButton([string]$text, [bool]$primary, [scriptblock]$onClick) {
  $b = New-Object System.Windows.Controls.Button
  $b.Style = $wz.FindResource($(if ($primary) { 'WPrimary' } else { 'WBtn' }))
  $b.Content = $text
  $b.Margin = '12,0,0,0'
  $b.Height = 36
  $b.Tag = $onClick
  $b.Add_Click({ param($s, $e) Safe { & $s.Tag } })
  $b
}
function New-WzIcon([string]$state, [double]$size) {
  $c = $WzColors[$state]
  $ic = New-Object System.Windows.Controls.Border
  $ic.Width = $size; $ic.Height = $size
  $ic.CornerRadius = New-Object System.Windows.CornerRadius ($size / 2)
  $ic.Background = $c[1]
  if ($state -eq 'todo') { $ic.BorderBrush = '#3A4254'; $ic.BorderThickness = 1.5; $ic.Background = 'Transparent' }
  $t = New-Object System.Windows.Controls.TextBlock
  $t.Text = $WzGlyph[$state]
  $t.FontFamily = 'Segoe MDL2 Assets'; $t.FontSize = [math]::Round($size * 0.4)
  $t.Foreground = $c[0]; $t.HorizontalAlignment = 'Center'; $t.VerticalAlignment = 'Center'
  $ic.Child = $t
  $ic
}
function Add-WzRow($panel, [string]$state, [string]$title, [string]$sub, $button) {
  $c = $WzColors[$state]
  $b = New-Object System.Windows.Controls.Border
  $b.Background = '#161B24'; $b.CornerRadius = New-Object System.Windows.CornerRadius 12
  $b.Padding = '14,12'; $b.Margin = '0,0,0,8'
  if ($state -eq 'bad' -or $state -eq 'warn') { $b.BorderBrush = $c[1]; $b.BorderThickness = 1 }
  $g = New-Object System.Windows.Controls.Grid
  foreach ($w in @([System.Windows.GridLength]::Auto, (New-Object System.Windows.GridLength 1, 'Star'), [System.Windows.GridLength]::Auto)) {
    $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = $w; [void]$g.ColumnDefinitions.Add($cd)
  }
  $ic = New-WzIcon $state 34
  $ic.VerticalAlignment = 'Center'
  [void]$g.Children.Add($ic)
  $sp = New-Object System.Windows.Controls.StackPanel
  $sp.Margin = '14,0,0,0'; $sp.VerticalAlignment = 'Center'
  [System.Windows.Controls.Grid]::SetColumn($sp, 1)
  $t1 = New-Object System.Windows.Controls.TextBlock
  $t1.Text = $title; $t1.FontSize = 14; $t1.FontWeight = 'SemiBold'; $t1.TextWrapping = 'Wrap'
  $t1.Foreground = $(if ($state -eq 'todo') { '#8D96A8' } else { '#E6E9EF' })
  [void]$sp.Children.Add($t1)
  if ($sub) {
    $t2 = New-Object System.Windows.Controls.TextBlock
    $t2.Text = $sub; $t2.FontSize = 12; $t2.TextWrapping = 'Wrap'; $t2.Margin = '0,2,0,0'
    $t2.Foreground = $(if ($state -eq 'bad' -or $state -eq 'warn') { $c[0] } else { '#8D96A8' })
    [void]$sp.Children.Add($t2)
  }
  [void]$g.Children.Add($sp)
  if ($button) {
    $button.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($button, 2)
    [void]$g.Children.Add($button)
  }
  $b.Child = $g
  [void]$panel.Children.Add($b)
}
function Add-WzChip([string]$state, [string]$text) {
  $c = $WzColors[$state]
  $b = New-Object System.Windows.Controls.Border
  $b.Background = $c[1]; $b.CornerRadius = New-Object System.Windows.CornerRadius 16
  $b.Padding = '10,6,12,6'; $b.Margin = '0,0,8,8'
  $sp = New-Object System.Windows.Controls.StackPanel
  $sp.Orientation = 'Horizontal'
  $i = New-Object System.Windows.Controls.TextBlock
  $i.Text = $WzGlyph[$state]; $i.FontFamily = 'Segoe MDL2 Assets'; $i.FontSize = 11; $i.Foreground = $c[0]
  $i.VerticalAlignment = 'Center'; $i.Margin = '0,0,8,0'
  $t = New-Object System.Windows.Controls.TextBlock
  $t.Text = $text; $t.FontSize = 12; $t.Foreground = '#E6E9EF'; $t.VerticalAlignment = 'Center'
  [void]$sp.Children.Add($i); [void]$sp.Children.Add($t)
  $b.Child = $sp
  [void]$wu.chips8.Children.Add($b)
}

# barre laterale : une entree par etape
for ($i = 1; $i -le 8; $i++) {
  $btn = New-Object System.Windows.Controls.Button
  $btn.Style = $wz.FindResource('WNav'); $btn.Tag = $i
  $bg = New-Object System.Windows.Controls.Border
  $bg.CornerRadius = New-Object System.Windows.CornerRadius 10; $bg.Padding = '10,8'; $bg.Background = 'Transparent'
  $sp = New-Object System.Windows.Controls.StackPanel
  $sp.Orientation = 'Horizontal'
  $dot = New-Object System.Windows.Controls.Border
  $dot.Width = 26; $dot.Height = 26; $dot.CornerRadius = New-Object System.Windows.CornerRadius 13
  $num = New-Object System.Windows.Controls.TextBlock
  $num.HorizontalAlignment = 'Center'; $num.VerticalAlignment = 'Center'; $num.FontSize = 12; $num.FontWeight = 'Bold'
  $dot.Child = $num
  $lbl = New-Object System.Windows.Controls.TextBlock
  $lbl.Text = $WzSteps[$i - 1]; $lbl.Margin = '12,0,0,0'; $lbl.VerticalAlignment = 'Center'; $lbl.FontSize = 13
  [void]$sp.Children.Add($dot); [void]$sp.Children.Add($lbl)
  $bg.Child = $sp
  $btn.Content = $bg
  $btn.Add_Click({ param($s, $e) Safe { Show-WzPage ([int]$s.Tag) } })
  [void]$wu.navPanel.Children.Add($btn)
  $wu["navBg$i"] = $bg; $wu["navDot$i"] = $dot; $wu["navNum$i"] = $num; $wu["navLbl$i"] = $lbl
}

function Update-WzNav {
  for ($i = 1; $i -le 8; $i++) {
    $dot = $wu["navDot$i"]; $num = $wu["navNum$i"]; $lbl = $wu["navLbl$i"]; $bg = $wu["navBg$i"]
    if ($i -eq $script:WzPage) {
      $bg.Background = '#221F17'; $dot.Background = '#F5B83D'; $dot.BorderThickness = 0
      $num.FontFamily = 'Segoe UI'; $num.Text = [string]$i; $num.Foreground = '#0E1117'
      $lbl.Foreground = '#FFFFFF'; $lbl.FontWeight = 'SemiBold'
    } elseif ($script:WzOk[$i]) {
      $bg.Background = 'Transparent'; $dot.Background = '#1F3B2E'; $dot.BorderThickness = 0
      $num.FontFamily = 'Segoe MDL2 Assets'; $num.Text = $WzGlyph.ok; $num.Foreground = '#4ADE80'
      $lbl.Foreground = '#A9B1C1'; $lbl.FontWeight = 'Normal'
    } else {
      $bg.Background = 'Transparent'; $dot.Background = 'Transparent'; $dot.BorderBrush = '#3A4254'; $dot.BorderThickness = 1.5
      $num.FontFamily = 'Segoe UI'; $num.Text = [string]$i; $num.Foreground = '#8D96A8'
      $lbl.Foreground = '#8D96A8'; $lbl.FontWeight = 'Normal'
    }
  }
  # badge de protection
  $prot = Test-SharedNoExec
  if ($script:WzUpdState -eq 'blocked' -and $prot) { $wu.dotProt.Fill = '#4ADE80'; $wu.tbProt.Text = 'Verrouillé · MAJ bloquées' }
  elseif ($prot) { $wu.dotProt.Fill = '#4ADE80'; $wu.tbProt.Text = 'Active · migration bloquée' }
  else { $wu.dotProt.Fill = '#8D96A8'; $wu.tbProt.Text = 'Pas encore posée' }
}

# ---------- Etapes ----------
function Select-OldInstaller {
  Add-Type -AssemblyName System.Windows.Forms
  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  $dlg.Title = "Choisissez l'installateur de l'ancien GameLoop (GLP_installer.exe)"
  $dlg.Filter = 'Installateur (*.exe)|*.exe'
  if ($dlg.ShowDialog() -ne 'OK') { return $null }
  $script:InstallerPath = $dlg.FileName
  Log "Installateur choisi : $($dlg.FileName)"
  $dlg.FileName
}

function Refresh-Wz1 {
  $p = $wu.rows1; $p.Children.Clear()
  $s = $script:WzSys
  Add-WzRow $p 'ok' "Carte graphique : $($script:Reco.Gpu)" "Préréglage conseillé : $($script:Reco.Tier)" $null
  $ramState = if ($s.RamGb -ge 8) { 'ok' } else { 'warn' }
  Add-WzRow $p $ramState "Processeur et mémoire : $($s.RamGb) Go" $(if ($ramState -eq 'ok') { $s.Cpu } else { "$($s.Cpu) · 8 Go conseillés pour l'émulateur" }) $null
  if ($null -ne $s.Virt) {
    if ($s.Virt) { Add-WzRow $p 'ok' 'Virtualisation activée' "Nécessaire pour un émulateur fluide" $null }
    else { Add-WzRow $p 'warn' 'Virtualisation désactivée' "Activez VT-x / AMD-V (SVM) dans le BIOS, sinon l'émulateur sera lent" $null }
  }
  if ($null -ne $s.FreeGb) {
    Add-WzRow $p $(if ($s.FreeGb -ge 10) { 'ok' } else { 'warn' }) "Espace libre sur $($env:SystemDrive) : $($s.FreeGb) Go" $(if ($s.FreeGb -ge 10) { 'Suffisant' } else { 'Au moins 10 Go conseillés' }) $null
  }
  $gl7 = Get-NewGameLoopDir
  if ($gl7) {
    Add-WzRow $p 'bad' 'Nouveau GameLoop 7 détecté' "À désinstaller avant de continuer (Paramètres Windows > Applications > GameLoop). Revenez ici ensuite." (New-WzButton 'Désinstaller' $true { Start-Process 'ms-settings:appsfeatures' })
  } else { Add-WzRow $p 'ok' 'Nouveau GameLoop 7 absent' 'Rien ne remplacera l''ancien GameLoop' $null }
  $old = Test-OldInstalled
  $inst = $null
  if ($old) {
    Add-WzRow $p 'ok' 'Ancien GameLoop installé' (Get-GameLoopRoot) $null
  } else {
    Add-WzRow $p 'info' 'Ancien GameLoop pas encore installé' "Il sera installé à l'étape 3" (New-WzButton 'Déjà installé ailleurs ?' $false { if (Choose-GameLoopFolder) { Show-WzPage 1 } })
    $inst = Find-OldInstaller
    if ($inst) { Add-WzRow $p 'ok' 'Installateur de l''ancien GameLoop trouvé' $inst (New-WzButton 'Changer' $false { if (Select-OldInstaller) { Show-WzPage 1 } }) }
    else { Add-WzRow $p 'bad' 'Installateur de l''ancien GameLoop introuvable' "Placez GLP_installer.exe dans le dossier « gameloop » avant de construire l'exe, ou choisissez-le" (New-WzButton 'Choisir…' $true { if (Select-OldInstaller) { Show-WzPage 1 } }) }
  }
  (-not $gl7) -and ($old -or [bool]$inst)
}

function Refresh-Wz2 {
  $p = $wu.rows2; $p.Children.Clear()
  $acl = Test-SharedNoExec
  $rule = Test-AntiMigrRule
  $pcy = Test-PcyybOff
  if ($acl) { Add-WzRow $p 'ok' 'Exécution interdite dans le dossier de migration' "Le nouveau GameLoop ne peut pas s'installer, même sous un autre nom" $null }
  else { Add-WzRow $p 'todo' 'Interdire l''exécution dans le dossier de migration' $UpdSharedDir $null }
  if ($rule) { Add-WzRow $p 'ok' 'Pare-feu anti-migration' 'PcyybAssistant n''a pas accès à Internet' $null }
  else { Add-WzRow $p 'todo' 'Pare-feu anti-migration' 'Couper Internet à PcyybAssistant (programme de migration)' $null }
  if ($null -eq $pcy) { Add-WzRow $p 'info' 'PcyybAssistant' 'Sera désactivé juste après l''installation' $null }
  elseif ($pcy) { Add-WzRow $p 'ok' 'PcyybAssistant désactivé' 'Renommé en .bloque (réversible)' $null }
  else { Add-WzRow $p 'warn' 'PcyybAssistant actif' 'Cliquez « Poser les protections »' $null }
  $ok = $acl -and $rule -and ($pcy -ne $false)
  $wu.btnAct2.Content = if ($ok) { 'Reposer les protections' } else { 'Poser les protections' }
  $wu.btnAct2.Style = $wz.FindResource($(if ($ok) { 'WBtn' } else { 'WPrimary' }))
  $ok
}

function Render-Wz3([string]$text, [bool]$running) {
  $p = $wu.rows3; $p.Children.Clear()
  $items = @(
    @{ T = 'Exécution interdite dans le dossier de migration'; Done = 'execution interdite'; Warn = $null },
    @{ T = 'Pare-feu anti-migration'; Done = 'pare-feu'; Warn = $null },
    @{ T = 'Installation de GameLoop'; Done = 'installateur termine'; Warn = $null },
    @{ T = 'PcyybAssistant désactivé'; Done = 'PcyybAssistant desactive'; Warn = 'PcyybAssistant absent' },
    @{ T = 'Pas de lancement au démarrage du PC'; Done = 'AutoStart = 0'; Warn = 'AutoStart introuvable' }
  )
  $current = $running
  foreach ($it in $items) {
    if ($text -match [regex]::Escape($it.Done)) { Add-WzRow $p 'ok' $it.T $null $null }
    elseif ($it.Warn -and $text -match [regex]::Escape($it.Warn)) { Add-WzRow $p 'warn' $it.T $(if ($it.Warn -match 'AutoStart') { 'Sera fait au verrouillage final (étape 5)' } else { 'Sera fait aux étapes 2 et 5' }) $null }
    elseif ($current) { Add-WzRow $p 'run' $it.T 'En cours…' $null; $current = $false }
    else { Add-WzRow $p 'todo' $it.T $null $null }
  }
}

function Refresh-Wz3 {
  if ($script:InstRunning) { return $false }
  $old = Test-OldInstalled
  $gl7 = Get-NewGameLoopDir
  if ($old -and -not $gl7) {
    $p = $wu.rows3; $p.Children.Clear()
    Add-WzRow $p 'ok' 'Ancien GameLoop installé' (Get-GameLoopRoot) $null
    Add-WzRow $p 'ok' 'Nouveau GameLoop 7 absent' 'Aucune migration' $null
    $wu.tbInstBig.Text = 'Installé'; $wu.tbInstSub.Text = 'Passez à l''étape suivante.'
    $wu.btnAct3.Content = 'Réinstaller'; $wu.btnAct3.Style = $wz.FindResource('WBtn')
    return $true
  }
  Render-Wz3 ([string]$script:LastInstall) $false
  if ($gl7) { Add-WzRow $wu.rows3 'bad' 'Nouveau GameLoop 7 détecté' 'Désinstallez-le (étape 1) avant d''installer l''ancien' $null }
  $wu.tbInstBig.Text = 'Prêt'; $wu.tbInstSub.Text = 'L''installateur de l''ancien GameLoop va être lancé, protections comprises.'
  $wu.btnAct3.Content = 'Installer'; $wu.btnAct3.Style = $wz.FindResource('WPrimary')
  $false
}

function Refresh-Wz4 {
  Sync-GameLoopUi
  $p = $wu.rows4; $p.Children.Clear()
  $eng = Test-EngineInstalled
  $gl7 = Get-NewGameLoopDir
  if (-not (Test-OldInstalled)) { Add-WzRow $p 'bad' 'Ancien GameLoop non installé' 'Revenez à l''étape 3' $null }
  if ($eng) { Add-WzRow $p 'ok' 'Moteur Android installé' $(if ($GameLoopUi) { $GameLoopUi } else { (Join-Path (Get-GameLoopRoot) 'ui') }) $null }
  else { Add-WzRow $p 'run' 'En attente du moteur Android' 'Ouvrez GameLoop : il le télécharge et l''installe (quelques minutes)' $null }
  if (Test-PubgPresent) { Add-WzRow $p 'ok' 'PUBG Mobile détecté' 'Réglages PUBG présents dans GameLoop' $null }
  else { Add-WzRow $p 'info' 'PUBG Mobile pas encore détecté' 'Installez-le depuis GameLoop puis lancez-le une fois' $null }
  if ($gl7) { Add-WzRow $p 'bad' 'Migration vers GameLoop 7 détectée' "Le nouveau GameLoop s'est installé : désinstallez-le et revenez à l'étape 2" $null }
  else { Add-WzRow $p 'ok' 'Aucune migration' 'Les protections tiennent' $null }
  if (Test-GameLoopRunning) { Add-WzRow $p 'info' 'GameLoop est ouvert' $null $null }
  $eng -and -not $gl7
}

function Refresh-Wz5 {
  $p = $wu.rows5; $p.Children.Clear()
  $eng = Test-EngineInstalled
  $us = Get-UpdateBlockState
  $script:WzUpdState = $us
  $ss = Get-StartupBlockState
  $gl7 = Get-NewGameLoopDir
  switch ($us) {
    'blocked' { Add-WzRow $p 'ok' 'Mises à jour bloquées' 'TUpdate et PcyybAssistant désactivés, téléchargeurs coupés au pare-feu' $null }
    'migr'    { Add-WzRow $p 'warn' 'Programme de mise à jour encore actif' $(if ($eng) { 'Cliquez « Tout verrouiller »' } else { 'Installez d''abord le moteur Android (étape 4)' }) $null }
    'partial' { Add-WzRow $p 'warn' 'Blocage incomplet' 'Un fichier a été remis par GameLoop : cliquez « Tout verrouiller »' $null }
    'unknown' { Add-WzRow $p 'bad' 'Ancien GameLoop introuvable' 'Revenez à l''étape 3' $null }
    default   { Add-WzRow $p 'todo' 'Bloquer les mises à jour de GameLoop' 'TUpdate, PcyybAssistant et téléchargeurs' $null }
  }
  if ($ss -eq 'active') { Add-WzRow $p 'todo' 'Bloquer le lancement au démarrage du PC' 'GameLoop se lance encore tout seul' $null }
  else { Add-WzRow $p 'ok' 'Pas de lancement au démarrage' 'GameLoop ne démarre qu''à votre demande' $null }
  if ($gl7) { Add-WzRow $p 'bad' 'Nouveau GameLoop 7 détecté' 'Désinstallez-le (étape 1)' $null }
  else { Add-WzRow $p 'ok' 'Nouveau GameLoop 7 absent' $null $null }
  $ace = if ($GameLoopUi) { Join-Path $GameLoopUi 'plugins\Updater32.exe' } else { $null }
  if ($ace -and (Test-Path -LiteralPath $ace)) { Add-WzRow $p 'ok' 'Anti-triche intact' 'Son programme de mise à jour n''est jamais bloqué' $null }
  $wu.btnAct5.IsEnabled = [bool]$eng
  $ok = ($us -eq 'blocked') -and ($ss -ne 'active') -and -not $gl7
  $wu.btnAct5.Content = if ($ok) { 'Reverrouiller' } else { 'Tout verrouiller' }
  $wu.btnAct5.Style = $wz.FindResource($(if ($ok) { 'WBtn' } else { 'WPrimary' }))
  $ok
}

function Get-WzPresetName([string]$prof) {
  switch ($prof) {
    'wide'  { return $script:Reco.Tier }
    'light' { return 'Competitif' }
    default { if ($script:Reco.Tier -eq 'Competitif') { return 'Ipad720' } else { return 'Ipad1080' } }
  }
}
function Update-WzCards {
  foreach ($k in 'Wide', 'Ipad', 'Light') {
    $card = $wu["card$k"]
    $pr = $Presets[(Get-WzPresetName $card.Tag)]
    $wu["sub$k"].Text = "$($pr.W) × $($pr.H) · DPI $($pr.Dpi)"
    $sel = ($script:WzCfg.Profile -eq $card.Tag)
    $card.Background = $(if ($sel) { '#221F17' } else { '#161B24' })
    $card.BorderBrush = $(if ($sel) { '#F5B83D' } else { '#161B24' })
  }
  $wu.subWide.Text += " · conseillé pour votre carte"
}

# ---------- Detection du moteur de rendu et des FPS ----------
# Constate le 2026-11-22 : GameLoop ecrit le moteur utilise dans ui\AEngine<vm>.log
# ("local_opengl::start: Renderer=DirectX+") et la resolution ("Resolution:1600x900").
# Les FPS sont dans HKCU\...\MobileGamePC\<paquet>_FPSLevel ; GameLoop propose auto/30/40/60/90.
function Get-GlRenderInfo {
  $r = @{ Renderer = $null; Res = $null; When = $null }
  if (-not $GameLoopUi) { return $r }
  foreach ($l in @(Get-ChildItem -LiteralPath $GameLoopUi -Filter 'AEngine*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
    try {
      $lines = @(Get-Content -LiteralPath $l.FullName -Tail 20000 -ErrorAction Stop)
      for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if (-not $r.Renderer -and $lines[$i] -match 'Renderer=([A-Za-z+]+)') { $r.Renderer = $Matches[1]; $r.When = $l.LastWriteTime }
        if (-not $r.Res -and $lines[$i] -match 'Resolution:(\d+x\d+)') { $r.Res = $Matches[1] }
        if ($r.Renderer -and $r.Res) { break }
      }
    } catch { }
    if ($r.Renderer) { break }
  }
  $r
}
function Get-GlFpsText([string]$pkg) {
  $v = Get-RegValue "${pkg}_FPSLevel"
  if (-not $v) { return 'par défaut (jamais changé dans GameLoop)' }
  $n = 0
  if ([int]::TryParse([string]$v.Value, [ref]$n) -and @(30, 40, 60, 90, 120) -contains $n) { return "$n ips" }
  "niveau $($v.Value) (valeur GameLoop)"
}
function Open-GlSettings {
  $ts = if ($GameLoopUi) { Join-Path $GameLoopUi 'TSettingCenter.exe' } else { $null }
  if ($ts -and (Test-Path -LiteralPath $ts)) { Start-Process -FilePath $ts -WorkingDirectory $GameLoopUi; Log 'Parametres GameLoop ouverts (TSettingCenter.exe).' }
  else { Info "Ouvrez GameLoop, menu (trois traits en haut a droite) > Parametres > Moteur." }
}
function Update-WzDetect {
  $ri = Get-GlRenderInfo
  $pkg = $Builds[[string]$wu.cbBuildW.SelectedItem]
  $fps = Get-GlFpsText $pkg
  $script:WzDet = @{ Renderer = $ri.Renderer; Res = $ri.Res; Fps = $fps }
  $wu.tbDetRender.Text = "Moteur de rendu : " + $(if ($ri.Renderer) { $ri.Renderer } else { 'pas encore détecté' })
  $wu.tbDetFps.Text = "FPS GameLoop (PUBG) : $fps"
  $tips = @()
  if (-not $ri.Renderer) { $tips += 'Lancez PUBG une fois dans GameLoop : le moteur utilisé sera détecté au prochain passage ici.' }
  else {
    $tips += "Lu dans le journal de GameLoop du $($ri.When.ToString('dd/MM HH:mm'))" + $(if ($ri.Res) { ", résolution $($ri.Res)" } else { '' }) + '.'
    if ($script:Reco.Gpu -match 'NVIDIA|GeForce' -and $ri.Renderer -match 'DirectX') { $tips += 'Carte NVIDIA : si le jeu saccade, essayez OpenGL+ (à comparer).' }
    elseif ($script:Reco.Gpu -match 'AMD|Radeon|Intel' -and $ri.Renderer -match 'OpenGL') { $tips += 'Carte AMD / Intel : si le jeu saccade, essayez DirectX+ (à comparer).' }
  }
  if ($fps -notmatch '^90 ') { $tips += 'Conseil : FPS sur 90 dans GameLoop (le maximum proposé pour PUBG Global).' }
  $wu.tbDetTip.Text = $tips -join ' '
}
function Refresh-Wz6 { Update-WzCards; Update-WzDetect; $true }
function Refresh-Wz7 { $wu.tbGpuW.Text = "$($script:Reco.Gpu) : ouvrir la page de téléchargement du dernier pilote."; $true }

function Refresh-Wz8 {
  $wu.chips8.Children.Clear()
  $us = Get-UpdateBlockState; $script:WzUpdState = $us
  $ss = Get-StartupBlockState
  $gl7 = Get-NewGameLoopDir
  Add-WzChip $(if ($us -eq 'blocked') { 'ok' } else { 'warn' }) $(if ($us -eq 'blocked') { 'Mises à jour bloquées' } else { 'Mises à jour NON bloquées (étape 5)' })
  Add-WzChip $(if ($ss -ne 'active') { 'ok' } else { 'warn' }) $(if ($ss -ne 'active') { 'Pas de lancement au démarrage' } else { 'Lancement au démarrage actif' })
  Add-WzChip $(if (-not $gl7) { 'ok' } else { 'bad' }) $(if (-not $gl7) { 'GameLoop 7 ne peut pas s''installer' } else { 'GameLoop 7 détecté' })
  $ace = if ($GameLoopUi) { Join-Path $GameLoopUi 'plugins\Updater32.exe' } else { $null }
  if ($ace -and (Test-Path -LiteralPath $ace)) { Add-WzChip 'ok' 'Anti-triche intact' }
  $all = ($us -eq 'blocked') -and ($ss -ne 'active') -and -not $gl7 -and (Test-OldInstalled)
  $wu.h8.Text = if ($all) { 'Tout est prêt, bon jeu' } else { 'Presque prêt' }
  $wu.kick8.Text = if ($all) { 'ÉTAPE 8 SUR 8 · PRÊT' } else { 'ÉTAPE 8 SUR 8 · À VÉRIFIER' }
  $w = Get-RegValue 'VMResWidth'; $h = Get-RegValue 'VMResHeight'; $d = Get-RegValue 'VMDPI'
  $res = if ($w -and $h) { "$($w.Value) × $($h.Value)" } else { 'non définie' }
  $ratio = ''
  if ($w -and $h -and [int]$h.Value -gt 0) { $r = [int]$w.Value / [int]$h.Value; $ratio = if ([math]::Abs($r - 4/3) -lt 0.02) { 'iPad 4:3' } elseif ([math]::Abs($r - 16/9) -lt 0.02) { '16:9' } else { '{0:N2}:1' -f $r } }
  try { Update-WzDetect } catch { }
  $wu.tbProf.Text = "Version : $([string]$wu.cbBuildW.SelectedItem)`nRésolution : $res`nFormat : $(if ($ratio) { $ratio } else { '-' })`nDPI : $(if ($d) { $d.Value } else { '-' })`nMoteur : $(if ($script:WzDet.Renderer) { $script:WzDet.Renderer } else { '-' })`nFPS GameLoop : $($script:WzDet.Fps)"
  $true
}

function Refresh-WzPage([int]$n) {
  $ok = switch ($n) { 1 { Refresh-Wz1 } 2 { Refresh-Wz2 } 3 { Refresh-Wz3 } 4 { Refresh-Wz4 } 5 { Refresh-Wz5 } 6 { Refresh-Wz6 } 7 { Refresh-Wz7 } 8 { Refresh-Wz8 } }
  $ok = [bool]$ok
  $script:WzOk[$n] = $ok -and $n -le 5
  if ($n -ge 6) { $script:WzOk[$n] = $script:WzOk[$n] -or ($script:WzSeen -contains $n) }
  $ok
}

function Update-WzFooter {
  $n = $script:WzPage
  $wu.btnBack.IsEnabled = $n -gt 1
  $ok = if ($n -le 5) { [bool]$script:WzOk[$n] } else { $true }
  if ($n -eq 8) { $wu.btnNext.Content = 'Lancer PUBG'; $wu.btnNext.IsEnabled = Test-OldInstalled }
  else { $wu.btnNext.Content = 'Suivant'; $wu.btnNext.IsEnabled = $ok }
  $wu.tbFoot.Text = switch ($n) {
    1 { if ($ok) { 'Tout est bon.' } else { 'Corrigez les points en rouge pour continuer.' } }
    2 { if ($ok) { 'Protections en place.' } else { 'Posez les protections pour continuer.' } }
    3 { if ($ok) { 'Ancien GameLoop installé.' } else { 'Installez l''ancien GameLoop pour continuer.' } }
    4 { if ($ok) { 'Moteur installé.' } else { 'En attente du moteur Android.' } }
    5 { if ($ok) { 'Verrouillé.' } else { 'Verrouillez pour continuer.' } }
    8 { 'PUBG est lancé par GameLoop, sans ADB.' }
    default { 'Étape facultative.' }
  }
}

function Show-WzPage([int]$n) {
  if ($n -lt 1 -or $n -gt 8) { return }
  $script:WzPage = $n
  if ($n -ge 6 -and $script:WzSeen -notcontains $n) { $script:WzSeen += $n }
  for ($i = 1; $i -le 8; $i++) { $wu["page$i"].Visibility = $(if ($i -eq $n) { 'Visible' } else { 'Collapsed' }) }
  $wu.progC1.Width = New-Object System.Windows.GridLength $n, 'Star'
  $wu.progC2.Width = New-Object System.Windows.GridLength (8 - $n), 'Star'
  $wz.Cursor = 'Wait'
  try { [void](Refresh-WzPage $n) } finally { $wz.Cursor = $null }
  Update-WzNav
  Update-WzFooter
  if ($n -eq 4) { $script:WzTimer.Start() } else { $script:WzTimer.Stop() }
}

function Set-WzBusy([bool]$b) {
  $wu.navPanel.IsEnabled = -not $b
  $wu.footer.IsEnabled = -not $b
  $wu.pages.IsEnabled = -not $b
  $wu.btnWzExpert.IsEnabled = -not $b
  $wz.Cursor = $(if ($b) { 'AppStarting' } else { $null })
}

# ---------- Actions ----------
function Invoke-WzProtect {
  $root = Get-GameLoopRoot
  if (-not $root) { $root = Join-Path $env:ProgramFiles 'TxGameAssistant' }
  Set-WzBusy $true
  try { $res = Invoke-Elevated 'gameloop-protect' $ProtectScript "-Root `"$root`" -Shared `"$UpdSharedDir`"" $null } finally { Set-WzBusy $false }
  if ($null -eq $res) { Log 'Protections : autorisation administrateur refusee.'; Info "Windows n'a pas donné l'autorisation administrateur : rien n'a été changé." 'Warning'; return }
  ($res -split "`r?`n") | ForEach-Object { Log "Protections : $_" }
  if ($res -notmatch '^OK') { Info $res 'Warning' }
  Show-WzPage 2
}

function Invoke-WzInstall {
  if (Get-NewGameLoopDir) { Info "Le nouveau GameLoop 7 est encore installé. Désinstallez-le d'abord (étape 1)." 'Warning'; Show-WzPage 1; return }
  if ((Test-OldInstalled) -and -not (Ask "L'ancien GameLoop est déjà installé. Relancer son installateur ?")) { return }
  $inst = Find-OldInstaller
  if (-not $inst) { $inst = Select-OldInstaller; if (-not $inst) { return } }
  $root = Join-Path $env:ProgramFiles 'TxGameAssistant'
  Log "Assistant : installation de l'ancien GameLoop : $inst"
  $script:InstRunning = $true
  $script:LastInstall = ''; $script:InstTick = ''
  Set-WzBusy $true
  $wu.pbInst.Visibility = 'Visible'; $wu.pbInst.IsIndeterminate = $true
  $wu.tbInstBig.Text = 'Installation en cours'
  $wu.tbInstSub.Text = 'Acceptez la demande Windows, puis suivez l''installateur de GameLoop.'
  Render-Wz3 '' $true
  try {
    $res = Invoke-Elevated 'gameloop-install-old' $OldInstallScript "-Installer `"$inst`" -Root `"$root`" -Shared `"$UpdSharedDir`"" { param($t) if ($t -ne $script:InstTick) { $script:InstTick = $t; Render-Wz3 $t $true } }
  } finally {
    $script:InstRunning = $false
    Set-WzBusy $false
    $wu.pbInst.IsIndeterminate = $false; $wu.pbInst.Visibility = 'Hidden'
  }
  if ($null -eq $res) { Log 'Installation : autorisation administrateur refusee.'; $wu.tbInstBig.Text = 'Annulé'; $wu.tbInstSub.Text = 'Windows n''a pas donné l''autorisation administrateur.'; Render-Wz3 '' $false; return }
  ($res -split "`r?`n") | ForEach-Object { Log "Installation : $_" }
  $script:LastInstall = $res
  Set-GameLoopUi (Find-GameLoopUi)
  Update-Status; Update-UpdateBlockUi; Update-StartupBlockUi
  Render-Wz3 $res $false
  $gl7 = Get-NewGameLoopDir
  $ok = ($res -match '^OK') -and (Test-OldInstalled) -and -not $gl7
  if ($ok) {
    Add-WzRow $wu.rows3 'ok' 'Contrôle final' 'Ancien GameLoop présent, GameLoop 7 absent' $null
    $wu.tbInstBig.Text = 'Terminé'; $wu.tbInstSub.Text = 'Passez à l''étape suivante pour installer le moteur et PUBG.'
  } else {
    $why = if ($gl7) { 'GameLoop 7 a été détecté' } elseif (-not (Test-OldInstalled)) { 'AppMarket introuvable' } else { ($res -split "`r?`n")[0] }
    Add-WzRow $wu.rows3 'bad' 'Contrôle final' $why $null
    $wu.tbInstBig.Text = 'À vérifier'; $wu.tbInstSub.Text = 'Voir le journal dans le mode expert.'
  }
  $script:WzOk[3] = $ok
  $script:WzOk[2] = [bool](Refresh-Wz2)
  Update-WzNav; Update-WzFooter
}

function Invoke-WzOpenGameLoop {
  $r = Get-GameLoopRoot
  $am = if ($r) { Join-Path $r 'AppMarket\AppMarket.exe' } else { $null }
  if (-not $am -or -not (Test-Path -LiteralPath $am)) { Info 'AppMarket.exe introuvable : installez d''abord l''ancien GameLoop (étape 3).' 'Warning'; return }
  Start-Process -FilePath $am
  Log 'Assistant : GameLoop ouvert (AppMarket.exe).'
}

function Invoke-WzLock {
  if (-not (Test-EngineInstalled)) { Info "Le moteur Android n'est pas encore installé : TUpdate doit rester actif pour l'installer. Terminez l'étape 4 d'abord." 'Warning'; return }
  $dir = Join-Path $DataRoot 'app'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $upd = Join-Path $dir 'gameloop-update-block.ps1'
  Set-Content -LiteralPath $upd -Value $UpdBlockScript -Encoding UTF8
  $st = Join-Path $dir 'gameloop-startup-block.ps1'
  Set-Content -LiteralPath $st -Value ("param([string]`$Mode, [string]`$State, [string]`$Out)`r`n" + $StartupLib + "`r`n" + $StartupMain) -Encoding UTF8
  $tail = "-UpdPs1 `"$upd`" -StartPs1 `"$st`" -Exes `"$((Get-UpdTargetPaths) -join '|')`" -FwOnly `"$((Get-UpdFwOnlyPaths) -join '|')`" -Shared `"$UpdSharedDir`" -State `"$StartupStateFile`""
  if (Test-GameLoopRunning) {
    if (-not (Ask "GameLoop est ouvert. Le verrouillage ferme son programme de mise à jour s'il tourne, sans fermer le jeu.`n`nContinuer ?")) { return }
  }
  Set-WzBusy $true
  try { $res = Invoke-Elevated 'gameloop-final-lock' $LockScript $tail $null } finally { Set-WzBusy $false }
  if ($null -eq $res) { Log 'Verrouillage : autorisation administrateur refusee.'; Info "Windows n'a pas donné l'autorisation administrateur : rien n'a été changé." 'Warning'; return }
  ($res -split "`r?`n") | ForEach-Object { Log "Verrouillage : $_" }
  Update-UpdateBlockUi; Update-StartupBlockUi
  if ($res -match 'ERREUR') { Info $res 'Warning' }
  Show-WzPage 5
}

function Invoke-WzApply {
  $b = [string]$wu.cbBuildW.SelectedItem
  if ($b -and [string]$ui.cbBuild.SelectedItem -ne $b) { $ui.cbBuild.SelectedItem = $b }
  $name = Get-WzPresetName $script:WzCfg.Profile
  Apply-Preset $name
  $ui.cbDevice.SelectedIndex = 0
  $ui.chkShader.IsChecked = [bool]$wu.chkShaderW.IsChecked
  $ui.chkGpu.IsChecked = [bool]$wu.chkGpuW.IsChecked
  $ui.chkAutoKm.IsChecked = [bool]$wu.chkKmW.IsChecked
  Save-WzCfg
  Apply-Settings (Get-FormSettings)
}

function Invoke-WzLaunch {
  Save-WzCfg
  $us = Get-UpdateBlockState
  if ($us -ne 'blocked' -and -not (AskNo "Les mises à jour de GameLoop ne sont pas bloquées (étape 5).`nGameLoop pourrait se mettre à jour ou migrer vers GameLoop 7.`n`nLancer quand même ?")) { return }
  if ($wu.chkLaunchGM.IsChecked) { Show-GameModeDialog }
  $b = [string]$wu.cbBuildW.SelectedItem
  if (-not $b) { $b = 'Global' }
  Start-AndroidPackage $Builds[$b]
  if ($wu.chkLaunchMon.IsChecked) { Show-Monitor }
}

function Show-Expert {
  $wz.Hide()
  $script:Front = $win
  Update-Status; Update-UpdateBlockUi; Update-StartupBlockUi
  $win.Show(); [void]$win.Activate()
}

# ---------- Evenements de l'assistant ----------
$script:WzSeen = @()
$script:WzTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:WzTimer.Interval = [TimeSpan]::FromSeconds(4)
$script:WzTimer.Add_Tick({
  try {
    if ($script:WzPage -ne 4 -or -not $wz.IsVisible -or -not $wu.pages.IsEnabled) { return }
    $before = [bool]$script:WzOk[4]
    [void](Refresh-WzPage 4)
    if ($before -ne [bool]$script:WzOk[4]) { Update-WzNav }
    Update-WzFooter
  } catch { }
})
$wu.btnBack.Add_Click({ Safe { Show-WzPage ($script:WzPage - 1) } })
$wu.btnNext.Add_Click({ Safe { if ($script:WzPage -eq 8) { Invoke-WzLaunch } else { Show-WzPage ($script:WzPage + 1) } } })
$wu.btnRecheck.Add_Click({ Safe { Show-WzPage $script:WzPage } })
$wu.btnAct2.Add_Click({ Safe { Invoke-WzProtect } })
$wu.btnAct3.Add_Click({ Safe { Invoke-WzInstall } })
$wu.btnAct4.Add_Click({ Safe { Invoke-WzOpenGameLoop } })
$wu.btnAct5.Add_Click({ Safe { Invoke-WzLock } })
$wu.btnAct6.Add_Click({ Safe { Invoke-WzApply; Refresh-Wz8 | Out-Null } })
foreach ($k in 'Wide', 'Ipad', 'Light') {
  $wu["card$k"].Add_Click({ param($s, $e) Safe { $script:WzCfg.Profile = [string]$s.Tag; Update-WzCards } })
}
$wu.btnGameModeW.Add_Click({ Safe { Show-GameModeDialog } })
$wu.btnOptimizeW.Add_Click({ Safe { Invoke-Optimize } })
$wu.btnGpuDrvW.Add_Click({ Safe { Open-GpuDriverPage } })
$wu.btnCloseAllW.Add_Click({ Safe { Close-AllGameLoop } })
$wu.btnWzMonitor.Add_Click({ Safe { Show-Monitor } })
$wu.btnWzExpert.Add_Click({ Safe { Show-Expert } })
$wu.btnDiscord.Add_Click({ Safe { Start-Process $DiscordUrl } })
$wu.btnGlSettings.Add_Click({ Safe { Open-GlSettings } })

function Initialize-Wizard {
  $script:Reco = Get-Recommendation
  $script:WzSys = Get-WzSysInfo
  $script:WzCfg = Read-WzCfg
  $Builds.Keys | ForEach-Object { [void]$wu.cbBuildW.Items.Add($_) }
  $wu.cbBuildW.SelectedItem = $(if ($Builds.Contains([string]$script:WzCfg.Build)) { [string]$script:WzCfg.Build } else { 'Global' })
  $wu.chkLaunchGM.IsChecked = [bool]$script:WzCfg.GameMode
  $wu.chkLaunchMon.IsChecked = [bool]$script:WzCfg.Monitor
  $wu.chkShaderW.IsChecked = [bool]$script:WzCfg.Shader
  $wu.chkGpuW.IsChecked = [bool]$script:WzCfg.Gpu
  $wu.chkKmW.IsChecked = [bool]$script:WzCfg.Keymap
  # on evalue les etapes obligatoires et on ouvre la premiere qui n'est pas au vert
  $start = 8
  for ($i = 1; $i -le 5; $i++) {
    $ok = [bool](Refresh-WzPage $i)
    if (-not $ok -and $start -eq 8) { $start = $i }
  }
  if ($start -eq 8) { $script:WzSeen = @(6, 7) }
  Show-WzPage $start
  Log "Assistant : ouverture a l'etape $start ($($WzSteps[$start - 1]))."
}

# ---------------- Demarrage ----------------
Safe {
  $ui.tbAdb.Text = ''
  Update-Status
  $reco = Get-Recommendation
  $ui["rec$($reco.Tier)"].Visibility = 'Visible'
  $ui.tbReco.Text = "Carte graphique : $($reco.Gpu). Conseille : $($reco.Tier)."
  if ($GameLoopUi -and -not (Test-Path $RegPath)) { Log "Cle $RegNative absente : lancez GameLoop une fois sur ce PC." }
  Load-Current
  Refresh-Profiles; Refresh-Backups
  Update-UpdateBlockUi
  Update-StartupBlockUi
  Log "PUBG GL Expert v$AppVersion pret. GameLoop : $(if ($GameLoopUi) { "$GameLoopUi ($script:FoundBy)" } else { 'introuvable' })"
}
# v4 : l'assistant est la fenetre principale ; "Mode expert" affiche l'ancienne fenetre.
$script:Front = $wz
$script:Quitting = $false
$win.Title = 'PUBG GL Expert - mode expert'
$win.Add_Closing({ param($s, $e)
  if ($script:Quitting) { return }
  # fermer le mode expert ramene a l'assistant
  $e.Cancel = $true
  $win.Hide()
  $script:Front = $wz
  $wz.Show(); [void]$wz.Activate()
  Safe { Show-WzPage $script:WzPage }
})
$wz.Add_Closed({
  $script:Quitting = $true
  try { $script:WzTimer.Stop() } catch { }
  try { Close-Monitor } catch { }
  try { $win.Close() } catch { }
  try { Log 'Fermeture.' } catch { }
  $script:Frame.Continue = $false
})
Safe { Initialize-Wizard }
$script:Frame = New-Object System.Windows.Threading.DispatcherFrame
$wz.Show()
[System.Windows.Threading.Dispatcher]::PushFrame($script:Frame)
# Fin propre : arrete tout ce que l'outil a lance en arriere-plan (serveur adb compris)
try { if ($Adb -and (Test-Path $Adb)) { [void](Invoke-Adb @('kill-server') 3000) } } catch { }
[Environment]::Exit(0)
