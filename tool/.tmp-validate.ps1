$target = 'd:\reflex\keiyo\keiyo-chat-app\tool\configure_platform.ps1'
$errs = $null
$tokens = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$tokens, [ref]$errs)
if ($errs) {
    foreach ($e in $errs) {
        Write-Host ("{0} @line {1}" -f $e.Message, $e.Extent.StartLineNumber)
    }
    exit 1
}
Write-Host 'PS OK'
