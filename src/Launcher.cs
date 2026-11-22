// PUBG GL Expert - lanceur .exe (developed by TNL YORYO)
// Contient PubgSetup.ps1 (et, s'il etait present a la construction, GLP_installer.exe) en ressources.
// Les extrait dans %LOCALAPPDATA%\PubgSetup\app et execute le script avec PowerShell (console cachee).
// Le manifeste (app.manifest) demande les droits administrateur au lancement.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("PUBG GL Expert")]
[assembly: AssemblyProduct("PUBG GL Expert")]
[assembly: AssemblyCompany("TNL YORYO")]
[assembly: AssemblyDescription("Ancien GameLoop sans mises a jour + reglages PUBG Mobile")]
[assembly: AssemblyVersion("4.1.0.0")]
[assembly: AssemblyFileVersion("4.1.0.0")]

static class Program
{
    const string Title = "PUBG GL Expert";

    [STAThread]
    static int Main()
    {
        bool first;
        using (Mutex m = new Mutex(true, "PubgSetup_SingleInstance", out first))
        {
            if (!first)
            {
                MessageBox.Show("PUBG GL Expert est deja ouvert.", Title, MessageBoxButtons.OK, MessageBoxIcon.Information);
                return 0;
            }
            try
            {
                Assembly asm = Assembly.GetExecutingAssembly();
                string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PubgSetup", "app");
                Directory.CreateDirectory(dir);
                string ps1 = Path.Combine(dir, "PubgSetup.ps1");
                string err = Path.Combine(dir, "last-error.txt");
                if (File.Exists(err)) File.Delete(err);
                using (Stream s = asm.GetManifestResourceStream("PubgSetup.ps1"))
                using (FileStream f = File.Create(ps1))
                {
                    s.CopyTo(f);
                }
                string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
                string cmd = "try { & '" + ps1.Replace("'", "''") + "' } catch { $_ | Out-String | Set-Content -LiteralPath '"
                           + err.Replace("'", "''") + "'; exit 1 }; exit 0";
                ProcessStartInfo psi = new ProcessStartInfo(ps,
                    "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -Command \"" + cmd + "\"");
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.EnvironmentVariables["PUBGSETUP_EXEDIR"] = AppDomain.CurrentDomain.BaseDirectory;

                // Installateur de l'ancien GameLoop integre (facultatif)
                using (Stream r = asm.GetManifestResourceStream("GLP_installer.exe"))
                {
                    if (r != null)
                    {
                        string inst = Path.Combine(dir, "GLP_installer.exe");
                        if (!File.Exists(inst) || new FileInfo(inst).Length != r.Length)
                        {
                            using (FileStream f = File.Create(inst)) { r.CopyTo(f); }
                        }
                        psi.EnvironmentVariables["PUBGSETUP_INSTALLER"] = inst;
                    }
                }

                using (Process p = Process.Start(psi))
                {
                    p.WaitForExit();
                    if (p.ExitCode != 0 && File.Exists(err))
                        MessageBox.Show(File.ReadAllText(err), Title + " - erreur", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return p.ExitCode;
                }
            }
            catch (Exception e)
            {
                MessageBox.Show(e.Message, Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }
    }
}
