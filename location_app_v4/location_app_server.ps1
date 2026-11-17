$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'LOCATION APP - PTSC V4'

function Show-Fatal([string]$message) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Red
    Write-Host ' KHONG THE KHOI DONG LOCATION APP' -ForegroundColor Red
    Write-Host '============================================================' -ForegroundColor Red
    Write-Host $message -ForegroundColor Yellow
    Write-Host ''
    Read-Host 'Nhan Enter de dong'
    exit 1
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '              LOCATION APP - PTSC V4' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '[1/3] Dang tim thu muc Location App...' -ForegroundColor Yellow

$candidates = New-Object System.Collections.Generic.List[string]
# Duong dan xuat hien trong anh chup cua anh
$candidates.Add('C:\Users\khiempt\OneDrive - PTSC\1.0 STT\0. Claude\Location App\Input\3D\out\local_site')
# Tim theo cac bien OneDrive cua Windows, khong phu thuoc ten tai khoan
foreach ($od in @($env:OneDriveCommercial, $env:OneDrive, $env:OneDriveConsumer)) {
    if (-not [string]::IsNullOrWhiteSpace($od)) {
        $candidates.Add((Join-Path $od '1.0 STT\0. Claude\Location App\Input\3D\out\local_site'))
    }
}
$candidates.Add((Join-Path $HOME 'OneDrive - PTSC\1.0 STT\0. Claude\Location App\Input\3D\out\local_site'))

$root = $null
foreach ($candidate in ($candidates | Select-Object -Unique)) {
    if ((Test-Path -LiteralPath (Join-Path $candidate 'index.html') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $candidate '3d') -PathType Container)) {
        $root = (Resolve-Path -LiteralPath $candidate).Path
        break
    }
}

if (-not $root) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Hay chon DUY NHAT thu muc local_site (thu muc co index.html va thu muc 3d).'
        $dialog.ShowNewFolderButton = $false
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $candidate = $dialog.SelectedPath
            if ((Test-Path -LiteralPath (Join-Path $candidate 'index.html') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $candidate '3d') -PathType Container)) {
                $root = (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    } catch {}
}
if (-not $root) {
    Show-Fatal 'Khong tim thay thu muc local_site. Hay chon dung thu muc local_site, noi co index.html va thu muc 3d.'
}
Write-Host "Da tim thay: $root" -ForegroundColor Green

