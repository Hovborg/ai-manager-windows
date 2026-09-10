# Real local HTTP transport, synthetic public text. No external network or installations.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../updater-releases.ps1"
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
$listener.Start()
$port=$listener.LocalEndpoint.Port
$server=[powershell]::Create().AddScript({
    param($listener)
    foreach ($request in 1..4) {
        $socket=$listener.AcceptTcpClientAsync().GetAwaiter().GetResult()
        try {
            $stream=$socket.GetStream()
            $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::ASCII,$false,1024,$true)
            $requestLine=$reader.ReadLine()
            while ($reader.ReadLine()) {}
            $reader.Dispose()
            $path=($requestLine -split ' ')[1]
            $status='200 OK'; $extra=''
            $text=if ($path -eq '/large') {'x'*(8MB+1)} else {'Versionsnyt: æ, ø og å'}
            $bytes=[Text.Encoding]::UTF8.GetBytes($text)
            if ($path -in @('/gzip','/large')) {
                $memory=[IO.MemoryStream]::new()
                $gzip=[IO.Compression.GZipStream]::new($memory,[IO.Compression.CompressionLevel]::Fastest,$true)
                $gzip.Write($bytes,0,$bytes.Length); $gzip.Dispose()
                $bytes=$memory.ToArray(); $memory.Dispose()
                $extra="Content-Encoding: gzip`r`n"
            }
            if ($path -eq '/redirect') {$status='302 Found';$extra="Location: /plain`r`n"}
            $headers=[Text.Encoding]::ASCII.GetBytes("HTTP/1.1 $status`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($bytes.Length)`r`n${extra}Connection: close`r`n`r`n")
            $stream.Write($headers,0,$headers.Length);$stream.Write($bytes,0,$bytes.Length);$stream.Flush()
        } finally {$socket.Dispose()}
    }
}).AddArgument($listener)
$pending=$server.BeginInvoke()
try {
    $gzip=Invoke-ReleaseRequest "http://127.0.0.1:$port/gzip"
    if ($gzip -cne 'Versionsnyt: æ, ø og å') {throw 'Gzip response was not decoded to the original UTF-8 text'}
    $plain=Invoke-ReleaseRequest "http://127.0.0.1:$port/plain"
    if ($plain -cne $gzip) {throw 'Plain and gzip responses differ'}
    $largeError=''
    try {Invoke-ReleaseRequest "http://127.0.0.1:$port/large" | Out-Null} catch {$largeError=$_.Exception.Message}
    if ($largeError -notmatch 'for stort') {throw 'The 8 MiB limit was not enforced on decompressed content'}
    $redirectError=''
    try {Invoke-ReleaseRequest "http://127.0.0.1:$port/redirect" | Out-Null} catch {$redirectError=$_.Exception.Message}
    if ($redirectError -notmatch 'HTTP 302') {throw 'Transport followed or accepted an unexpected redirect'}
    [void]$server.EndInvoke($pending)
    if ($server.HadErrors) {throw "Local fixture failed: $($server.Streams.Error)"}
    Write-Output 'PASS: real HTTP, gzip/UTF-8, plain text, decompressed size limit and redirect rejection'
} finally {
    $listener.Stop()
    $server.Stop();$server.Dispose()
}
