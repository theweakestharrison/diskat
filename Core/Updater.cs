using System.Diagnostics;
using System.Net.Http;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;

namespace Diskat.Core;

public sealed record UpdateInfo(Version Version, string Url, string Sha256, long Size, string NotesUrl);

/// <summary>
/// Kiểm tra và cài bản mới. Chỉ chạy khi người dùng bấm "Check for updates" hoặc tự bật kiểm tra lúc khởi động.
/// Mỗi lần kiểm tra là một yêu cầu GET tới https://diskat.cc/api/latest, không gửi thông tin gì về máy.
/// </summary>
public static class Updater
{
    private const string ApiUrl = "https://diskat.cc/api/latest";
    private const string TrustedHost = "diskat.cc";

    /// <summary>Phiên bản đang chạy. Biến môi trường DISKAT_FAKE_VERSION dùng để thử luồng cập nhật.</summary>
    public static Version CurrentVersion
    {
        get
        {
            var fake = Environment.GetEnvironmentVariable("DISKAT_FAKE_VERSION");
            if (fake != null && Version.TryParse(fake, out var f)) return f;
            var v = Assembly.GetExecutingAssembly().GetName().Version ?? new Version(0, 0, 0);
            return new Version(v.Major, v.Minor, Math.Max(0, v.Build));
        }
    }

    /// <summary>True nếu app được cài từ Microsoft Store (MSIX): khi đó Store tự cập nhật.</summary>
    public static bool IsPackaged
    {
        get
        {
            try
            {
                int len = 0;
                return GetCurrentPackageFullName(ref len, null) != 15700; // APPMODEL_ERROR_NO_PACKAGE
            }
            catch { return false; }
        }
    }

    private static HttpClient CreateClient(TimeSpan timeout)
    {
        var http = new HttpClient { Timeout = timeout };
        http.DefaultRequestHeaders.UserAgent.ParseAdd($"Diskat/{CurrentVersion} (Windows)");
        return http;
    }

    /// <summary>Trả về thông tin bản mới nếu có bản mới hơn bản đang chạy, ngược lại null.</summary>
    public static async Task<UpdateInfo?> CheckAsync(CancellationToken ct = default)
    {
        using var http = CreateClient(TimeSpan.FromSeconds(15));
        using var resp = await http.GetAsync(ApiUrl, ct);
        resp.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync(ct));
        var root = doc.RootElement;

        var version = Version.Parse(root.GetProperty("version").GetString()!);
        var info = new UpdateInfo(
            version,
            root.GetProperty("url").GetString()!,
            root.GetProperty("sha256").GetString()!.ToLowerInvariant(),
            root.GetProperty("size").GetInt64(),
            root.TryGetProperty("notes", out var n) ? n.GetString() ?? "" : "");

        Settings.Current.LastUpdateCheckUtc = DateTime.UtcNow;
        Settings.Current.Save();

        if (!IsTrusted(info.Url)) throw new InvalidOperationException("Untrusted download URL: " + info.Url);
        return version > CurrentVersion ? info : null;
    }

    private static bool IsTrusted(string url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var u) && u.Scheme == Uri.UriSchemeHttps &&
        u.Host.Equals(TrustedHost, StringComparison.OrdinalIgnoreCase);

    /// <summary>Tải file về thư mục tạm, kiểm tra SHA-256. Trả về đường dẫn file đã tải.</summary>
    public static async Task<string> DownloadAsync(UpdateInfo info, IProgress<double>? progress, CancellationToken ct = default)
    {
        if (!IsTrusted(info.Url)) throw new InvalidOperationException("Untrusted download URL: " + info.Url);

        var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Diskat", "updates");
        Directory.CreateDirectory(dir);
        var target = Path.Combine(dir, $"Diskat-{info.Version}.exe");
        var partial = target + ".part";

        using var http = CreateClient(TimeSpan.FromMinutes(30));
        using var resp = await http.GetAsync(info.Url, HttpCompletionOption.ResponseHeadersRead, ct);
        resp.EnsureSuccessStatusCode();
        long total = resp.Content.Headers.ContentLength ?? info.Size;

        using (var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256))
        {
            await using (var src = await resp.Content.ReadAsStreamAsync(ct))
            await using (var dst = new FileStream(partial, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 16, true))
            {
                var buffer = new byte[1 << 16];
                long done = 0;
                int read;
                while ((read = await src.ReadAsync(buffer, ct)) > 0)
                {
                    sha.AppendData(buffer, 0, read);
                    await dst.WriteAsync(buffer.AsMemory(0, read), ct);
                    done += read;
                    if (total > 0) progress?.Report((double)done / total);
                }
            }

            var actual = Convert.ToHexString(sha.GetHashAndReset()).ToLowerInvariant();
            if (actual != info.Sha256)
            {
                File.Delete(partial);
                throw new InvalidDataException($"SHA-256 mismatch: expected {info.Sha256}, got {actual}");
            }
        }

        File.Move(partial, target, overwrite: true);
        return target;
    }

    /// <summary>True nếu có quyền ghi vào thư mục chứa Diskat.exe đang chạy (để tự thay file).</summary>
    public static bool CanReplaceRunningExe()
    {
        try
        {
            var dir = Path.GetDirectoryName(Environment.ProcessPath!)!;
            var probe = Path.Combine(dir, $".diskat-write-test-{Environment.ProcessId}");
            File.WriteAllText(probe, "");
            File.Delete(probe);
            return true;
        }
        catch { return false; }
    }

    /// <summary>
    /// Chạy một script nhỏ: đợi Diskat thoát, chép file mới đè lên Diskat.exe rồi mở lại.
    /// Gọi hàm này xong thì tắt app ngay.
    /// </summary>
    public static void InstallAfterExit(string newExe)
    {
        var current = Environment.ProcessPath!;
        var script = Path.Combine(Path.GetTempPath(), $"diskat-update-{Environment.ProcessId}.cmd");
        File.WriteAllText(script, """
            @echo off
            setlocal
            set "PID=%~1"
            set "SRC=%~2"
            set "DST=%~3"
            :wait
            tasklist /FI "PID eq %PID%" 2>nul | find "%PID%" >nul
            if not errorlevel 1 (
              timeout /t 1 /nobreak >nul
              goto wait
            )
            copy /Y "%SRC%" "%DST%" >nul
            if errorlevel 1 (
              start "" "%SRC%"
            ) else (
              del "%SRC%" >nul 2>&1
              start "" "%DST%"
            )
            (goto) 2>nul & del "%~f0"
            """);
        Process.Start(new ProcessStartInfo("cmd.exe",
            $"/c \"\"{script}\" {Environment.ProcessId} \"{newExe}\" \"{current}\"\"")
        {
            CreateNoWindow = true,
            UseShellExecute = false,
            WindowStyle = ProcessWindowStyle.Hidden,
        });
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetCurrentPackageFullName(ref int packageFullNameLength, System.Text.StringBuilder? packageFullName);
}
