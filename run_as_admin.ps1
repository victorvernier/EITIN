# Defines the current user's Desktop directory and the output file name.
# Retrieves the desktop path and concatenates it with the computer name and the suffix "_Inventory.txt".
$output_dir = [System.Environment]::GetFolderPath("Desktop")
$filename = "$output_dir\$env:COMPUTERNAME`_Inventory.txt"

# Deletes the previous file, if it exists.
# This ensures that the report is not appended to old data, generating a clean inventory.
if (Test-Path $filename) { 
    Remove-Item $filename 
}

# Report header.
# Adds separation lines, title with date/time, and a blank line for better formatting.
Add-Content -Path $filename -Value "==============================="
Add-Content -Path $filename -Value "IT INVENTORY - $(Get-Date)"
Add-Content -Path $filename -Value "==============================="
Add-Content -Path $filename -Value ""

# [IDENTIFICATION]
# Starts the identification section, displaying the computer name and listing active users.
Add-Content -Path $filename -Value "[IDENTIFICATION]"
Add-Content -Path $filename -Value "Computer Name: $env:COMPUTERNAME"
Add-Content -Path $filename -Value "Created Users:"

# Gets the active local users (not disabled) and ignores unwanted default accounts.
$users = Get-WmiObject Win32_UserAccount | Where-Object { 
    $_.LocalAccount -eq $true -and $_.Disabled -eq $false -and $_.Name -notmatch '^(Administrator|DefaultAccount|Guest|WDAGUtilityAccount)$'
}
# For each filtered user, writes the name to the file.
$users | ForEach-Object { 
    Add-Content -Path $filename -Value $_.Name 
}
Add-Content -Path $filename -Value ""

# [OPERATING SYSTEM]
# Collects operating system information through CIM (the currently recommended approach).
Add-Content -Path $filename -Value "[OPERATING SYSTEM]"
$os = Get-CimInstance Win32_OperatingSystem
Add-Content -Path $filename -Value "System: $($os.Caption)"
Add-Content -Path $filename -Value "Version: $($os.Version)"
Add-Content -Path $filename -Value "Architecture: $($os.OSArchitecture)"
Add-Content -Path $filename -Value ""

# [WINDOWS SPECIFICATIONS] - section where additional dates are displayed

Add-Content -Path $filename -Value "[WINDOWS SPECIFICATIONS]"
$winSpec = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion"
Add-Content -Path $filename -Value "Product: $($winSpec.ProductName)"
Add-Content -Path $filename -Value "Edition: $($winSpec.EditionID)"
Add-Content -Path $filename -Value "Version: $($winSpec.CurrentVersion) (Build $($winSpec.CurrentBuild))"

# Installation date handling
if ($os.InstallDate -and $os.InstallDate -match '^\d{14}\.\d{6}[\+\-]\d{3}$') {
    try {
        $installDate = [Management.ManagementDateTimeConverter]::ToDateTime($os.InstallDate)
        Add-Content -Path $filename -Value "Installation Date: $installDate"
    } catch {
        Add-Content -Path $filename -Value "Installation Date: Conversion Error"
    }
} else {
    Add-Content -Path $filename -Value "Installation Date: Not Available"
}

# Last boot handling
if ($os.LastBootUpTime -and $os.LastBootUpTime -match '^\d{14}\.\d{6}[\+\-]\d{3}$') {
    try {
        $lastBoot = [Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime)
        Add-Content -Path $filename -Value "Last Boot: $lastBoot"
    } catch {
        Add-Content -Path $filename -Value "Last Boot: Conversion Error"
    }
} else {
    Add-Content -Path $filename -Value "Last Boot: Not Available"
}

Add-Content -Path $filename -Value ""


# [EQUIPMENT TYPE]
# Determines if the equipment is Desktop or Notebook based on the PCSystemType property.
Add-Content -Path $filename -Value "[EQUIPMENT TYPE]"
$equipmentType = (Get-CimInstance Win32_ComputerSystem).PCSystemType
if ($equipmentType -eq 1) {
    Add-Content -Path $filename -Value "Type: Desktop"
} else {
    Add-Content -Path $filename -Value "Type: Notebook"
}
Add-Content -Path $filename -Value ""

