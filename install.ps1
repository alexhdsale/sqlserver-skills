# Installs every skill in this repo for Claude Code, Codex CLI, GitHub Copilot CLI and SSMS 22 Copilot.
# Usage:  git clone https://github.com/alexhdsale/sqlserver-skills.git ; cd sqlserver-skills ; .\install.ps1
param([string[]]$Targets = @("$HOME\.claude\skills", "$HOME\.agents\skills", "$HOME\.copilot\skills"))

$src = Join-Path $PSScriptRoot "skills"
foreach ($t in $Targets) {
    New-Item -ItemType Directory -Force $t | Out-Null
    Get-ChildItem $src -Directory | ForEach-Object {
        $dest = Join-Path $t $_.Name
        if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
        Copy-Item -Recurse -Force $_.FullName $dest
        Write-Host "installed $($_.Name) -> $dest"
    }
}
Write-Host "`nDone. Restart Claude Code / Copilot / SSMS. In Claude Code you can also use:"
Write-Host "  /plugin marketplace add alexhdsale/sqlserver-skills"
Write-Host "  /plugin install sqlserver-skills@alexhdsale"
