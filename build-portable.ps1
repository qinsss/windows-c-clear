param([string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceDirectory = Join-Path $PSScriptRoot 'src'
$hostSource = Join-Path $PSScriptRoot 'packaging\PortableHost.cs'
$iconPath = Join-Path $sourceDirectory 'app.ico'
$finalExe = Join-Path $OutputDirectory 'C盘清理助手.exe'
$cscCandidates = @(
    (Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$csc = $cscCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $csc) { throw '找不到系统自带的 .NET Framework C# 编译器。' }
foreach ($requiredFile in @($hostSource, $iconPath, (Join-Path $sourceDirectory 'Cleaner.Core.ps1'), (Join-Path $sourceDirectory 'WindowsCClear.ps1'))) {
    if (-not (Test-Path -LiteralPath $requiredFile)) { throw "缺少打包文件：$requiredFile" }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
if (Test-Path -LiteralPath $finalExe) { Remove-Item -LiteralPath $finalExe -Force }

$compilerArguments = @(
    '/nologo',
    '/target:winexe',
    '/platform:anycpu',
    '/optimize+',
    ('/out:"{0}"' -f $finalExe),
    ('/win32icon:"{0}"' -f $iconPath),
    '/reference:System.dll',
    '/reference:System.Windows.Forms.dll',
    ('/resource:"{0}",Cleaner.Core.ps1' -f (Join-Path $sourceDirectory 'Cleaner.Core.ps1')),
    ('/resource:"{0}",WindowsCClear.ps1' -f (Join-Path $sourceDirectory 'WindowsCClear.ps1')),
    ('/resource:"{0}",app.ico' -f $iconPath),
    ('"{0}"' -f $hostSource)
)

$compiler = Start-Process -FilePath $csc -ArgumentList $compilerArguments -WindowStyle Hidden -Wait -PassThru
if ($compiler.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $finalExe)) {
    throw "免安装程序编译失败，退出代码：$($compiler.ExitCode)"
}

$result = Get-Item -LiteralPath $finalExe
Write-Output "已生成：$($result.FullName)"
Write-Output "大小：$([math]::Round($result.Length / 1KB, 1)) KB"