# [PROCESSOR]
# Collects information about the processor: model, cores, and maximum speed.
Add-Content -Path $filename -Value "[PROCESSOR]"
$processor = Get-CimInstance Win32_Processor
Add-Content -Path $filename -Value "Model: $($processor.Name)"
Add-Content -Path $filename -Value "Cores: $($processor.NumberOfCores)"
Add-Content -Path $filename -Value "Max Speed: $($processor.MaxClockSpeed) MHz"
Add-Content -Path $filename -Value ""

# [RAM MEMORY]
# Collects information from each physical memory module installed.
Add-Content -Path $filename -Value "[RAM MEMORY]"
$memory = Get-CimInstance Win32_PhysicalMemory
$memory | ForEach-Object {
    # Converts the numeric memory type code to a readable string (DDR, DDR2, etc.).
    $ddr = switch ($_.SMBIOSMemoryType) {
        20 { 'DDR' }
        21 { 'DDR2' }
        22 { 'DDR2 FB-DIMM' }
        24 { 'DDR3' }
        26 { 'DDR4' }
        34 { 'DDR5' }
        default { 'Unknown' }
    }
    Add-Content -Path $filename -Value "Manufacturer: $($_.Manufacturer)"
    Add-Content -Path $filename -Value "Capacity: $([math]::round($_.Capacity / 1GB, 2)) GB"
    Add-Content -Path $filename -Value "Speed: $($_.Speed) MHz"
    Add-Content -Path $filename -Value "Type: $ddr"
    Add-Content -Path $filename -Value ""
}

# [STORAGE] - Information on physical disks (SSD, HDD, or USB Drive).
Add-Content -Path $filename -Value "[STORAGE]"
$disks = Get-PhysicalDisk
foreach ($disk in $disks) {
    # Determines the media type based on the MediaType value.
    $media = switch ($disk.MediaType) {
        3 { "HDD" }
        4 { "SSD" }
        default {
            if ($disk.Model -match "USB" -or $disk.FriendlyName -match "USB" -or $disk.DeviceID -match "USB" -or $disk.Model -match "Cruzer|Flash|Thumb|Stick|Pen|Drive") {
                "USB Drive"
            } elseif ($disk.Model -match "SSD" -or $disk.FriendlyName -match "SSD") {
                "SSD"
            } elseif ($disk.Model -match "HDD" -or $disk.FriendlyName -match "HDD") {
                "HDD"
            } else {
                "Unknown"
            }
        }
    }
    Add-Content -Path $filename -Value "Drive: $($disk.FriendlyName)"
    Add-Content -Path $filename -Value "Type: $media"
    # Displays the serial number if available.
    if ($disk.SerialNumber) {
        Add-Content -Path $filename -Value "Serial: $($disk.SerialNumber)"
    }
    Add-Content -Path $filename -Value ""
}
# Disk space report by volume.
Add-Content -Path $filename -Value 'Space by Drive (Volumes):'
$volumes = Get-Volume | Where-Object { $_.FileSystem -ne $null }
foreach ($volume in $volumes) {
    $total = [math]::round($volume.Size / 1GB, 2)
    $used = [math]::round(($volume.Size - $volume.SizeRemaining) / 1GB, 2)
    $available = [math]::round($volume.SizeRemaining / 1GB, 2)
    # Formats the message with drive, total, used, and available.
    $message = "Drive {0}: Total: {1} GB `| Used: {2} GB `| Available: {3} GB" -f $volume.DriveLetter, $total, $used, $available
    Add-Content -Path $filename -Value $message
}
Add-Content -Path $filename -Value ""

# [NETWORK] – Network information.
Add-Content -Path $filename -Value "[NETWORK]"

# Gets all active network adapters
$netAdapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }

# Filters wireless adapters (Wi-Fi)
$wifiAdapters = $netAdapters | Where-Object { 
    $_.Name -match 'Wireless|Wi[-]?Fi' -or $_.InterfaceDescription -match 'Wireless|Wi[-]?Fi'
}

