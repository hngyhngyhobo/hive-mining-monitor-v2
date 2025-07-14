# Dockerized Hive Mining Monitor - PowerShell 5.1+ Compatible
# Now with comprehensive file logging and configurable environment variables

# =================================================================
# Configuration from Environment Variables
# =================================================================

# Required environment variables - will exit if not provided
$apiToken = $env:HIVE_API_TOKEN
if ([string]::IsNullOrEmpty($apiToken)) {
    Write-Error "HIVE_API_TOKEN environment variable is required"
    Write-Host "Get your token from: https://hiveos.farm -> Account Settings -> API" -ForegroundColor Yellow
    exit 1
}

$farmId = $env:HIVE_FARM_ID
if ([string]::IsNullOrEmpty($farmId)) {
    Write-Error "HIVE_FARM_ID environment variable is required"
    Write-Host "Find your Farm ID in the HiveOS dashboard URL (the number after /farms/)" -ForegroundColor Yellow
    exit 1
}

$mqttBroker = $env:MQTT_BROKER
if ([string]::IsNullOrEmpty($mqttBroker)) {
    Write-Error "MQTT_BROKER environment variable is required"
    Write-Host "Set this to your MQTT broker IP address or hostname" -ForegroundColor Yellow
    exit 1
}

# Optional environment variables with defaults
$mqttPort = if ($env:MQTT_PORT) { $env:MQTT_PORT } else { "1883" }
$mqttUsername = if ($env:MQTT_USERNAME) { $env:MQTT_USERNAME } else { "" }
$mqttPassword = if ($env:MQTT_PASSWORD) { $env:MQTT_PASSWORD } else { "" }
$runInterval = if ($env:RUN_INTERVAL) { [int]$env:RUN_INTERVAL } else { 300 }
$logLevel = if ($env:LOG_LEVEL) { $env:LOG_LEVEL } else { "INFO" }

# Logging configuration
$enableFileLogging = if ($env:ENABLE_FILE_LOGGING) { $env:ENABLE_FILE_LOGGING -eq "true" } else { $true }
$maxLogFiles = if ($env:MAX_LOG_FILES) { [int]$env:MAX_LOG_FILES } else { 7 }
$logDirectory = "/logs"

# API URLs
$farmWorkersUrl = "https://api2.hiveos.farm/api/v2/farms/$farmId/workers"
$headers = @{
    "Authorization" = "Bearer $apiToken"
    "Content-Type" = "application/json"
}

