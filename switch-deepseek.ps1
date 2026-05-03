# DeepSeek Switch Script
# Usage: .\switch-deepseek.ps1 <status|switch|restore>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("status", "switch", "restore")]
    [string]$Command
)

# ============================================================
# Constants
# ============================================================

$SETTINGS_PATH = "$env:USERPROFILE\.claude\settings.json"
$BACKUP_PATH = "$env:USERPROFILE\.claude\settings.json.deepseek-switch.backup"
$TEMP_PATH = "$env:USERPROFILE\.claude\settings.json.tmp"

# DeepSeek Target Config
$DEEPSEEK_BASE_URL = "https://api.deepseek.com/anthropic"
$DEEPSEEK_MODEL = "deepseek-v4-flash"
$DEEPSEEK_API_KEY = "sk-d4ed88714cd54c31b0d01d371c5f32c1"

# ============================================================
# Helper Functions
# ============================================================

function Get-JsonFile {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }

    $content = Get-Content $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($content)) {
        throw "File is empty: $Path"
    }

    try {
        $json = $content | ConvertFrom-Json
    } catch {
        throw "JSON parse failed: $Path - $_"
    }

    if ($json -isnot [PSCustomObject]) {
        throw "JSON root must be object: $Path"
    }

    return $json
}

function Set-JsonFile {
    param(
        [PSCustomObject]$Json,
        [string]$Path
    )

    try {
        $output = $json | ConvertTo-Json -Depth 100 -Compress
        $output | Out-File -FilePath $Path -Encoding UTF8 -Force
    } catch {
        throw "Write failed: $Path - $_"
    }
}

function Test-JsonObject {
    param([object]$Obj)

    if ($Obj -isnot [PSCustomObject]) {
        return $false
    }
    return $true
}

# ============================================================
# Status Detection
# ============================================================

function Get-CurrentStatus {
    $result = @{
        ConfigExists = $false
        BackupExists = $false
        Status = "unknown"
        Fields = @{}
    }

    $result.ConfigExists = Test-Path $SETTINGS_PATH
    $result.BackupExists = Test-Path $BACKUP_PATH

    if (-not $result.ConfigExists) {
        $result.Status = "unknown"
        return $result
    }

    try {
        $json = Get-JsonFile $SETTINGS_PATH

        $envObj = $null
        if ($json.PSObject.Properties.Name -contains "env") {
            $envObj = $json.env
        }

        $fields = @{}

        if ($envObj) {
            $fields.BASE_URL = if ($envObj.ANTHROPIC_BASE_URL) { $envObj.ANTHROPIC_BASE_URL } else { $null }
            $fields.MODEL = if ($envObj.ANTHROPIC_MODEL) { $envObj.ANTHROPIC_MODEL } else { $null }
            $fields.HAIKU_MODEL = if ($envObj.ANTHROPIC_DEFAULT_HAIKU_MODEL) { $envObj.ANTHROPIC_DEFAULT_HAIKU_MODEL } else { $null }
            $fields.SONNET_MODEL = if ($envObj.ANTHROPIC_DEFAULT_SONNET_MODEL) { $envObj.ANTHROPIC_DEFAULT_SONNET_MODEL } else { $null }
            $fields.OPUS_MODEL = if ($envObj.ANTHROPIC_DEFAULT_OPUS_MODEL) { $envObj.ANTHROPIC_DEFAULT_OPUS_MODEL } else { $null }
            $fields.HAS_API_KEY = $null -ne $envObj.ANTHROPIC_API_KEY
            $fields.HAS_AUTH_TOKEN = $null -ne $envObj.ANTHROPIC_AUTH_TOKEN
        }

        $fields.TOP_MODEL = if ($json.PSObject.Properties.Name -contains "model") { $json.model } else { $null }

        $result.Fields = $fields

        # Status detection
        if ($fields.BASE_URL -eq $DEEPSEEK_BASE_URL -and $fields.MODEL -eq $DEEPSEEK_MODEL) {
            $result.Status = "deepseek-like"
        } elseif ($fields.MODEL -match "claude|opus|sonnet|haiku" -or
                  $fields.HAIKU_MODEL -match "claude|haiku" -or
                  $fields.SONNET_MODEL -match "claude|sonnet" -or
                  $fields.OPUS_MODEL -match "claude|opus") {
            $result.Status = "claude-like"
        } else {
            $result.Status = "unknown"
        }

    } catch {
        $result.Status = "unknown"
    }

    return $result
}

# ============================================================
# Command Implementations
# ============================================================

function Invoke-Status {
    Write-Host ""
    Write-Host "=== Claude Code Config Status ===" -ForegroundColor Cyan
    Write-Host ""

    $status = Get-CurrentStatus

    Write-Host "Config file: $SETTINGS_PATH"
    Write-Host "Config exists: $(if ($status.ConfigExists) { 'Yes' } else { 'No' })"
    Write-Host ""
    Write-Host "Backup file: $BACKUP_PATH"
    Write-Host "Backup exists: $(if ($status.BackupExists) { 'Yes' } else { 'No' })"
    Write-Host ""
    Write-Host "Current status: $($status.Status)"
    Write-Host ""

    if ($status.ConfigExists -and $status.Fields.Count -gt 0) {
        Write-Host "=== Key Fields ===" -ForegroundColor Yellow
        $f = $status.Fields
        Write-Host "  ANTHROPIC_BASE_URL: $($f.BASE_URL)"
        Write-Host "  ANTHROPIC_MODEL: $($f.MODEL)"
        Write-Host "  ANTHROPIC_DEFAULT_HAIKU_MODEL: $($f.HAIKU_MODEL)"
        Write-Host "  ANTHROPIC_DEFAULT_SONNET_MODEL: $($f.SONNET_MODEL)"
        Write-Host "  ANTHROPIC_DEFAULT_OPUS_MODEL: $($f.OPUS_MODEL)"
        Write-Host "  Top-level model: $($f.TOP_MODEL)"
        Write-Host "  ANTHROPIC_API_KEY: $(if ($f.HAS_API_KEY) { 'Set' } else { 'Not set' })"
        Write-Host "  ANTHROPIC_AUTH_TOKEN: $(if ($f.HAS_AUTH_TOKEN) { 'Set' } else { 'Not set' })"
    }

    Write-Host ""
}

