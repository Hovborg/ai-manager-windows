function Set-ManagerEventQueue {
    param($Queue)
    $script:ManagerEventQueue=$Queue
}

function Publish-ManagerEvent {
    param([string]$Type,[string]$Text='', $Data)
    if ($null -eq $script:ManagerEventQueue) {return}
    # Bound noisy output while preserving stage and completion events.
    if ($Type -eq 'Output' -and $script:ManagerEventQueue.Count -ge 200) {return}
    $item=@{Type=$Type;Text=$Text;Data=$Data;At=[datetimeoffset]::Now.ToString('o')}
    if ($script:ManagerCurrentOperation) {
        foreach ($key in $script:ManagerCurrentOperation.Keys) {$item[$key]=$script:ManagerCurrentOperation[$key]}
    }
    $script:ManagerEventQueue.Enqueue($item)
}

function Read-ManagerProcessStreams {
    param([object[]]$Streams,[Text.StringBuilder]$Output)
    foreach ($stream in $Streams) {
        $chunks=0
        while (-not $stream.Closed -and $stream.Task.IsCompleted -and $chunks -lt 64) {
            $count=$stream.Task.GetAwaiter().GetResult()
            if ($count -le 0) {$stream.Closed=$true;break}
            $text=[string]::new($stream.Buffer,0,$count)
            [void]$Output.Append($text)
            if ($Output.Length -gt 256KB) {[void]$Output.Remove(0,$Output.Length-256KB)}
            if ($script:ManagerCaptureOutput) {
                $clean=$text -replace '\x1b\[[0-?]*[ -/]*[@-~]','' -replace '[\x00-\x08\x0b\x0c\x0e-\x1f]',''
                Publish-ManagerEvent 'Output' $clean
            }
            $stream.Task=$stream.Reader.ReadAsync($stream.Buffer,0,$stream.Buffer.Length)
            $chunks++
        }
    }
}