# Filters Ethernet adapters
$ethernetAdapters = $netAdapters | Where-Object { 
    $_.Name -match 'Ethernet' -or $_.InterfaceDescription -match 'Ethernet'
}

# Displays active Wi-Fi adapters
if ($wifiAdapters) {
    foreach ($wifi in $wifiAdapters) {
        Add-Content -Path $filename -Value "Wi‑Fi - Adapter: $($wifi.Name) | Physical Address (MAC): $($wifi.MacAddress)"
    }
} else {
    Add-Content -Path $filename -Value "No active Wi‑Fi interfaces found."
}

# Displays active Ethernet adapters
if ($ethernetAdapters) {
    foreach ($eth in $ethernetAdapters) {
        Add-Content -Path $filename -Value "Ethernet - Adapter: $($eth.Name) | Physical Address (MAC): $($eth.MacAddress)"
    }
} else {
    Add-Content -Path $filename -Value "No active Ethernet interfaces found."
}

# Adds a listing of all active network adapters (regardless of type)
if ($netAdapters) {
    Add-Content -Path $filename -Value "[ALL ACTIVE NETWORK ADAPTERS]"
    foreach ($adapter in $netAdapters) {
        Add-Content -Path $filename -Value "Adapter: $($adapter.Name) | Physical Address (MAC): $($adapter.MacAddress) | Description: $($adapter.InterfaceDescription)"
    }
} else {
    Add-Content -Path $filename -Value "No active network adapters found."
}

# Selects the first valid IPv4 address, ignoring link-local addresses (169.254.x.x)
$mainIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch "^169\.254\." } | Select-Object -First 1).IPAddress
if ($mainIP) {
    Add-Content -Path $filename -Value "Main IP: $mainIP"
}
Add-Content -Path $filename -Value ""

# [INSTALLED SOFTWARES] – List of installed applications (excluding Microsoft ones).
Add-Content -Path $filename -Value "[INSTALLED SOFTWARES]"
$apps1 = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | 
    Where-Object { $_.DisplayName -and $_.DisplayName -notmatch "Microsoft" }
$apps2 = Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | 
    Where-Object { $_.DisplayName -and $_.DisplayName -notmatch "Microsoft" }
# Merges the two lists (64-bit and 32-bit applications).
$softwares = $apps1 + $apps2
$softwares | ForEach-Object {
    Add-Content -Path $filename -Value "$($_.DisplayName) - Version: $($_.DisplayVersion)"
}
Add-Content -Path $filename -Value ""

# [MAC] – Product information (Model, Manufacturer, and for Dell, displays the Service Tag).
Add-Content -Path $filename -Value "[MAC]"
$mec = Get-CimInstance -ClassName Win32_ComputerSystemProduct
Add-Content -Path $filename -Value "Model: $($mec.Name)"
Add-Content -Path $filename -Value "Manufacturer: $($mec.Vendor)"
if ($mec.Vendor -match "Dell") {
    # For Dell systems, retrieves the BIOS Serial which represents the Service Tag.
    $dellSerial = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
    Add-Content -Path $filename -Value "Dell Service Tag: $dellSerial"
} else {
    Add-Content -Path $filename -Value "Identification Number: $($mec.IdentifyingNumber)"
}

