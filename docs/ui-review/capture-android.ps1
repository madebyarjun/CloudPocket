param([Parameter(Mandatory=$true)][string]$Name, [string]$Tap, [switch]$Back, [switch]$Down, [switch]$Up)
$adbPath = 'D:/platform-tools/adb.exe'
$device = 'emulator-5554'
$xmlPath = Join-Path $env:TEMP 'cloudpocket-review-window.xml'
if ($Tap) {
    & $adbPath -s $device shell uiautomator dump /sdcard/cloudpocket-review-window.xml | Out-Null
    & $adbPath -s $device pull /sdcard/cloudpocket-review-window.xml $xmlPath 2>$null | Out-Null
    [xml]$tree = Get-Content -LiteralPath $xmlPath
    $matches = @($tree.SelectNodes('//node') | Where-Object { $_.'content-desc' -eq $Tap -or $_.text -eq $Tap })
    if ($matches.Count -ne 1) { throw "Expected one visible element named '$Tap'; found $($matches.Count)" }
    $bounds = [regex]::Matches($matches[0].bounds, '\d+') | ForEach-Object { [int]$_.Value }
    & $adbPath -s $device shell input tap ([int](($bounds[0]+$bounds[2])/2)) ([int](($bounds[1]+$bounds[3])/2))
}
if ($Back) { & $adbPath -s $device shell input keyevent 4 }
if ($Down) { & $adbPath -s $device shell input swipe 540 1700 540 600 500 }
if ($Up) { & $adbPath -s $device shell input swipe 540 600 540 1800 500 }
$dump = & $adbPath -s $device shell uiautomator dump /sdcard/cloudpocket-review-window.xml 2>&1
if ($dump -notmatch 'dumped to') { throw 'Android did not return a fresh UI tree; capture again after the transition.' }
& $adbPath -s $device pull /sdcard/cloudpocket-review-window.xml $xmlPath 2>$null | Out-Null
[xml]$tree = Get-Content -LiteralPath $xmlPath
& $adbPath -s $device shell screencap -p /sdcard/cloudpocket-review.png
& $adbPath -s $device pull /sdcard/cloudpocket-review.png (Join-Path $PSScriptRoot "screenshots/$Name.png") 2>$null | Out-Null
$tree.SelectNodes('//node') | Where-Object { $_.text -ne '' -or $_.'content-desc' -ne '' } | Select-Object text,content-desc,bounds | Format-Table -Wrap