function Invoke-Switch {
    Write-Host ""
    Write-Host "=== Switch to DeepSeek Config ===" -ForegroundColor Cyan
    Write-Host ""

    # Pre-check
    if (-not (Test-Path $SETTINGS_PATH)) {
        Write-Error "Config file not found: $SETTINGS_PATH"
        exit 1
    }

    # Check readability
    try {
        $null = Get-Content $SETTINGS_PATH -ErrorAction Stop
    } catch {
        Write-Error "Config file not readable: $SETTINGS_PATH"
        exit 1
    }

    # Parse JSON
    $json = $null
    try {
        $json = Get-JsonFile $SETTINGS_PATH
    } catch {
        Write-Error $_
        exit 1
    }

    # Check env object
    if ($null -ne $json.env -and -not (Test-JsonObject $json.env)) {
        Write-Error "env exists but is not an object"
        exit 1
    }

    # Backup
    if (-not (Test-Path $BACKUP_PATH)) {
        Write-Host "Creating backup..."
        try {
            Copy-Item $SETTINGS_PATH $BACKUP_PATH -Force
            Write-Host "Backup created: $BACKUP_PATH" -ForegroundColor Green
        } catch {
            Write-Error "Backup failed: $_"
            exit 1
        }
    } else {
        Write-Host "Backup already exists, skipping" -ForegroundColor Yellow
    }

    # Ensure env object exists
    if ($null -eq $json.env) {
        $json | Add-Member -NotePropertyName "env" -NotePropertyValue ([PSCustomObject]@{}) -ErrorAction Stop
    }

    # Patch whitelist fields
    Write-Host "Updating config..."

    $json.env | Add-Member -NotePropertyName "ANTHROPIC_BASE_URL" -NotePropertyValue $DEEPSEEK_BASE_URL -Force -ErrorAction Stop
    $json.env | Add-Member -NotePropertyName "ANTHROPIC_MODEL" -NotePropertyValue $DEEPSEEK_MODEL -Force -ErrorAction Stop
    $json.env | Add-Member -NotePropertyName "ANTHROPIC_API_KEY" -NotePropertyValue $DEEPSEEK_API_KEY -Force -ErrorAction Stop
    $json.env | Add-Member -NotePropertyName "ANTHROPIC_DEFAULT_HAIKU_MODEL" -NotePropertyValue $DEEPSEEK_MODEL -Force -ErrorAction Stop
    $json.env | Add-Member -NotePropertyName "ANTHROPIC_DEFAULT_SONNET_MODEL" -NotePropertyValue $DEEPSEEK_MODEL -Force -ErrorAction Stop
    $json.env | Add-Member -NotePropertyName "ANTHROPIC_DEFAULT_OPUS_MODEL" -NotePropertyValue $DEEPSEEK_MODEL -Force -ErrorAction Stop

    # Safe write
    try {
        Set-JsonFile $json $TEMP_PATH
        Move-Item -Path $TEMP_PATH -Destination $SETTINGS_PATH -Force
        Write-Host "Config updated: $SETTINGS_PATH" -ForegroundColor Green
    } catch {
        Write-Error "Write failed: $_"
        if (Test-Path $TEMP_PATH) {
            Remove-Item $TEMP_PATH -Force -ErrorAction SilentlyContinue
        }
        exit 1
    }

    Write-Host ""
    Write-Host "Switch complete!" -ForegroundColor Green
    Write-Host ""
}

function Invoke-Restore {
    Write-Host ""
    Write-Host "=== Restore Original Config ===" -ForegroundColor Cyan
    Write-Host ""

    # Pre-check
    if (-not (Test-Path $BACKUP_PATH)) {
        Write-Error "Backup not found: $BACKUP_PATH"
        Write-Host "Please run 'switch' first to create backup." -ForegroundColor Yellow
        exit 1
    }

    # Check readability
    try {
        $null = Get-Content $BACKUP_PATH -ErrorAction Stop
    } catch {
        Write-Error "Backup not readable: $BACKUP_PATH"
        exit 1
    }

    # Validate backup JSON
    try {
        $null = Get-JsonFile $BACKUP_PATH
    } catch {
        Write-Error $_
        exit 1
    }

    # Restore
    try {
        Copy-Item $BACKUP_PATH $SETTINGS_PATH -Force
        Write-Host "Config restored: $SETTINGS_PATH" -ForegroundColor Green
    } catch {
        Write-Error "Restore failed: $_"
        exit 1
    }

    Write-Host ""
    Write-Host "Restore complete!" -ForegroundColor Green
    Write-Host ""
}

# ============================================================
# Entry Point
# ============================================================

switch ($Command) {
    "status" { Invoke-Status }
    "switch" { Invoke-Switch }
    "restore" { Invoke-Restore }
}
