# This is a script for automatically creating a silently deployable installer for Firefox ESR 
# - With file customizations
# - AppDeployToolkit support
# - Application creation in Configuration Manager 
#
# Jaakko Luoto
# jaakko.luoto@tut.fi
#
# Based on Make-FirefoxAppSource by:
# Henri Perämäki
# henri.w.peramaki@jyu.fi
# 9.5.2017
#
# All modifications in the modification.xml file will be automatically done to the installer source
# Example:
#	<?xml version="1.0" ?>
#	<modifications>
#		<replaceFile>
#			<source>Modifications\core\mozilla.cfg</source>
#			<target>core\mozilla.cfg</target>
#		</replaceFile>
#	</modifications>  
# 
# This will copy (and overwrite) a customized mozilla.cfg to the installer source files.
# All paths are relative, source being relative to the folder of this script and
# target to the installer source files root.

# Variables
$SetupURL = "https://download.mozilla.org/?product=firefox-esr-latest&os=win&lang=en-US"
$TempDir = "C:\Temp"
$7z = "C:\Program Files\7-Zip\7z.exe"
$SetupFileName = "$($TempDir)\firefox-latest-esr-setup.exe"
$ExtractDir = "$($TempDir)\Make-FF-Temp"
$TempSetupDir = "$($ExtractDir)\installer"
$DateStamp = Get-Date -Format "yyMMdd"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ModificationFile = "$($ScriptDir)\modifications.xml"
$OutputDirRoot = "$($TempDir)\Make-FF-Output"
$ContentDirRoot = "\\servershare\apps\Mozilla\Firefox"

# If using AppDeployToolkit, setting this to $true will:
# - Put setup files into subdirectory called Files
# - Set "Run installation and uninstall program as 32-bit process", needed for ServiceUI.exe compatibility
# - Increase SCCM installation maximum runtime to 120 minutes to allow AppDeployToolkit UI to stay on screen long enough
$EnableADT = $false

# SCCM related variables
# Sitecode
$CMSite = "CM1"
# Application folder in SCCM
$AppFolder = "$($CMSite):\Application\Mozilla\Firefox"
# Application name prefix
$AppName = "Mozilla Firefox ESR"
# Install and uninstall commands
$InstallCommand = 'setup.cmd'
$UninstallCommand = '"C:\Program Files (x86)\Mozilla Firefox\uninstall\helper.exe" -ms'
# Installation program visibility (One of Hidden, Maximized, Minimized, Normal)
$InstVisib = 'Normal'
# Max installation time in minutes
$MaxRunTime = 15
# Estimated installation time in minutes
$EstRunTime = 5

$TempSetupFilesDir = $TempSetupDir

if ($EnableADT) {
	$TempSetupFilesDir = "$($TempSetupDir)\Files"
	$MaxRunTime = 120
}

If (!(Test-Path $7z)) {
	Write-Host "7-Zip executable not found at $7z" -Foreground Red
	Exit
}

# Load the customizations xml file
$ModificationXML = [xml](Get-Content $ModificationFile)
if (!$ModificationXML) {
	Write-Host "Something went wrong. Could not read $ModificationFile." -Foreground Red
	Exit
}
$Modifications = $ModificationXML.modifications


# Download the latest Firefox ESR Setup
Write-Host "Downloading latest setup..."
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile($SetupURL, $SetupFileName)

# Check that download was successful
If (!(Test-Path $SetupFileName)) {
	Write-Host "Setup file not found in $SetupFileName" -Foreground Red
	Exit
}

Write-Host "Extracting files with 7-Zip to $TempSetupFilesDir..." 
Write-Host "Please ignore any lines about 'ERROR: Data Error'"
& $7z x -y -t* $SetupFileName -o"$ExtractDir" | Out-Null
& $7z x -y "$($ExtractDir)\[0]" -o"$TempSetupFilesDir" | Out-Null