Write-Host '[2/3] Dang chuan bi web server bang Windows PowerShell...' -ForegroundColor Yellow
$csharp = @'
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public sealed class PTSCLocalWebServer
{
    private readonly string root;
    private readonly TcpListener listener;
    private volatile bool running;

    public PTSCLocalWebServer(string folder, int port)
    {
        root = Path.GetFullPath(folder);
        if (!root.EndsWith(Path.DirectorySeparatorChar.ToString())) root += Path.DirectorySeparatorChar;
        listener = new TcpListener(IPAddress.Loopback, port);
    }

    public void Start()
    {
        listener.Start(100);
        running = true;
        Task.Factory.StartNew(AcceptLoop, TaskCreationOptions.LongRunning);
    }

    public void Stop()
    {
        running = false;
        try { listener.Stop(); } catch { }
    }

    private void AcceptLoop()
    {
        while (running)
        {
            try
            {
                TcpClient client = listener.AcceptTcpClient();
                Task.Factory.StartNew(() => Handle(client), TaskCreationOptions.None);
            }
            catch (SocketException) { if (!running) break; }
            catch (ObjectDisposedException) { break; }
            catch { }
        }
    }

    private static string Mime(string path)
    {
        string ext = Path.GetExtension(path).ToLowerInvariant();
        switch (ext)
        {
            case ".html": case ".htm": return "text/html; charset=utf-8";
            case ".js": case ".mjs": return "application/javascript; charset=utf-8";
            case ".css": return "text/css; charset=utf-8";
            case ".json": return "application/json; charset=utf-8";
            case ".webmanifest": return "application/manifest+json; charset=utf-8";
            case ".svg": return "image/svg+xml";
            case ".png": return "image/png";
            case ".jpg": case ".jpeg": return "image/jpeg";
            case ".gif": return "image/gif";
            case ".ico": return "image/x-icon";
            case ".bin": return "application/octet-stream";
            case ".wasm": return "application/wasm";
            case ".glb": return "model/gltf-binary";
            case ".gltf": return "model/gltf+json";
            case ".woff": return "font/woff";
            case ".woff2": return "font/woff2";
            case ".ttf": return "font/ttf";
            case ".xml": return "application/xml; charset=utf-8";
            default: return "application/octet-stream";
        }
    }

    private static void Reply(NetworkStream stream, int code, string reason, string body)
    {
        byte[] data = Encoding.UTF8.GetBytes(body);
        string headers = "HTTP/1.1 " + code + " " + reason + "\r\n" +
            "Content-Type: text/plain; charset=utf-8\r\n" +
            "Content-Length: " + data.Length + "\r\n" +
            "Connection: close\r\n" +
            "Cache-Control: no-store\r\n" +
            "Access-Control-Allow-Origin: *\r\n" +
            "Access-Control-Allow-Methods: GET, HEAD, OPTIONS\r\n" +
            "Access-Control-Allow-Headers: Range, Content-Type\r\n\r\n";
        byte[] h = Encoding.ASCII.GetBytes(headers);
        stream.Write(h, 0, h.Length);
        if (data.Length > 0) stream.Write(data, 0, data.Length);
    }

    private void Handle(TcpClient client)
    {
        using (client)
        {
            try
            {
                client.ReceiveTimeout = 10000;
                client.SendTimeout = 60000;
                using (NetworkStream stream = client.GetStream())
                {
                    MemoryStream ms = new MemoryStream();
                    int state = 0;
                    while (ms.Length < 32768)
                    {
                        int b = stream.ReadByte();
                        if (b < 0) return;
                        ms.WriteByte((byte)b);
                        if ((state == 0 || state == 2) && b == 13) state++;
                        else if ((state == 1 || state == 3) && b == 10) state++;
                        else state = (b == 13) ? 1 : 0;
                        if (state == 4) break;
                    }
                    string request = Encoding.ASCII.GetString(ms.ToArray());
                    string[] lines = request.Split(new string[] { "\r\n" }, StringSplitOptions.None);
                    if (lines.Length == 0) { Reply(stream, 400, "Bad Request", "Bad request"); return; }
                    string[] first = lines[0].Split(' ');
                    if (first.Length < 2) { Reply(stream, 400, "Bad Request", "Bad request"); return; }
                    string method = first[0].ToUpperInvariant();
                    if (method == "OPTIONS") { Reply(stream, 204, "No Content", ""); return; }
                    if (method != "GET" && method != "HEAD") { Reply(stream, 405, "Method Not Allowed", "Method not allowed"); return; }

                    string urlPath = first[1];
                    int q = urlPath.IndexOf('?');
                    if (q >= 0) urlPath = urlPath.Substring(0, q);
                    urlPath = Uri.UnescapeDataString(urlPath).TrimStart('/').Replace('/', Path.DirectorySeparatorChar);
                    string full = Path.GetFullPath(Path.Combine(root, urlPath));
                    if (!full.StartsWith(root, StringComparison.OrdinalIgnoreCase)) { Reply(stream, 403, "Forbidden", "Forbidden"); return; }
                    if (Directory.Exists(full)) full = Path.Combine(full, "index.html");
                    if (!File.Exists(full)) { Reply(stream, 404, "Not Found", "Not found: " + urlPath); return; }

                    FileInfo info = new FileInfo(full);
                    long start = 0;
                    long length = info.Length;
                    int status = 200;
                    string reason = "OK";
                    string range = null;
                    foreach (string line in lines) {
                        if (line.StartsWith("Range:", StringComparison.OrdinalIgnoreCase)) range = line.Substring(6).Trim();
                    }
                    if (!String.IsNullOrEmpty(range) && range.StartsWith("bytes=", StringComparison.OrdinalIgnoreCase)) {
                        string spec = range.Substring(6).Split(',')[0].Trim();
                        string[] bounds = spec.Split('-');
                        long a, b;
                        if (bounds.Length == 2 && (bounds[0].Length > 0 || bounds[1].Length > 0)) {
                            if (bounds[0].Length == 0 && Int64.TryParse(bounds[1], out b)) { start = Math.Max(0, info.Length - b); }
                            else if (Int64.TryParse(bounds[0], out a)) { start = a; if (bounds[1].Length > 0 && Int64.TryParse(bounds[1], out b)) length = Math.Min(length, b - start + 1); }
                            if (start >= 0 && start < info.Length && length > 0) { length = Math.Min(length, info.Length - start); status = 206; reason = "Partial Content"; }
                            else { Reply(stream, 416, "Range Not Satisfiable", "Range not satisfiable"); return; }
                        }
                    }
                    string responseHeaders = "HTTP/1.1 " + status + " " + reason + "\r\n" +
                        "Content-Type: " + Mime(full) + "\r\n" +
                        "Content-Length: " + length + "\r\n" +
                        (status == 206 ? "Content-Range: bytes " + start + "-" + (start + length - 1) + "/" + info.Length + "\r\n" : "") +
                        "Accept-Ranges: bytes\r\n" +
                        "Connection: close\r\n" +
                        "Cache-Control: no-cache\r\n" +
                        "Access-Control-Allow-Origin: *\r\n" +
                        "Access-Control-Allow-Methods: GET, HEAD, OPTIONS\r\n" +
                        "Access-Control-Allow-Headers: Range, Content-Type\r\n\r\n";
                    byte[] head = Encoding.ASCII.GetBytes(responseHeaders);
                    stream.Write(head, 0, head.Length);
                    if (method == "HEAD") return;
                    using (FileStream file = new FileStream(full, FileMode.Open, FileAccess.Read, FileShare.ReadWrite)) {
                        file.Position = start;
                        byte[] buffer = new byte[65536];
                        long remaining = length;
                        while (remaining > 0) {
                            int wanted = (int)Math.Min(buffer.Length, remaining);
                            int read = file.Read(buffer, 0, wanted);
                            if (read <= 0) break;
                            stream.Write(buffer, 0, read);
                            remaining -= read;
                        }
                    }
                }
            }
            catch { }
        }
    }
}
'@