# Adds new options: Device ID and Product ID.
Add-Content -Path $filename -Value "Device ID: $($mec.UUID)"
$productID = (Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion').ProductID
Add-Content -Path $filename -Value "Product ID: $productID"
Add-Content -Path $filename -Value ""

# [BIOS & FIRMWARE] – BIOS details and chassis information.
Add-Content -Path $filename -Value "[BIOS & FIRMWARE]"
$bios = Get-CimInstance -ClassName Win32_BIOS
# Joins BIOS versions (if more than one) separated by commas.
Add-Content -Path $filename -Value "BIOS - Version: $($bios.BIOSVersion -join ', ')"
# Checks if the BIOS date is in a specific format; if so, converts it to a readable date.
if ($bios.ReleaseDate -and $bios.ReleaseDate -match '^\d{14}\.\d{6}[\+\-]\d{3}$') {
    $biosDate = [Management.ManagementDateTimeConverter]::ToDateTime($bios.ReleaseDate)
    Add-Content -Path $filename -Value "BIOS - Release Date: $biosDate"
} else {
    Add-Content -Path $filename -Value "BIOS - Release Date: Not Available"
}
# Retrieves system enclosure (chassis) information.
$enclosure = Get-CimInstance -ClassName Win32_SystemEnclosure
if ($enclosure.ChassisTypes) {
    # Displays the first listed chassis type.
    Add-Content -Path $filename -Value "Chassis Type: $($enclosure.ChassisTypes[0])"
}
Add-Content -Path $filename -Value ""

# [MONITORS] – Information about connected monitors via WMI (WmiMonitorID class).
Add-Content -Path $filename -Value "[MONITORS]"
$monitors = Get-WmiObject -Namespace root\wmi -Class WmiMonitorID
if ($monitors) {
    foreach ($monitor in $monitors) {
        # Local function to decode byte arrays into strings (e.g., manufacturer name, model, serial).
        function Decode-Array($array) {
            if ($array -and ($array -is [array])) {
                return ([System.Text.Encoding]::ASCII.GetString($array)).Trim([char]0)
            } else { 
                return "Not Found" 
            }
        }
        $mManufacturer = Decode-Array $monitor.ManufacturerName
        $mName = Decode-Array $monitor.UserFriendlyName
        $mSerial = Decode-Array $monitor.SerialNumberID
        Add-Content -Path $filename -Value "Monitor: $mName"
        Add-Content -Path $filename -Value "  Manufacturer: $mManufacturer"
        Add-Content -Path $filename -Value "  Serial: $mSerial"
        Add-Content -Path $filename -Value ""
    }
} else {
    Add-Content -Path $filename -Value "No monitors found via WmiMonitorID."
}
Add-Content -Path $filename -Value ""

# [WINDOWS UPDATES] – Last 10 installed updates.
Add-Content -Path $filename -Value "[WINDOWS UPDATES]"

try {
    # Creates the session and update searcher object
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    
    # Gets the total count of installed updates
    $historyCount = $updateSearcher.GetTotalHistoryCount()
    
    # Sets the desired amount (10 or fewer, if there are less updates)
    $numUpdates = [Math]::Min(10, $historyCount)
    
    # Retrieves the update history (from index 0 to $numUpdates)
    $updates = $updateSearcher.QueryHistory(0, $numUpdates) | Sort-Object -Property Date -Descending
    
    foreach ($update in $updates) {
        $title = $update.Title
        # Classifies the update based on keywords in the title.
        if ($title -match 'Quality|Cumulative') {
            $category = "Quality Update"
        } elseif ($title -match 'Driver') {
            $category = "Driver Update"
        } elseif ($title -match 'Definition|Antivirus') {
            $category = "Definition Update"
        } else {
            $category = "Other Updates"
        }
        # Formats the date and adds the information to the file.
        $updateDate = $update.Date.ToString("dd/MM/yyyy HH:mm")
        Add-Content -Path $filename -Value "$updateDate - [$category] $title"
    }
} catch {
    Add-Content -Path $filename -Value "Unable to retrieve Windows update history."
}
Add-Content -Path $filename -Value ""

# [ACTIVE DIRECTORY] – Collects Active Directory information if the module is available.
Add-Content -Path $filename -Value "[ACTIVE DIRECTORY]"
if (Get-Command -Name Get-ADComputer -ErrorAction SilentlyContinue) {
    Import-Module ActiveDirectory
    $adComputer = Get-ADComputer $env:COMPUTERNAME -Properties DistinguishedName
    Add-Content -Path $filename -Value "DistinguishedName: $($adComputer.DistinguishedName)"
} else {
    Add-Content -Path $filename -Value "ActiveDirectory module not found. Skipping AD collection."
}
Add-Content -Path $filename -Value ""

# Final message displayed on the console.
Write-Host "Report generated at: $filename"
