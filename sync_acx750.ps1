<#
.SYNOPSIS
  将 acx750_ov5640_ddr3_hdmi_16bit 的已提交 HEAD 同步到 Car_radar 的 cong 分支。
.DESCRIPTION
  方案 A：原始项目继续作为工作目录；本脚本把原始项目的 git HEAD 导出为快照，
  替换 Car_radar\acx750_ov5640_ddr3_hdmi_16bit，提交（中文）并推送。
  只同步已提交的内容；原始项目有未提交修改时脚本拒绝执行。
.PARAMETER ProjectPath
  原始项目路径，默认 D:\Xilinx\FPGAProject\acx750_ov5640_ddr3_hdmi_16bit
.PARAMETER RepoPath
  Car_radar 仓库路径，默认 D:\Xilinx\FPGAProject\Car_radar
.PARAMETER Branch
  推送分支，默认 cong
.PARAMETER Message
  自定义提交信息；默认“同步 acx750_ov5640_ddr3_hdmi_16bit：<短哈希>”
#>
param(
    [string]$ProjectPath = "D:\Xilinx\FPGAProject\acx750_ov5640_ddr3_hdmi_16bit",
    [string]$RepoPath    = "D:\Xilinx\FPGAProject\Car_radar",
    [string]$Branch      = "cong",
    [string]$Message     = ""
)

$ErrorActionPreference = "Stop"

function Fail($msg) { Write-Host "[失败] $msg" -ForegroundColor Red; exit 1 }
function Info($msg) { Write-Host "[信息] $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "[完成] $msg" -ForegroundColor Green }

# 路径检查
if (-not (Test-Path $ProjectPath)) { Fail "原始项目不存在：$ProjectPath" }
if (-not (Test-Path $RepoPath))    { Fail "Car_radar 仓库不存在：$RepoPath" }
if (-not (Test-Path (Join-Path $ProjectPath ".git"))) { Fail "原始项目不是 git 仓库：$ProjectPath" }
if (-not (Test-Path (Join-Path $RepoPath ".git")))    { Fail "Car_radar 不是 git 仓库：$RepoPath" }

# 原始项目必须干净（只同步已提交的 HEAD）
$dirty = git -C $ProjectPath status --porcelain
if ($dirty) {
    Fail "原始项目有未提交修改，请先提交后再同步：`n$dirty"
}

# 分支检查
$cur = (git -C $RepoPath rev-parse --abbrev-ref HEAD).Trim()
if ($cur -ne $Branch) {
    Fail "Car_radar 当前分支是 $cur，不是 $Branch；请先切换：git -C `"$RepoPath`" checkout $Branch"
}

$short   = (git -C $ProjectPath rev-parse --short HEAD).Trim()
$subject = (git -C $ProjectPath log -1 --pretty=%s).Trim()
$folder  = Split-Path -Leaf $ProjectPath
$dest    = Join-Path $RepoPath $folder
$tmp     = Join-Path $env:TEMP ("acx750_sync_" + [guid]::NewGuid().ToString("N") + ".tar")

if ([string]::IsNullOrWhiteSpace($Message)) {
    $Message = "同步 ${folder}：$short"
}

Info "原始 HEAD：$short（$subject）"
Info "导出快照到临时文件..."
try {
    git -C $ProjectPath archive --format=tar HEAD -o $tmp
    if ($LASTEXITCODE -ne 0) { Fail "git archive 失败" }

    Info "替换 Car_radar 副本：$dest"
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    tar -xf $tmp -C $dest
    if ($LASTEXITCODE -ne 0) { Fail "解包失败" }
}
finally {
    if (Test-Path $tmp) { Remove-Item -Force $tmp }
}

# 提交
git -C $RepoPath add -A
if ($LASTEXITCODE -ne 0) { Fail "git add 失败" }

$staged = git -C $RepoPath status --porcelain
if (-not $staged) {
    Ok "快照没有变化，无需提交"
    exit 0
}

Info "提交：$Message"
git -C $RepoPath commit -m $Message
if ($LASTEXITCODE -ne 0) { Fail "git commit 失败" }

# 推送：使用 Windows OpenSSH，避免 Git 自带 ssh 的管道问题
$ssh = Join-Path $env:WINDIR "System32\OpenSSH\ssh.exe"
$sshArg = $ssh -replace '\\', '/'
Info "推送 origin/$Branch ..."
git -C $RepoPath -c core.sshCommand="$sshArg" push origin $Branch
if ($LASTEXITCODE -ne 0) { Fail "git push 失败（提交已在本地，可稍后手动重试）" }

$newHash = (git -C $RepoPath rev-parse --short HEAD).Trim()
Ok "同步完成：$folder -> $Branch @ $newHash"
