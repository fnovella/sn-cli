$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $RepoRoot "build\win"
$DistDir  = Join-Path $RepoRoot "dist"
$RubyVer  = "3.3.7-1"
$RubyUrl  = "https://github.com/oneclick/rubyinstaller2/releases/download/RubyInstaller-$RubyVer/ruby-$RubyVer-x64.7z"

Write-Host "==> Preparing build directories..."
if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Path $DistDir | Out-Null }
New-Item -ItemType Directory -Path $BuildDir | Out-Null

$Archive7z = Join-Path $BuildDir "ruby.7z"
Write-Host "==> Downloading portable RubyInstaller ($RubyVer)..."
Invoke-WebRequest -Uri $RubyUrl -OutFile $Archive7z -UseBasicParsing

Write-Host "==> Extracting portable Ruby..."
7z x $Archive7z "-o$BuildDir" -y | Out-Null
$ExtractedRoot = Join-Path $BuildDir "ruby-$RubyVer-x64"

$RuntimeDir = Join-Path $BuildDir "runtime"
New-Item -ItemType Directory -Path $RuntimeDir | Out-Null

# Copy only required runtime folders (bin with builtin DLLs, stdlib, site_ruby, and ssl certs)
Copy-Item -Recurse (Join-Path $ExtractedRoot "bin") (Join-Path $RuntimeDir "bin")
Copy-Item -Recurse (Join-Path $ExtractedRoot "ssl") (Join-Path $RuntimeDir "ssl")

$LibRubySrc = Join-Path $ExtractedRoot "lib\ruby"
$LibRubyDst = Join-Path $RuntimeDir "lib\ruby"
New-Item -ItemType Directory -Path $LibRubyDst | Out-Null
Copy-Item -Recurse (Join-Path $LibRubySrc "3.3.0") (Join-Path $LibRubyDst "3.3.0")
if (Test-Path (Join-Path $LibRubySrc "site_ruby")) {
    Copy-Item -Recurse (Join-Path $LibRubySrc "site_ruby") (Join-Path $LibRubyDst "site_ruby")
}
if (Test-Path (Join-Path $LibRubySrc "vendor_ruby")) {
    Copy-Item -Recurse (Join-Path $LibRubySrc "vendor_ruby") (Join-Path $LibRubyDst "vendor_ruby")
}

# Copy the sn script into the portable runtime
$AppDir = Join-Path $RuntimeDir "app"
New-Item -ItemType Directory -Path $AppDir | Out-Null
Copy-Item (Join-Path $RepoRoot "sn") (Join-Path $AppDir "sn")

# Create runtime.zip
$RuntimeZip = Join-Path $BuildDir "runtime.zip"
Write-Host "==> Compressing portable runtime + sn into runtime.zip..."
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $RuntimeDir,
    $RuntimeZip,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)

$HashBytes = (Get-FileHash -Path $RuntimeZip -Algorithm SHA256).Hash.Substring(0, 16).ToLower()
Write-Host "==> Runtime bundle ID: rt-$HashBytes"

# Generate C# native launcher source
$LauncherCs = Join-Path $BuildDir "Launcher.cs"
$CsCode = @"
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

