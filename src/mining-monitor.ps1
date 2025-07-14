# Dockerized Hive Mining Monitor - PowerShell 5.1+ Compatible
# Now with configurable environment variables for Docker deployment

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

# API URLs
$farmWorkersUrl = "https://api2.hiveos.farm/api/v2/farms/$farmId/workers"
$headers = @{
    "Authorization" = "Bearer $apiToken"
    "Content-Type" = "application/json"
}

# Display configuration
Write-Host "=== Hive Mining Monitor Configuration ===" -ForegroundColor Cyan
Write-Host "Farm ID: $farmId" -ForegroundColor Gray
Write-Host "MQTT Broker: $mqttBroker`:$mqttPort" -ForegroundColor Gray
Write-Host "Update Interval: $runInterval seconds" -ForegroundColor Gray
Write-Host "Log Level: $logLevel" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

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
    
    if ($logLevel -eq "DEBUG") {
        Write-Host "MQTT: $Topic = '$Message'" -ForegroundColor Cyan
    }
    
    try {
        Publish-MQTTMessage-Fallback -Topic $Topic -Message $Message -Broker $Broker -Port $Port
    }
    catch {
        Write-Host "MQTT Error: $($_.Exception.Message)" -ForegroundColor Red
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
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ReceiveTimeout = 3000
        $tcpClient.SendTimeout = 3000
        
        $tcpClient.Connect($Broker, [int]$Port)
        $stream = $tcpClient.GetStream()
        
        # MQTT CONNECT packet
        $clientId = "HiveMiner-" + (Get-Random -Maximum 9999)
        $clientIdBytes = [System.Text.Encoding]::UTF8.GetBytes($clientId)
        
        $connectPacket = @(
            0x10,  # CONNECT packet type
            (12 + $clientIdBytes.Length),  # Remaining length
            0x00, 0x04,  # Protocol name length
            0x4d, 0x51, 0x54, 0x54,  # "MQTT"
            0x04,  # Protocol level (3.1.1)
            0x00,  # Connect flags
            0x00, 0x3c,  # Keep alive (60 seconds)
            0x00, $clientIdBytes.Length  # Client ID length
        ) + $clientIdBytes
        
        $stream.Write($connectPacket, 0, $connectPacket.Length)
        $stream.Flush()
        
        # Read CONNACK
        Start-Sleep -Milliseconds 200
        $response = New-Object byte[] 10
        $bytesRead = $stream.Read($response, 0, 10)
        
        if ($bytesRead -ge 4 -and $response[0] -eq 0x20 -and $response[3] -eq 0x00) {
            # MQTT PUBLISH packet
            $topicBytes = [System.Text.Encoding]::UTF8.GetBytes($Topic)
            $messageBytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
            
            $remainingLength = 2 + $topicBytes.Length + $messageBytes.Length
            $publishPacket = @(
                0x30,  # PUBLISH packet type
                $remainingLength,  # Remaining length
                0x00, $topicBytes.Length  # Topic length
            ) + $topicBytes + $messageBytes
            
            $stream.Write($publishPacket, 0, $publishPacket.Length)
            $stream.Flush()
            
            if ($logLevel -eq "DEBUG") {
                Write-Host "Published successfully" -ForegroundColor Green
            }
        } else {
            Write-Host "MQTT connection failed" -ForegroundColor Red
        }
        
        $stream.Close()
        $tcpClient.Close()
        
    }
    catch {
        Write-Host "TCP Error: $($_.Exception.Message)" -ForegroundColor Red
        if ($tcpClient) {
            $tcpClient.Close()
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
                    if ($logLevel -eq "DEBUG") {
                        Write-Host "Hashrate: $foundValue KH/s" -ForegroundColor Green
                    }
                    break
                }
            }
        }
        
        if ($hashrate -eq 0 -and $logLevel -ne "ERROR") {
            Write-Host "No hashrate found for this worker" -ForegroundColor Yellow
        }
        
        return $hashrate
    }
    catch {
        Write-Host "Error extracting hashrate: $($_.Exception.Message)" -ForegroundColor Red
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
                if ($logLevel -eq "DEBUG") {
                    Write-Host "Found CPU temp: $cpuTemp°C" -ForegroundColor Gray
                }
            }
        }
        
        if ($cpuTemp -eq $null -and $workerData.stats -and $workerData.stats.temps) {
            if ($workerData.stats.temps -is [array] -and $workerData.stats.temps.Count -gt 0) {
                $cpuTemp = [int]$workerData.stats.temps[0]
                if ($logLevel -eq "DEBUG") {
                    Write-Host "Found CPU temp: $cpuTemp°C" -ForegroundColor Gray
                }
            }
        }
        
        return $cpuTemp
    }
    catch {
        Write-Host "Error extracting CPU temperature: $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

# =================================================================
# Main data collection and publishing function
# =================================================================
function Get-MiningDataAndPublish {
    Write-Host "=== Mining Data Collection Started ===" -ForegroundColor Cyan
    Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    
    try {
        $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        
        Publish-MQTTMessage -Topic "mining/heartbeat" -Message "alive"
        
        if ($logLevel -eq "DEBUG") {
            Write-Host "Fetching workers data from HiveOS..." -ForegroundColor Yellow
        }
        
        $response = Invoke-RestMethod -Uri $farmWorkersUrl -Headers $headers -Method Get -TimeoutSec 30
        
        if (-not $response -or -not $response.data) {
            Write-Host "No data received from API" -ForegroundColor Red
            return
        }
        
        Publish-MQTTMessage -Topic "mining/farm/$farmId/timestamp" -Message $timestamp
        
        $totalWorkers = $response.data.Count
        $onlineWorkers = ($response.data | Where-Object { $_.stats.online -eq $true }).Count
        $offlineWorkers = $totalWorkers - $onlineWorkers
        
        Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/count" -Message $totalWorkers
        Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/online" -Message $onlineWorkers
        Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/offline" -Message $offlineWorkers
        
        Write-Host "Farm Summary: $onlineWorkers/$totalWorkers workers online" -ForegroundColor Green
        
        $totalHashrate = 0
        $uptimeSum = 0
        $onlineCount = 0
        $cpuTempSum = 0
        $cpuTempCount = 0
        
        foreach ($worker in $response.data) {
            $workerId = $worker.id
            $workerName = $worker.name
            $isOnline = $worker.stats.online
            
            if ($logLevel -eq "DEBUG") {
                Write-Host "Processing: $workerName (ID: $workerId) - Online: $isOnline" -ForegroundColor White
            }
            
            Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/$workerId/name" -Message $workerName
            $onlineStatus = if ($isOnline) { "true" } else { "false" }
            Publish-MQTTMessage -Topic "mining/farm/$farmId/workers/$workerId/online" -Message $onlineStatus
            
            try {
                $workerApiUrl = "https://api2.hiveos.farm/api/v2/farms/$farmId/workers/$workerId"
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
                }
            }
            catch {
                Write-Host "Failed to get detailed info for $workerName`: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
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
        
        Write-Host "=== Data Collection Completed Successfully ===" -ForegroundColor Green
        Write-Host "Total Hashrate: $($totalHashrate.ToString('F3')) KH/s" -ForegroundColor Green
        Write-Host "Farm Efficiency: $efficiency%" -ForegroundColor Green
        if ($cpuTempCount -gt 0) {
            Write-Host "Average CPU Temperature: $($avgCpuTemp)°C" -ForegroundColor Green
        }
        
    }
    catch {
        Write-Host "Error in main data collection: $($_.Exception.Message)" -ForegroundColor Red
        Publish-MQTTMessage -Topic "mining/farm/$farmId/error" -Message $_.Exception.Message
    }
}

# =================================================================
# Main execution loop
# =================================================================
function Start-MiningMonitor {
    Write-Host "Starting Dockerized Hive Mining Monitor..." -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
    Write-Host ""
    
    Publish-MQTTMessage -Topic "mining/status" -Message "Dockerized mining monitor started"
    
    while ($true) {
        try {
            Get-MiningDataAndPublish
            Write-Host ""
            Write-Host "Waiting $runInterval seconds until next update..." -ForegroundColor Gray
            Start-Sleep -Seconds $runInterval
        }
        catch {
            Write-Host "Error in main loop: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Retrying in 30 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 30
        }
    }
}

# =================================================================
# Entry Point
# =================================================================
if ($args[0] -eq "-once") {
    Get-MiningDataAndPublish
} else {
    Start-MiningMonitor
}