try {
    Add-Type -TypeDefinition $csharp -Language CSharp
} catch {
    Show-Fatal ('Windows khong the nap bo may web server: ' + $_.Exception.Message)
}

Write-Host '[3/3] Dang khoi dong web server...' -ForegroundColor Yellow
$server = $null
$port = 8765
for ($p = 8765; $p -le 8780; $p++) {
    $candidateServer = $null
    try {
        $candidateServer = New-Object -TypeName PTSCLocalWebServer -ArgumentList $root, $p
        $candidateServer.Start()
        $server = $candidateServer
        $port = $p
        break
    } catch {
        try { if ($candidateServer) { $candidateServer.Stop() } } catch {}
        $candidateServer = $null
    }
}
if (-not $server) {
    Show-Fatal 'Khong mo duoc cong mang tu 8765 den 8780. Hay dong cac cua so Location App cu roi chay lai.'
}

$url = "http://127.0.0.1:$port/"
Start-Sleep -Milliseconds 700
try { Start-Process $url } catch { Write-Host "Hay tu mo trinh duyet va nhap: $url" -ForegroundColor Yellow }
Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' LOCATION APP DA DUOC KHOI DONG' -ForegroundColor Green
Write-Host " Dia chi: $url" -ForegroundColor Green
Write-Host ' May chu nay chay bang PowerShell, KHONG CAN PYTHON.' -ForegroundColor Green
Write-Host ' Giu cua so nay mo trong khi su dung ung dung.' -ForegroundColor Green
Write-Host ' Nhan Q de tat may chu.' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Green

try {
    while ($true) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::Q) { break }
        }
        Start-Sleep -Milliseconds 200
    }
} finally {
    if ($server) { $server.Stop() }
    Write-Host 'Da tat web server.' -ForegroundColor Yellow
}
