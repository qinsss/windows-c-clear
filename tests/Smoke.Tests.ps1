Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\Cleaner.Core.ps1')

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "断言失败：$Message" }
}

Assert-True (Test-ProtectedPath $env:windir) 'Windows 目录必须受保护'
Assert-True (Test-ProtectedPath (Join-Path $env:ProgramFiles 'Example')) 'Program Files 子目录必须受保护'
Assert-True (-not (Test-ProtectedPath (Join-Path $env:LOCALAPPDATA 'Temp'))) '用户临时目录不应被误判为系统目录'

$jsonItems = @(ConvertFrom-AppDataInventoryJson -Json '[{"Name":"A","Bytes":1},{"Name":"B","Bytes":2}]')
Assert-True ($jsonItems.Count -eq 2) 'JSON 数组必须在 Windows PowerShell 5.1 中展开为两个项目'
Assert-True ((Measure-CleanerItemsBytes -Items $jsonItems) -eq 3) 'JSON 项目的字节数汇总必须正确'
Assert-True ((Measure-CleanerItemsBytes -Items @()) -eq 0) '空选择集合的字节数必须安全地汇总为 0'

$inventory = @(Get-CleanerInventory)
Assert-True (@($inventory | Where-Object Selected).Count -eq 0) '所有清理候选都必须默认不勾选'
foreach ($item in $inventory) {
    Assert-True ($item.Kind -eq '用户级数据') '删除候选必须全部标为用户级数据'
    Assert-True (-not (Test-ProtectedPath $item.Path)) "删除候选不得位于系统目录：$($item.Path)"
}

for ($i = 0; $i -lt $inventory.Count; $i++) {
    if ($inventory[$i].DeleteMode -ne 'Contents') { continue }
    $left = $inventory[$i].Path.TrimEnd('\')
    for ($j = $i + 1; $j -lt $inventory.Count; $j++) {
        if ($inventory[$j].DeleteMode -ne 'Contents') { continue }
        $right = $inventory[$j].Path.TrimEnd('\')
        $overlap = $left.StartsWith($right + '\', [StringComparison]::OrdinalIgnoreCase) -or
                   $right.StartsWith($left + '\', [StringComparison]::OrdinalIgnoreCase)
        Assert-True (-not $overlap) "可清空目录不能互相嵌套：$left / $right"
    }
}

$appDataInventory = @(Get-AppDataUsageInventory)
Assert-True (@($appDataInventory | Where-Object Selected).Count -eq 0) '所有 AppData 项目都必须默认不勾选'
foreach ($appDataItem in $appDataInventory) {
    Assert-True ($appDataItem.Kind -eq '用户级数据') 'AppData 项目必须经过用户级路径保护规则'
    Assert-True ($appDataItem.Source -eq 'AppData') 'AppData 项目必须带有高风险来源标记'
    Assert-True ($appDataItem.DeleteMode -eq 'Contents') 'AppData 项目只能清空内容，不能删除根目录'
    Assert-True (-not (Test-ProtectedPath $appDataItem.Path)) "AppData 项目不得位于系统保护目录：$($appDataItem.Path)"
}

Write-Output "PASS: $($inventory.Count) 个候选项通过路径保护检查。"
