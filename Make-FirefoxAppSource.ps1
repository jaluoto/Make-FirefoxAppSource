#
# This is a script for automatically creating a silently deployable installer with customizations
# for Firefox ESR
#
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
# All paths are relative, source being relative to the folder this script is being run and
# target to the installer source files root.
#

# Function to get child processes for a parent process
Function Find-ChildProcess {
	param($ID=$PID)
	Get-WmiObject -Class Win32_Process -Filter "ParentProcessID=$ID"
}

# Some variables
$SetupURL = "https://download.mozilla.org/?product=firefox-esr-latest&os=win&lang=en-US"
$TempFolder = $env:temp
$SetupFileName = "$TempFolder" + "\firefox-latest-esr-setup.exe"
$DateStamp = Get-Date -Format "yyMMdd"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ModificationFile = "$($ScriptDir)\modifications.xml"
$OutputFolderRoot = "$($ScriptDir)\Output"

# Loading the customizations xml file
$ModificationXML = [xml](Get-Content $ModificationFile)
if (!$ModificationXML) {
	Write-Host "Something went wrong. Could not read $ModificationFile."
	Exit
}
$Modifications = $ModificationXML.modifications


# Downloading the latest Firefox ESR Setup
Write-Host "Downloading latest setup..."
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile($SetupURL, $SetupFileName)

# Check that it was really downloaded
If (!(Test-Path $SetupFileName)) {
	Write-Host "Setup file not found at $SetupFileName"
	Exit
}


# The Firefox ESR Setup is basicly a self-extracting 7z archive. We'll launch it and wait for it to be extracted.
# Then we can simply copy the actual installer source from the folder where setup.exe is being run.

# Launching the downloaded exe
Write-Host "Starting the setup..." 
$7zProcess = Start-Process $SetupFileName -PassThru -WindowStyle Hidden
Write-Host "Waiting for the setup to extract files..."
While (!$SetupProcess) {
	$Temp = Find-ChildProcess -ID $7zProcess.ID
	If ($Temp.ExecutablePath) {
		$SetupProcess = $Temp
	}
}

# Sleep for 1 second, just to be sure.
Start-Sleep 1

Write-Host "Child process for Setup.exe found."
$ExtractedSetupDir = Split-Path -Parent $SetupProcess.ExecutablePath

Write-Host "Checking version info..."
$FirefoxExeInfo = (Get-ChildItem "$($ExtractedSetupDir)\core\firefox.exe").VersionInfo
$FirefoxFileVersion = New-Object System.Version -ArgumentList @($FirefoxExeInfo.FileMajorPart, $FirefoxExeInfo.FileMinorPart, $FirefoxExeInfo.FileBuildPart, $FirefoxExeInfo.FilePrivatePart)
$FirefoxProductVersion = $FirefoxExeInfo.ProductVersion

Write-Host "   FileVersion:    $FirefoxFileVersion"
Write-Host "   ProductVersion: $FirefoxProductVersion"


$TempSetupDir = "$($ExtractedSetupDir)_autopackage"

Write-Host "Copying setup files to a temporary location:"
Write-Host "   Source: $ExtractedSetupDir"
Write-Host "   Target: $TempSetupDir"

Try {
	Copy-Item $ExtractedSetupDir $TempSetupDir -Recurse
} catch {
	Write-Host "Copy failed!"
	Exit
}

Write-Host "Copying done."

Write-Host "Killing processes."
Kill -ID $SetupProcess.ProcessID
Kill $7zProcess
Write-Host "   Done"

# Processing modifications found in the modification.xml file
# This version only supports a action called 'replaceFile', which replaces a original file in the installer source with a customized file
# Additional actions can be created by writing the functionality for them here
Write-Host "Adding modifications to setup files..."
Foreach ($ReplaceFile in $Modifications.replaceFile) {
	$ReplaceSource = "$($ScriptDir)\$($ReplaceFile.Source)"
	$ReplaceTarget = "$($TempSetupDir)\$($ReplaceFile.Target)"
	Write-Host "   $ReplaceSource -> $ReplaceTarget" -noNewLine
	Try {
		Copy-Item $ReplaceSource $ReplaceTarget -Force
		Write-Host "  [OK]" -Foreground Green
	} catch {
		Write-Host "  [COPY FAILED]" -Foreground Red
	}
}

$OutputFolder = "$($OutputFolderRoot)\Mozilla_Firefox_$($FirefoxProductVersion)esr_$DateStamp"

# Making sure that the output folder is unique
$i = 1
While (Test-Path $OutputFolder) {
	$i = $i + 1
	$OutputFolder = "$($OutputFolderRoot)\Mozilla_Firefox_$($FirefoxProductVersion)esr_$($DateStamp)_$i"
}

Write-Host "Copying setup files to the output folder..."
Write-Host "   Source: $TempSetupDir"
Write-Host "   Target: $OutputFolder"

Copy-Item $TempSetupDir $OutputFolder -Recurse

Write-Host "Cleaning up..."
Remove-Item $ExtractedSetupDir -Force -Recurse
Remove-Item $TempSetupDir -Force -Recurse