# Check that extraction was successful
If (!(Test-Path "$($TempSetupFilesDir)\core\firefox.exe")) {
	Write-Host "Firefox executable not found in $($TempSetupFilesDir)\core" -Foreground Red
	Exit
}

Write-Host "Checking firefox.exe version info..."
$FirefoxExeInfo = (Get-ChildItem "$($TempSetupFilesDir)\core\firefox.exe").VersionInfo
$FirefoxFileVersion = New-Object System.Version -ArgumentList @($FirefoxExeInfo.FileMajorPart, $FirefoxExeInfo.FileMinorPart, $FirefoxExeInfo.FileBuildPart, $FirefoxExeInfo.FilePrivatePart)
$FirefoxProductVersion = $FirefoxExeInfo.ProductVersion

Write-Host "   FileVersion:    $FirefoxFileVersion"
Write-Host "   ProductVersion: $FirefoxProductVersion"

$AppNameWithVer = "$AppName $FirefoxProductVersion"

# Process modifications found in the modification.xml file
# This version supports following actions: 
# replaceFile - recursively copies customized files over installer files
# replaceString - replace string in installer files with support for magic string #Version# for inserting Firefox version
#
# Additional actions can be created by writing the functionality for them here.
Write-Host "Adding modifications to setup files..."
Foreach ($ReplaceFile in $Modifications.replaceFile) {
	$ReplaceSource = "$($ScriptDir)\$($ReplaceFile.Source)"
	$ReplaceTarget = "$($TempSetupDir)\$($ReplaceFile.Target)"
	Write-Host "   Copy '$ReplaceSource' -> '$ReplaceTarget'" -noNewLine
	Try {
		Copy-Item $ReplaceSource $ReplaceTarget -Force -Recurse
		Write-Host "  [OK]" -Foreground Green
	} Catch {
		Write-Host "  [FAILED]" -Foreground Red
	}
}
Foreach ($ReplaceString in $Modifications.replaceString) {
	$File = "$($TempSetupDir)\$($ReplaceString.File)"
	$Source = $ReplaceString.Source
	$Target = $ReplaceString.Target
	
	If ($Target -eq "#Version#") {
		# Magic string #Version# set as target -> replace string with Firefox version
		$Target = $FirefoxProductVersion
	}
	
	Write-Host "   Replace '$Source' with '$Target' in $File" -noNewLine
	Try {
		(Get-Content $File).replace($Source, $Target) | Set-Content $File
		Write-Host "  [OK]" -Foreground Green
	} Catch {
		Write-Host "  [FAILED]" -Foreground Red
	}
}	

$OutputDir = "$($OutputDirRoot)\Mozilla_Firefox_$($FirefoxProductVersion)esr_$DateStamp"

# Make sure that the output folder is unique
$i = 1
While (Test-Path $OutputDir) {
	$i = $i + 1
	$OutputDir = "$($OutputDirRoot)\Mozilla_Firefox_$($FirefoxProductVersion)esr_$($DateStamp)_$i"
}

Write-Host "Copying setup files to the output folder..."
Write-Host "   Source: $TempSetupDir"
Write-Host "   Target: $OutputDir"

Copy-Item $TempSetupDir $OutputDir -Recurse

Write-Host "Cleaning up $ExtractDir..."
Remove-Item $ExtractDir -Force -Recurse

# Move application source to contentdir

$ContentDir = "$ContentDirRoot\$AppNameWithVer"

# Make sure application title is unique
# Application is meant to be manually renamed (removing the Generated_xxxxxx string) before creating a deployment
$AppTitle = "$AppNameWithVer Generated_$DateStamp"
If ($i -gt 1) {
	$AppTitle = "$AppTitle`_$i"
}

Write-Host
Write-Host "Confirmation for next steps..." -Foreground Yellow
Write-Host "   - Setup files will be copied to content dir:" -Foreground Yellow
Write-Host "       Source: '$OutputDir'" -Foreground Yellow
Write-Host "       Target: '$ContentDir'" -Foreground Yellow
Write-Host "   - Application object will be created in Configuration Manager:" -Foreground Yellow
Write-Host "       Name: '$AppTitle'" -Foreground Yellow
Write-Host "   - Make sure you have modify permissions in target directory and SCCM" -Foreground Yellow
Pause