internal static class Program
{
    private const string BundleId = "rt-$HashBytes";
    private const int STD_OUTPUT_HANDLE = -11;
    private const int STD_ERROR_HANDLE = -12;
    private const uint ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetStdHandle(int nStdHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

    private static void EnableAnsiColors()
    {
        try
        {
            foreach (int handleId in new[] { STD_OUTPUT_HANDLE, STD_ERROR_HANDLE })
            {
                IntPtr handle = GetStdHandle(handleId);
                if (handle != IntPtr.Zero && GetConsoleMode(handle, out uint mode))
                {
                    SetConsoleMode(handle, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
                }
            }
        }
        catch
        {
            // Ignore when stdout/stderr are redirected
        }
    }

    private static string QuoteArg(string arg)
    {
        if (string.IsNullOrEmpty(arg))
            return "\"\"";

        bool needsQuotes = false;
        foreach (char c in arg)
        {
            if (char.IsWhiteSpace(c) || c == '"')
            {
                needsQuotes = true;
                break;
            }
        }
        if (!needsQuotes)
            return arg;

        StringBuilder sb = new StringBuilder();
        sb.Append('"');
        int backslashes = 0;
        foreach (char c in arg)
        {
            if (c == '\\')
            {
                backslashes++;
            }
            else if (c == '"')
            {
                sb.Append('\\', backslashes * 2 + 1);
                sb.Append('"');
                backslashes = 0;
            }
            else
            {
                if (backslashes > 0)
                {
                    sb.Append('\\', backslashes);
                    backslashes = 0;
                }
                sb.Append(c);
            }
        }
        if (backslashes > 0)
        {
            sb.Append('\\', backslashes * 2);
        }
        sb.Append('"');
        return sb.ToString();
    }

    private static string EnsureRuntimeExtracted()
    {
        string baseDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "sn-cli"
        );
        string targetDir = Path.Combine(baseDir, BundleId);
        string markerFile = Path.Combine(targetDir, ".ready");

        if (File.Exists(markerFile))
            return targetDir;

        Directory.CreateDirectory(baseDir);
        string tempDir = Path.Combine(baseDir, BundleId + "-tmp-" + Process.GetCurrentProcess().Id);
        if (Directory.Exists(tempDir))
            Directory.Delete(tempDir, true);

        using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("runtime.zip"))
        {
            if (stream == null)
                throw new InvalidOperationException("Embedded runtime.zip resource not found.");

            using (ZipArchive archive = new ZipArchive(stream, ZipArchiveMode.Read))
            {
                archive.ExtractToDirectory(tempDir);
            }
        }

        File.WriteAllText(Path.Combine(tempDir, ".ready"), BundleId);

        try
        {
            if (Directory.Exists(targetDir))
                Directory.Delete(targetDir, true);
            Directory.Move(tempDir, targetDir);
        }
        catch
        {
            if (!File.Exists(markerFile))
                throw;
            if (Directory.Exists(tempDir))
                Directory.Delete(tempDir, true);
        }

        return targetDir;
    }

    public static int Main(string[] args)
    {
        EnableAnsiColors();
        Console.CancelKeyPress += (sender, e) => { e.Cancel = true; };

        string runtimeRoot = EnsureRuntimeExtracted();
        string rubyExe = Path.Combine(runtimeRoot, "bin", "ruby.exe");
        string snScript = Path.Combine(runtimeRoot, "app", "sn");
        string sslCert = Path.Combine(runtimeRoot, "ssl", "cert.pem");

        StringBuilder cmdArgs = new StringBuilder();
        cmdArgs.Append(QuoteArg(snScript));
        foreach (string a in args)
        {
            cmdArgs.Append(' ');
            cmdArgs.Append(QuoteArg(a));
        }

        ProcessStartInfo psi = new ProcessStartInfo
        {
            FileName = rubyExe,
            Arguments = cmdArgs.ToString(),
            UseShellExecute = false
        };

        if (File.Exists(sslCert) && string.IsNullOrEmpty(Environment.GetEnvironmentVariable("SSL_CERT_FILE")))
        {
            psi.EnvironmentVariables["SSL_CERT_FILE"] = sslCert;
        }

        using (Process proc = Process.Start(psi))
        {
            proc.WaitForExit();
            return proc.ExitCode;
        }
    }
}
"@
Set-Content -Path $LauncherCs -Value $CsCode -Encoding UTF8

$CscExe = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $CscExe)) {
    throw "csc.exe not found at $CscExe"
}

$OutExe = Join-Path $DistDir "sn.exe"
Write-Host "==> Compiling standalone $OutExe..."
& $CscExe /nologo /target:exe /platform:x64 /optimize+ `
    /r:System.IO.Compression.dll `
    /r:System.IO.Compression.FileSystem.dll `
    "/resource:$RuntimeZip,runtime.zip" `
    "/out:$OutExe" `
    $LauncherCs

if ($LASTEXITCODE -ne 0) {
    throw "csc.exe failed with exit code $LASTEXITCODE"
}

$SizeMB = [Math]::Round((Get-Item $OutExe).Length / 1MB, 2)
Write-Host "==> Successfully built $OutExe ($SizeMB MB)"
