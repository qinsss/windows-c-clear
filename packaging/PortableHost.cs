using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("C盘清理助手")]
[assembly: AssemblyDescription("安全优先的 Windows C 盘用户数据清理工具")]
[assembly: AssemblyCompany("qinsss")]
[assembly: AssemblyProduct("C盘清理助手")]
[assembly: AssemblyCopyright("Copyright © 2026 qinsss")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

internal static class PortableHost
{
    [STAThread]
    private static int Main(string[] arguments)
    {
        string temporaryDirectory = Path.Combine(Path.GetTempPath(), "WindowsCClear-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(temporaryDirectory);
            ExtractResource("Cleaner.Core.ps1", Path.Combine(temporaryDirectory, "Cleaner.Core.ps1"));
            ExtractResource("app.ico", Path.Combine(temporaryDirectory, "app.ico"));
            string mainScript = Path.Combine(temporaryDirectory, "WindowsCClear.ps1");
            ExtractResource("WindowsCClear.ps1", mainScript);

            string engine = FindPowerShell();
            if (engine == null)
            {
                MessageBox.Show("未找到 PowerShell 运行环境。请启用 Windows PowerShell 或安装 PowerShell 7。",
                    "C 盘清理助手", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 9009;
            }

            string powerShellArguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " + Quote(mainScript);
            foreach (string argument in arguments) powerShellArguments += " " + Quote(argument);

            var startInfo = new ProcessStartInfo
            {
                FileName = engine,
                Arguments = powerShellArguments,
                WorkingDirectory = temporaryDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            using (Process process = Process.Start(startInfo))
            {
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception exception)
        {
            MessageBox.Show("应用启动失败：\r\n" + exception.Message,
                "C 盘清理助手", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            for (int attempt = 0; attempt < 8 && Directory.Exists(temporaryDirectory); attempt++)
            {
                try { Directory.Delete(temporaryDirectory, true); }
                catch { Thread.Sleep(150); }
            }
        }
    }

    private static void ExtractResource(string resourceName, string outputPath)
    {
        using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName))
        {
            if (input == null) throw new InvalidOperationException("缺少内嵌资源：" + resourceName);
            using (FileStream output = File.Create(outputPath)) input.CopyTo(output);
        }
    }

    private static string FindPowerShell()
    {
        string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        string windowsPowerShell = Path.Combine(windows, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        if (File.Exists(windowsPowerShell)) return windowsPowerShell;

        string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        string powerShell7 = Path.Combine(programFiles, "PowerShell", "7", "pwsh.exe");
        return File.Exists(powerShell7) ? powerShell7 : null;
    }

    private static string Quote(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }
}