Write-Host
Write-Host "Copying files..."

If (Test-Path "FileSystem::$ContentDir") {
    Write-Host "Warning: Skipping copy operation because '$ContentDir' already exists." -Foreground Yellow
} Else {
    Copy-Item $OutputDir "FileSystem::$ContentDir" -Recurse
}

# Connect to SCCM

Write-Host "Connecting to Configuration Manager..."

$CMModule = Join-Path $(Split-Path $env:SMS_ADMIN_UI_PATH) ConfigurationManager.psd1
If (!(Test-Path $CMModule)) {
	Write-Host "Configuration Manager PowerShell module not found at '$CMModule'. Install Configuration Manager Console." -Foreground Red
	Exit
}

# Import SCCM module
Import-Module $CMModule

# Change working directory to the application folder in SCCM
$OriginalLocation = Get-Location
Try {
	Set-Location $AppFolder -ErrorAction Stop
} Catch {
	Write-Host "Error connecting to Configuration Manager site $CMSite and accessing folder $AppFolder" -Foreground Red
	Exit
}

Write-Host "Creating Application '$AppTitle'..."

# Create Application object
Try {
	$App = New-CMApplication -Name $AppTitle -LocalizedApplicationName $AppNameWithVer -AutoInstall $true -SoftwareVersion $FirefoxProductVersion
} Catch {
	Write-Host "Creation of Application failed: $_" -Foreground Red
	Exit
}

# Move Application object to SCCM internal folder
Try {
	Move-CMObject -FolderPath "$AppFolder" -InputObject $App
} Catch {
	Write-Host "Moving Application to folder failed: $_" -Foreground Yellow
}

# Detection script accepts 32-bit and 64-bit Firefox
$DetectionScript = "If (Test-Path 'C:\Program Files (x86)\Mozilla Firefox\firefox.exe') {`$version = (Get-ChildItem 'C:\Program Files (x86)\Mozilla Firefox\firefox.exe').VersionInfo.ProductVersion}`nIf (Test-Path 'C:\Program Files\Mozilla Firefox\firefox.exe') {`$version = (Get-ChildItem 'C:\Program Files\Mozilla Firefox\firefox.exe').VersionInfo.ProductVersion}`nIf (`$version -eq [System.Version]'$FirefoxProductVersion') {Write-Host 'Installed'}`nexit 0"

Write-Host "Creating Deployment Type..."

# Create Deployment Type
Try {
	# Parameter "Force32Bit" is required for our AppDeployToolkit+ServiceUI.exe setup.
	# Set it conditionally with splat array
	$Force32bit = @{'Force32bit'=$EnableADT}

	$DepType = Add-CMScriptDeploymentType -ApplicationName $AppTitle -DeploymentTypeName $AppNameWithVer -ContentLocation "$ContentDirRoot\$AppNameWithVer\" -InstallCommand $InstallCommand -UninstallCommand $UninstallCommand -ScriptLanguage Powershell -Scripttext $DetectionScript -LogonRequirementType WhereOrNotUserLoggedOn -UserInteractionMode $InstVisib -MaximumRunTimeMinutes $MaxRunTime -EstimatedRuntimeMins $EstRunTime -InstallationBehaviorType InstallForSystem @Force32bit
} Catch {
	Write-Host "Creation of Deployment Type failed: $_" -Foreground Red
	Exit
}

Set-Location $OriginalLocation

Write-Host "Done."
Write-Host
Write-Host "Note: Remember manual steps:" -Foreground Yellow
Write-Host "- If you are happy with the result, rename application and remove Generated_yymmdd string." -Foreground Yellow
Write-Host "- Add supersedence of previous version in SCCM. Uninstall-checkbox can be left empty." -Foreground Yellow
Write-Host "- Make a test deployment before deploying to production." -Foreground Yellow