# =================================================================
# Logging Functions
# =================================================================
function Write-LogMessage {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Color = "White"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Always write to console
    Write-Host $logMessage -ForegroundColor $Color
    
    # Write to file if logging is enabled
    if ($enableFileLogging) {
        try {
            # Ensure log directory exists
            if (-not (Test-Path $logDirectory)) {
                New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
            }
            
            # Main log file
            $logFile = Join-Path $logDirectory "mining-monitor.log"
            Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
            
            # Daily log file
            $dailyLogFile = Join-Path $logDirectory "mining-monitor-$(Get-Date -Format 'yyyy-MM-dd').log"
            Add-Content -Path $dailyLogFile -Value $logMessage -ErrorAction SilentlyContinue
            
            # Level-specific log files
            if ($Level -eq "ERROR") {
                $errorFile = Join-Path $logDirectory "error.log"
                Add-Content -Path $errorFile -Value $logMessage -ErrorAction SilentlyContinue
            }
            elseif ($Level -eq "DEBUG") {
                $debugFile = Join-Path $logDirectory "debug.log"
                Add-Content -Path $debugFile -Value $logMessage -ErrorAction SilentlyContinue
            }
        }
        catch {
            # If logging fails, don't crash the application
            Write-Host "Warning: Failed to write to log file: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

function Write-InfoLog {
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "INFO" -Color "White"
}

function Write-SuccessLog {
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "SUCCESS" -Color "Green"
}

function Write-WarningLog {
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "WARNING" -Color "Yellow"
}

function Write-ErrorLog {
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "ERROR" -Color "Red"
}

function Write-DebugLog {
    param([string]$Message)
    if ($logLevel -eq "DEBUG") {
        Write-LogMessage -Message $Message -Level "DEBUG" -Color "Gray"
    }
}

function Clean-OldLogFiles {
    if ($enableFileLogging -and $maxLogFiles -gt 0) {
        try {
            # Clean up old daily log files
            $dailyLogs = Get-ChildItem -Path $logDirectory -Filter "mining-monitor-*.log" | Sort-Object LastWriteTime -Descending
            if ($dailyLogs.Count -gt $maxLogFiles) {
                $logsToDelete = $dailyLogs | Select-Object -Skip $maxLogFiles
                foreach ($log in $logsToDelete) {
                    Remove-Item $log.FullName -Force
                    Write-DebugLog "Deleted old log file: $($log.Name)"
                }
            }
        }
        catch {
            Write-WarningLog "Failed to clean old log files: $($_.Exception.Message)"
        }
    }
}

function Write-StartupLog {
    Write-InfoLog "=== Hive Mining Monitor Starting ==="
    Write-InfoLog "Container: $env:HOSTNAME"
    Write-InfoLog "Farm ID: $farmId"
    Write-InfoLog "MQTT Broker: $mqttBroker`:$mqttPort"
    if ($mqttUsername) {
        Write-InfoLog "MQTT Auth: Enabled (user: $mqttUsername)"
    } else {
        Write-InfoLog "MQTT Auth: Disabled"
    }
    Write-InfoLog "Update Interval: $runInterval seconds"
    Write-InfoLog "Log Level: $logLevel"
    Write-InfoLog "File Logging: $(if ($enableFileLogging) { 'Enabled' } else { 'Disabled' })"
    if ($enableFileLogging) {
        Write-InfoLog "Log Directory: $logDirectory"
        Write-InfoLog "Max Log Files: $maxLogFiles"
    }
    Write-InfoLog "Timezone: $env:TZ"
    Write-InfoLog "==========================================="
}

# =================================================================
# MQTT Publishing Function
# =================================================================
function Publish-MQTTMessage {
    param(
        [string]$Topic,
        [string]$Message,
        [string]$Broker = $mqttBroker,
        [string]$Port = $mqttPort
    )
    
    Write-DebugLog "Publishing MQTT: $Topic = '$Message'"
    
    try {
        Publish-MQTTMessage-Fallback -Topic $Topic -Message $Message -Broker $Broker -Port $Port
    }
    catch {
        Write-ErrorLog "MQTT Error: $($_.Exception.Message)"
    }
}

# =================================================================
# MQTT TCP Fallback Function
# =================================================================
function Publish-MQTTMessage-Fallback {
    param(
        [string]$Topic,
        [string]$Message,
        [string]$Broker = $mqttBroker,
        [string]$Port = $mqttPort
    )
    
    $tcpClient = $null
    try {
        Write-DebugLog "Attempting MQTT connection to $Broker`:$Port"
        
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ReceiveTimeout = 3000
        $tcpClient.SendTimeout = 3000
        
        $tcpClient.Connect($Broker, [int]$Port)
        Write-DebugLog "TCP connection established to MQTT broker"
        
        $stream = $tcpClient.GetStream()
        
        # MQTT CONNECT packet
        $clientId = "HiveMiner-" + (Get-Random -Maximum 9999)
        if ($env:HOSTNAME) {
            $clientId = "HiveMiner-" + $env:HOSTNAME + "-" + (Get-Random -Maximum 9999)
        }
        $clientIdBytes = [System.Text.Encoding]::UTF8.GetBytes($clientId)
        
        Write-DebugLog "MQTT Client ID: $clientId"
        
        # Calculate packet size including authentication
        $usernameBytes = @()
        $passwordBytes = @()
        if ($mqttUsername) {
            $usernameBytes = [System.Text.Encoding]::UTF8.GetBytes($mqttUsername)
            Write-DebugLog "Using MQTT authentication for user: $mqttUsername"
        }
        if ($mqttPassword) {
            $passwordBytes = [System.Text.Encoding]::UTF8.GetBytes($mqttPassword)
        }
        
        $connectFlags = 0x00
        if ($mqttUsername -and $mqttPassword) {
            $connectFlags = 0xC0  # Username and password flags
        }
        
        $variableHeaderLength = 10
        $payloadLength = 2 + $clientIdBytes.Length
        
        if ($mqttUsername) {
            $payloadLength += 2 + $usernameBytes.Length
        }
        if ($mqttPassword) {
            $payloadLength += 2 + $passwordBytes.Length
        }
        
        $remainingLength = $variableHeaderLength + $payloadLength
        
        $connectPacket = @(
            0x10,  # CONNECT packet type
            $remainingLength,  # Remaining length
            0x00, 0x04,  # Protocol name length
            0x4d, 0x51, 0x54, 0x54,  # "MQTT"
            0x04,  # Protocol level (3.1.1)
            $connectFlags,  # Connect flags
            0x00, 0x3c,  # Keep alive (60 seconds)
            0x00, $clientIdBytes.Length  # Client ID length
        ) + $clientIdBytes
        
        # Add username if provided
        if ($mqttUsername) {
            $connectPacket += @(0x00, $usernameBytes.Length) + $usernameBytes
        }
        
        # Add password if provided
        if ($mqttPassword) {
            $connectPacket += @(0x00, $passwordBytes.Length) + $passwordBytes
        }
        
        Write-DebugLog "Sending MQTT CONNECT packet"
        $stream.Write($connectPacket, 0, $connectPacket.Length)
        $stream.Flush()
        
        # Read CONNACK
        Start-Sleep -Milliseconds 300
        $response = New-Object byte[] 10
        $bytesRead = $stream.Read($response, 0, 10)
        
        if ($bytesRead -ge 4 -and $response[0] -eq 0x20 -and $response[3] -eq 0x00) {
            Write-DebugLog "Received MQTT CONNACK - connection successful"
            
            # MQTT PUBLISH packet
            $topicBytes = [System.Text.Encoding]::UTF8.GetBytes($Topic)
            $messageBytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
            
            $remainingLength = 2 + $topicBytes.Length + $messageBytes.Length
            $publishPacket = @(
                0x30,  # PUBLISH packet type
                $remainingLength,  # Remaining length
                0x00, $topicBytes.Length  # Topic length
            ) + $topicBytes + $messageBytes
            
            Write-DebugLog "Publishing message to topic: $Topic"
            $stream.Write($publishPacket, 0, $publishPacket.Length)
            $stream.Flush()
            
            Write-DebugLog "MQTT message published successfully"
        } else {
            Write-ErrorLog "MQTT connection failed - CONNACK error code: $($response[3])"
            Write-DebugLog "CONNACK response: $($response[0..9] -join ' ')"
        }
        
        $stream.Close()
        $tcpClient.Close()
        
    }
    catch {
        Write-ErrorLog "MQTT TCP Error: $($_.Exception.Message)"
        Write-DebugLog "MQTT connection details - Broker: $Broker, Port: $Port"
        if ($tcpClient) {
            try {
                $tcpClient.Close()
            }
            catch {
                Write-DebugLog "Error closing TCP client: $($_.Exception.Message)"
            }
        }
    }
}

# =================================================================
# Convert seconds to friendly uptime format
# =================================================================
function Convert-SecondsToUptime {
    param([int]$Seconds)
    
    if ($Seconds -eq 0) { return "Unknown" }
    
    $days = [Math]::Floor($Seconds / 86400)
    $hours = [Math]::Floor(($Seconds % 86400) / 3600)
    $minutes = [Math]::Floor(($Seconds % 3600) / 60)
    
    $uptime = ""
    if ($days -gt 0) { $uptime += "${days}d " }
    if ($hours -gt 0) { $uptime += "${hours}h " }
    if ($minutes -gt 0) { $uptime += "${minutes}m" }
    
    return $uptime.Trim()
}

# =================================================================
# Extract hashrate from HiveOS response
# =================================================================
function Get-HashrateFromWorker {
    param($workerData)
    
    try {
        $hashrate = 0
        
        $jsonString = $workerData | ConvertTo-Json -Depth 10
        
        $hashMatches = [regex]::Matches($jsonString, '"hash":\s*([0-9.]+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($match in $hashMatches) {
            if ($match.Groups[1].Value) {
                $foundValue = [double]$match.Groups[1].Value
                if ($foundValue -gt 0) {
                    $hashrate = $foundValue
                    Write-DebugLog "Found hashrate: $foundValue KH/s"
                    break
                }
            }
        }
        
        if ($hashrate -eq 0) {
            Write-WarningLog "No hashrate found for this worker"
        }
        
        return $hashrate
    }
    catch {
        Write-ErrorLog "Error extracting hashrate: $($_.Exception.Message)"
        return 0
    }
}

# =================================================================
# Extract CPU temperature from HiveOS response
# =================================================================
function Get-CpuTemperatureFromWorker {
    param($workerData)
    
    try {
        $cpuTemp = $null
        
        if ($workerData.hardware_stats -and $workerData.hardware_stats.cputemp) {
            if ($workerData.hardware_stats.cputemp -is [array] -and $workerData.hardware_stats.cputemp.Count -gt 0) {
                $cpuTemp = [int]$workerData.hardware_stats.cputemp[0]
                Write-DebugLog "Found CPU temp in hardware_stats.cputemp[0]: $cpuTemp°C"
            }
        }
        
        if ($cpuTemp -eq $null -and $workerData.stats -and $workerData.stats.temps) {
            if ($workerData.stats.temps -is [array] -and $workerData.stats.temps.Count -gt 0) {
                $cpuTemp = [int]$workerData.stats.temps[0]
                Write-DebugLog "Found CPU temp in stats.temps[0]: $cpuTemp°C"
            }
        }
        
        return $cpuTemp
    }
    catch {
        Write-ErrorLog "Error extracting CPU temperature: $($_.Exception.Message)"
        return $null
    }
}

# =================================================================
# Main data collection and publishing function
# =================================================================
function Get-MiningDataAndPublish {
    Write-InfoLog "=== Mining Data Collection Started ==="
    Write-InfoLog "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    try {
        $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        
        # Publish heartbeat
        Write-DebugLog "Publishing heartbeat"
        Publish-MQTTMessage -Topic "mining/heartbeat" -Message "alive"
        
        # Fetch workers data from HiveOS API
        Write-DebugLog "Fetching workers data from HiveOS API: $farmWorkersUrl"
        
        $response = Invoke-RestMethod -Uri $farmWorkersUrl -Headers $headers -Method Get -TimeoutSec 30
        
        if (-not $response -or -not $response.data) {
            Write-ErrorLog "No data received from HiveOS API"
            return
        }
        
        Write-SuccessLog "Successfully retrieved data for $($response.data.Count) workers from HiveOS"
        
        # Publish timestamp
        Publish-MQTTMessage -Topic "mining/farm/$farmId/timestamp" -Message $timestamp
        
        $totalWorkers = $response.data.Count
        $onlineWorkers = ($response.data | Where-Object { $_.stats.online -eq $true }).Count
        $offlineWorkers = $totalWorkers - $onlineWorkers
        
        # Publish summary data
        Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/count" -Message $totalWorkers
        Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/online" -Message $onlineWorkers
        Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/offline" -Message $offlineWorkers
        
        Write-SuccessLog "Farm Summary: $onlineWorkers/$totalWorkers workers online"
        
        $totalHashrate = 0
        $uptimeSum = 0
        $onlineCount = 0
        $cpuTempSum = 0
        $cpuTempCount = 0
        
        foreach ($worker in $response.data) {
            $workerId = $worker.id
            $workerName = $worker.name
            $isOnline = $worker.stats.online
            
            Write-DebugLog "Processing worker: $workerName (ID: $workerId) - Online: $isOnline"
            
            Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/$workerId/name" -Message $workerName
            $onlineStatus = if ($isOnline) { "true" } else { "false" }
            Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/$workerId/online" -Message $onlineStatus
            
            try {
                $workerApiUrl = "https://api2.hiveos.farm/api/v2/farms/$farmId/workers/$workerId"
                Write-DebugLog "Fetching detailed worker data: $workerApiUrl"
                
                $workerResponse = Invoke-RestMethod -Uri $workerApiUrl -Headers $headers -Method Get -TimeoutSec 30
                
                if ($workerResponse) {
                    $flightSheet = if ($workerResponse.flight_sheet -and $workerResponse.flight_sheet.name) {
                        $workerResponse.flight_sheet.name
                    } else {
                        "Not Assigned"
                    }
                    Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/$workerId/flight_sheet" -Message $flightSheet
                    
                    $hashrate = Get-HashrateFromWorker -workerData $workerResponse
                    $totalHashrate += $hashrate
                    Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/$workerId/hashrate" -Message $hashrate.ToString("F3")
                    
                    if ($workerResponse.stats -and $workerResponse.stats.boot_time) {
                        $currentUnixTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                        $uptime = $currentUnixTime - $workerResponse.stats.boot_time
                        $uptimeSum += $uptime
                        $friendlyUptime = Convert-SecondsToUptime -Seconds $uptime
                        
                        Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/$workerId/uptime" -Message $uptime
                        Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/$workerId/uptime_friendly" -Message $friendlyUptime
                    } else {
                        Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/$workerId/uptime" -Message "0"
                        Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/$workerId/uptime_friendly" -Message "Unknown"
                    }
                    
                    $cpuTemp = Get-CpuTemperatureFromWorker -workerData $workerResponse
                    if ($cpuTemp -ne $null) {
                        Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/$workerId/cpu_temperature" -Message $cpuTemp
                        $cpuTempSum += $cpuTemp
                        $cpuTempCount++
                    }
                    
                    if ($workerResponse.stats -and $workerResponse.stats.power_draw) {
                        Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/$workerId/power_draw" -Message $workerResponse.stats.power_draw
                    }
                    
                    if ($workerResponse.stats -and $workerResponse.stats.stats_time) {
                        $lastSeen = $workerResponse.stats.stats_time
                        Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/$workerId/last_seen" -Message $lastSeen
                    }
                    
                    if ($isOnline) { $onlineCount++ }
                    
                    Write-DebugLog "Completed processing worker: $workerName"
                }
            }
            catch {
                Write-ErrorLog "Failed to get detailed info for worker $workerName`: $($_.Exception.Message)"
            }
        }
        
        # Publish farm summary statistics
        Publish-MQTTMessage -Topic "mining/farm/$farmId/summary/total_hashrate" -Message $totalHashrate.ToString("F3")
        
        if ($onlineCount -gt 0) {
            $avgUptime = [int]($uptimeSum / $onlineCount)
            Publish-MQTTMessage -Topic "mining/farm/$farmId/summary/average_uptime" -Message $avgUptime
        }
        
        if ($cpuTempCount -gt 0) {
            $avgCpuTemp = [Math]::Round($cpuTempSum / $cpuTempCount, 1)
            Publish-MQTTMessage -Topic "mining/farm/$farmId/summary/average_cpu_temp" -Message $avgCpuTemp
        }
        
        $efficiency = if ($totalWorkers -gt 0) { ($onlineWorkers / $totalWorkers * 100).ToString("F1") } else { "0" }
        Publish-MQTTMessage -Topic "mining/farm/$farmId/summary/efficiency" -Message $efficiency
        
        Write-SuccessLog "=== Data Collection Completed Successfully ==="
        Write-SuccessLog "Total Hashrate: $($totalHashrate.ToString('F3')) KH/s"
        Write-SuccessLog "Farm Efficiency: $efficiency%"
        if ($cpuTempCount -gt 0) {
            Write-SuccessLog "Average CPU Temperature: $($avgCpuTemp)°C"
        }
        Write-InfoLog "Published data to $($totalWorkers * 6 + 6) MQTT topics"
        
    }
    catch {
        Write-ErrorLog "Error in main data collection: $($_.Exception.Message)"
        Write-DebugLog "Stack trace: $($_.ScriptStackTrace)"
        Publish-MQTTMessage -Topic "mining/farm/$farmId/error" -Message $_.Exception.Message
    }
}

# =================================================================
# Main execution loop
# =================================================================
function Start-MiningMonitor {
    # Clean old log files on startup
    Clean-OldLogFiles
    
    # Write startup information
    Write-StartupLog
    
    # Test MQTT connection first
    Write-InfoLog "Testing MQTT broker connectivity..."
    try {
        $testConnection = New-Object System.Net.Sockets.TcpClient
        $testConnection.ReceiveTimeout = 5000
        $testConnection.SendTimeout = 5000
        $testConnection.Connect($mqttBroker, [int]$mqttPort)
        $testConnection.Close()
        Write-SuccessLog "MQTT broker is reachable at $mqttBroker`:$mqttPort"
    }
    catch {
        Write-ErrorLog "Cannot reach MQTT broker at $mqttBroker`:$mqttPort - $($_.Exception.Message)"
        Write-WarningLog "Will continue and retry MQTT connection during operation"
    }
    
    # Test HiveOS API connectivity
    Write-InfoLog "Testing HiveOS API connectivity..."
    try {
        $testUrl = "https://api2.hiveos.farm"
        $testResponse = Invoke-WebRequest -Uri $testUrl -Method Head -TimeoutSec 10
        Write-SuccessLog "HiveOS API is reachable"
    }
    catch {
        Write-ErrorLog "Cannot reach HiveOS API - $($_.Exception.Message)"
    }
    
    Write-InfoLog "Starting main monitoring loop..."
    Publish-MQTTMessage -Topic "mining/status" -Message "Hive Mining Monitor started successfully"
    
    $iteration = 0
    while ($true) {
        try {
            $iteration++
            Write-InfoLog "=== Starting iteration #$iteration ==="
            
            Get-MiningDataAndPublish
            
            Write-InfoLog "Iteration #$iteration completed successfully"
            Write-InfoLog "Waiting $runInterval seconds until next update..."
            Write-InfoLog ""
            
            Start-Sleep -Seconds $runInterval
        }
        catch {
            Write-ErrorLog "Error in main loop iteration #$iteration`: $($_.Exception.Message)"
            Write-WarningLog "Retrying in 30 seconds..."
            Start-Sleep -Seconds 30
        }
    }
}

# =================================================================
# Entry Point
# =================================================================
if ($args[0] -eq "-once") {
    # Clean old log files
    Clean-OldLogFiles
    # Write startup information
    Write-StartupLog
    # Run once for testing
    Get-MiningDataAndPublish
} else {
    # Run continuously
    Start-MiningMonitor
}