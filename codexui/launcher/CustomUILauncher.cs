using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

internal static class CustomUILauncher
{
    private const string AppUrl = "http://127.0.0.1:4187/";
    private const int StartupTimeoutMs = 30000;

    [STAThread]
    private static int Main(string[] args)
    {
        bool openAppWindow = true;
        foreach (string arg in args)
        {
            if (string.Equals(arg, "--no-open", StringComparison.OrdinalIgnoreCase))
            {
                openAppWindow = false;
            }
        }

        string appDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        if (string.IsNullOrEmpty(appDir))
        {
            appDir = Environment.CurrentDirectory;
        }

        string serverPath = Path.Combine(appDir, "server.py");
        if (!File.Exists(serverPath))
        {
            ShowError("server.py was not found beside Custom UI.exe.\n\nKeep Custom UI.exe in the codexui folder.");
            return 1;
        }

        if (!IsServerReady())
        {
            string pythonPath = FindPython();
            if (string.IsNullOrEmpty(pythonPath))
            {
                ShowError(
                    "Python was not found.\n\n" +
                    "Install Python, run this from inside Codex, or set CUSTOM_UI_PYTHON to python.exe."
                );
                return 1;
            }

            try
            {
                ProcessStartInfo info = new ProcessStartInfo();
                info.FileName = pythonPath;
                info.Arguments = Quote(serverPath);
                info.WorkingDirectory = appDir;
                info.UseShellExecute = false;
                info.CreateNoWindow = true;
                info.WindowStyle = ProcessWindowStyle.Hidden;
                Process.Start(info);
            }
            catch (Exception ex)
            {
                ShowError("Could not start the Custom UI server.\n\n" + ex.Message);
                return 1;
            }

            if (!WaitForServer())
            {
                ShowError("Custom UI server did not become ready at " + AppUrl);
                return 1;
            }
        }

        if (openAppWindow)
        {
            if (!OpenAppWindow(appDir))
            {
                ShowError("Custom UI is running, but the desktop app window did not open.\n\nOpen this manually:\n" + AppUrl);
                return 1;
            }
        }

        return 0;
    }

    private static bool OpenAppWindow(string appDir)
    {
        string browser = FindAppBrowser();
        if (string.IsNullOrEmpty(browser))
        {
            try
            {
                ProcessStartInfo fallback = new ProcessStartInfo();
                fallback.FileName = AppUrl;
                fallback.UseShellExecute = true;
                Process.Start(fallback);
                return true;
            }
            catch
            {
                return false;
            }
        }

        string profileDir = Path.Combine(appDir, ".app-profile");
        Directory.CreateDirectory(profileDir);

        try
        {
            ProcessStartInfo app = new ProcessStartInfo();
            app.FileName = browser;
            app.Arguments =
                "--app=" + AppUrl + " " +
                "--user-data-dir=" + Quote(profileDir) + " " +
                "--class=CustomUI";
            app.WorkingDirectory = appDir;
            app.UseShellExecute = false;
            app.CreateNoWindow = true;
            Process.Start(app);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static bool WaitForServer()
    {
        Stopwatch timer = Stopwatch.StartNew();
        while (timer.ElapsedMilliseconds < StartupTimeoutMs)
        {
            if (IsServerReady())
            {
                return true;
            }

            Thread.Sleep(500);
        }

        return false;
    }

    private static bool IsServerReady()
    {
        try
        {
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(AppUrl);
            request.Timeout = 2000;
            request.ReadWriteTimeout = 2000;
            request.Method = "GET";
            using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
            {
                return response.StatusCode == HttpStatusCode.OK;
            }
        }
        catch
        {
            return false;
        }
    }

    private static string FindPython()
    {
        string configured = Environment.GetEnvironmentVariable("CUSTOM_UI_PYTHON");
        if (File.Exists(configured))
        {
            return configured;
        }

        string userProfile = Environment.GetEnvironmentVariable("USERPROFILE");
        if (!string.IsNullOrEmpty(userProfile))
        {
            string runtimeRoot = Path.Combine(userProfile, ".cache", "codex-runtimes", "codex-primary-runtime", "dependencies", "python");
            string pythonw = Path.Combine(runtimeRoot, "pythonw.exe");
            if (File.Exists(pythonw))
            {
                return pythonw;
            }

            string python = Path.Combine(runtimeRoot, "python.exe");
            if (File.Exists(python))
            {
                return python;
            }
        }

        string localAppData = Environment.GetEnvironmentVariable("LOCALAPPDATA");
        string found = FindPythonUnder(localAppData);
        if (!string.IsNullOrEmpty(found))
        {
            return found;
        }

        found = FindOnPath("pythonw.exe");
        if (!string.IsNullOrEmpty(found))
        {
            return found;
        }

        return FindOnPath("python.exe");
    }

    private static string FindAppBrowser()
    {
        string configured = Environment.GetEnvironmentVariable("CUSTOM_UI_BROWSER");
        if (File.Exists(configured))
        {
            return configured;
        }

        string[] candidates = new string[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Microsoft", "Edge", "Application", "msedge.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Microsoft", "Edge", "Application", "msedge.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Google", "Chrome", "Application", "chrome.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Google", "Chrome", "Application", "chrome.exe")
        };

        foreach (string candidate in candidates)
        {
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        string found = FindOnPath("msedge.exe");
        if (!string.IsNullOrEmpty(found))
        {
            return found;
        }

        return FindOnPath("chrome.exe");
    }

    private static string FindPythonUnder(string root)
    {
        if (string.IsNullOrEmpty(root) || !Directory.Exists(root))
        {
            return null;
        }

        string programs = Path.Combine(root, "Programs", "Python");
        if (!Directory.Exists(programs))
        {
            return null;
        }

        string[] dirs = Directory.GetDirectories(programs, "Python*");
        Array.Sort(dirs, StringComparer.OrdinalIgnoreCase);
        Array.Reverse(dirs);

        foreach (string dir in dirs)
        {
            string pythonw = Path.Combine(dir, "pythonw.exe");
            if (File.Exists(pythonw))
            {
                return pythonw;
            }

            string python = Path.Combine(dir, "python.exe");
            if (File.Exists(python))
            {
                return python;
            }
        }

        return null;
    }

    private static string FindOnPath(string exeName)
    {
        string path = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrEmpty(path))
        {
            return null;
        }

        foreach (string dir in path.Split(Path.PathSeparator))
        {
            try
            {
                string candidate = Path.Combine(dir.Trim(), exeName);
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }
            catch
            {
            }
        }

        return null;
    }

    private static string Quote(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static void ShowError(string message)
    {
        MessageBox.Show(message, "Custom UI", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }
}
