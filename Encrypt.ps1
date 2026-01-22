#Requires -Version 5.1
<#
.SYNOPSIS
    Encrypts files for secure CUI email transmission per NIST SP 800-171.

.DESCRIPTION
    Encrypts files using FIPS 140-2 compliant AES-256-CBC with PBKDF2 key derivation.
    Outputs .Locked files, README.md with decryption instructions, and optionally
    a .msg email file with proper CUI markings per 32 CFR Part 2002.

    Compliance:
    - FIPS 140-2: AES-256-CBC encryption
    - NIST SP 800-132: PBKDF2-HMAC-SHA256 key derivation (100,000 iterations)
    - NIST SP 800-171: CUI handling requirements
    - 32 CFR Part 2002: CUI marking requirements

    Cross-Platform:
    - Works on Windows PowerShell 5.1+ and PowerShell Core 7+ (macOS/Linux)
    - Outlook .msg generation only available on Windows with Outlook installed

.PARAMETER Path
    Files or folders to encrypt. Accepts multiple paths.

.EXAMPLE
    .\Encrypt.ps1 "Document.pdf"
    .\Encrypt.ps1 "C:\Folder\To\Encrypt"
    .\Encrypt.ps1 "File1.pdf" "File2.docx" "File3.xlsx"
#>

param(
    [Parameter(Mandatory=$true, Position=0, ValueFromRemainingArguments=$true)]
    [string[]]$Path
)

# ============================================================================
# ORGANIZATION CONFIGURATION - Customize these for your organization
# ============================================================================
# These settings can be modified when forking for your organization.
# All other code should remain unchanged for compliance verification.

$ORG_NAME = ""                    # Your organization name (leave empty for generic)
                                  # Example: "ACME Corporation"

$ORG_SUPPORT_CONTACT = ""         # Support contact for recipients having trouble
                                  # Example: "IT Security: security@acme.com or x1234"

$ORG_HANDLING_INSTRUCTIONS = ""   # Additional handling instructions (appended to emails)
                                  # Example: "Per ACME Policy 12.3, retain for 7 years."

$MIN_PASSWORD_LENGTH = 8          # Minimum password length (8 is NIST minimum)
                                  # Increase if your organization requires longer

$DEFAULT_CUI_CATEGORY = 0         # Default CUI category when user presses Enter
                                  # 0 = Basic CUI, 1 = CTI, 2 = EXPT, 3 = PRVCY, 4 = PROPIN

# ============================================================================
# CRYPTOGRAPHIC CONFIGURATION - Do not modify (FIPS 140-2 / NIST SP 800-132)
# ============================================================================
$ITERATIONS = 100000  # PBKDF2 iterations (NIST SP 800-132 recommends minimum 10,000)
$SALT_SIZE = 16       # bytes (128 bits)
$KEY_SIZE = 32        # bytes (256 bits for AES-256)
$IV_SIZE = 16         # bytes (128 bits for AES block size)

# ============================================================================
# DECRYPTION ONE-LINER - Single source of truth for README.md and Password_Email
# ============================================================================
# This PowerShell one-liner is included in both the README and Password_Email.
# Uses file picker dialogs for ease of use. DO NOT MODIFY unless you understand
# the cryptographic operations (must match Encrypt-File function).
$DECRYPTION_ONELINER = 'Add-Type -AssemblyName System.Windows.Forms;$o=New-Object System.Windows.Forms.OpenFileDialog;$o.Title="Select .Locked file to decrypt";$o.Filter="Locked files (*.Locked)|*.Locked|All files (*.*)|*.*";if($o.ShowDialog()-eq''OK''){$f=$o.FileName;$p=Read-Host "Password" -AsSecureString;$b=[IO.File]::ReadAllBytes($f);$k=[Security.Cryptography.Rfc2898DeriveBytes]::new([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p)),$b[0..15],100000,"SHA256");$a=[Security.Cryptography.Aes]::Create();$a.Key=$k.GetBytes(32);$a.IV=$b[16..31];$c=$a.CreateDecryptor().TransformFinalBlock($b,32,$b.Length-32);$s=New-Object System.Windows.Forms.SaveFileDialog;$s.Title="Save decrypted file as";$s.FileName=[IO.Path]::GetFileName(($f-replace''\.Locked$'',''''));$s.InitialDirectory=[IO.Path]::GetDirectoryName($f);if($s.ShowDialog()-eq''OK''){[IO.File]::WriteAllBytes($s.FileName,$c);Write-Host "Decrypted: $($s.FileName)" -ForegroundColor Green}}'

# Platform detection
$IsWindowsPlatform = $PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows

# FIPS mode detection (Windows only)
function Test-FIPSMode {
    if (-not $IsWindowsPlatform) {
        # FIPS mode check only applies to Windows
        return @{
            Enabled = $false
            Applicable = $false
            Message = "FIPS mode check not applicable (non-Windows platform)"
        }
    }

    try {
        $fipsKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FIPSAlgorithmPolicy"
        $fipsValue = Get-ItemProperty -Path $fipsKey -Name "Enabled" -ErrorAction Stop
        $enabled = $fipsValue.Enabled -eq 1

        return @{
            Enabled = $enabled
            Applicable = $true
            Message = if ($enabled) {
                "Windows FIPS mode: ENABLED (CMVP #4515 validated)"
            } else {
                "Windows FIPS mode: DISABLED"
            }
        }
    }
    catch {
        # Registry key doesn't exist or can't be read
        return @{
            Enabled = $false
            Applicable = $true
            Message = "Windows FIPS mode: DISABLED (policy not configured)"
        }
    }
}

# Cross-platform SecureString to plain text conversion
function ConvertFrom-SecureStringPlain {
    param([System.Security.SecureString]$SecureString)

    if ($IsWindowsPlatform) {
        # Windows: Use Marshal methods
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        try {
            return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
    else {
        # macOS/Linux: Use NetworkCredential trick
        return [System.Net.NetworkCredential]::new('', $SecureString).Password
    }
}

# CUI Categories per 32 CFR Part 2002
# CUI subcategories (can be combined per 32 CFR Part 2002)
$CUI_SUBCATEGORIES = @{
    "1" = @{ Code = "SP-CTI"; Full = "Controlled Technical Information" }
    "2" = @{ Code = "SP-EXPT"; Full = "Export Controlled" }
    "3" = @{ Code = "SP-PRVCY"; Full = "Privacy" }
    "4" = @{ Code = "SP-PROPIN"; Full = "Proprietary Business Information" }
}

function Write-Banner {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  SendCUIEmail - CUI File Encryption Tool" -ForegroundColor Cyan
    Write-Host "  FIPS 140-2 / NIST SP 800-171 Compliant" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""

    # Check and display FIPS mode status
    $fipsStatus = Test-FIPSMode
    if ($fipsStatus.Applicable) {
        if ($fipsStatus.Enabled) {
            Write-Host $fipsStatus.Message -ForegroundColor Green
        }
        else {
            Write-Host "WARNING: $($fipsStatus.Message)" -ForegroundColor Yellow
            Write-Host "  For full NIST SP 800-171 section 3.13.11 compliance, enable FIPS mode:" -ForegroundColor Yellow
            Write-Host "  secpol.msc -> Local Policies -> Security Options ->" -ForegroundColor Gray
            Write-Host "  'System cryptography: Use FIPS compliant algorithms...'" -ForegroundColor Gray
            Write-Host ""
        }
    }
}

function Get-CUICategory {
    Write-Host "Select CUI Subcategories (can select multiple per 32 CFR Part 2002):" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [0] CUI (basic - no subcategory)" -ForegroundColor White
    foreach ($key in ($CUI_SUBCATEGORIES.Keys | Sort-Object)) {
        Write-Host "  [$key] $($CUI_SUBCATEGORIES[$key].Code) - $($CUI_SUBCATEGORIES[$key].Full)" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "Enter selection(s) separated by commas (e.g., '1,2' for CTI+EXPT)" -ForegroundColor Gray
    Write-Host "Or press Enter for basic CUI" -ForegroundColor Gray
    Write-Host ""

    $selection = Read-Host "Selection"

    # Default to basic CUI if empty or 0
    if ([string]::IsNullOrWhiteSpace($selection) -or $selection -eq "0") {
        return @{
            Short = "CUI"
            Full = "CONTROLLED UNCLASSIFIED INFORMATION (CUI)"
        }
    }

    # Parse comma-separated selections
    $selections = $selection -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $CUI_SUBCATEGORIES.ContainsKey($_) } | Sort-Object -Unique

    if ($selections.Count -eq 0) {
        Write-Host "Invalid selection, defaulting to basic CUI" -ForegroundColor Yellow
        return @{
            Short = "CUI"
            Full = "CONTROLLED UNCLASSIFIED INFORMATION (CUI)"
        }
    }

    # Build the combined marking (e.g., CUI//SP-CTI//SP-EXPT)
    $codes = $selections | ForEach-Object { $CUI_SUBCATEGORIES[$_].Code }
    $shortMarking = "CUI//" + ($codes -join "//")

    $fullNames = $selections | ForEach-Object { $CUI_SUBCATEGORIES[$_].Full }
    $fullMarking = "$shortMarking (" + ($fullNames -join ", ") + ")"

    return @{
        Short = $shortMarking
        Full = $fullMarking
    }
}

# Word list for passphrase generation (EFF-style short words, easy to communicate)
$PASSPHRASE_WORDS = @(
    "apple", "beach", "brave", "bring", "chair", "chief", "class", "cloud",
    "dance", "draft", "dream", "drink", "earth", "elder", "empty", "equal",
    "faint", "faith", "feast", "field", "flame", "flash", "float", "floor",
    "fruit", "giant", "glass", "globe", "grace", "grain", "grape", "grass",
    "green", "grove", "guide", "happy", "heart", "heavy", "horse", "house",
    "human", "image", "inner", "juice", "knife", "lemon", "level", "light",
    "liver", "lodge", "lunar", "magic", "maple", "march", "medal", "metal",
    "model", "money", "month", "motor", "mouse", "music", "noble", "north",
    "novel", "ocean", "olive", "onion", "orbit", "other", "outer", "paint",
    "panel", "paper", "peace", "pearl", "phone", "piano", "pilot", "pixel",
    "plain", "plant", "plate", "plaza", "plum", "point", "polar", "power",
    "pride", "prime", "print", "prize", "proof", "proud", "queen", "quick",
    "quiet", "radio", "rapid", "raven", "reach", "realm", "rider", "river",
    "robin", "robot", "rocky", "round", "royal", "salad", "scale", "scene",
    "scout", "seven", "shade", "shape", "sharp", "sheep", "shell", "shift",
    "shine", "shore", "shown", "sight", "silky", "silver", "simple", "skill"
)

function New-Passphrase {
    param([int]$WordCount = 4)

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $words = @()

    for ($i = 0; $i -lt $WordCount; $i++) {
        $bytes = New-Object byte[] 4
        $rng.GetBytes($bytes)
        $index = [Math]::Abs([BitConverter]::ToInt32($bytes, 0)) % $PASSPHRASE_WORDS.Count
        $words += $PASSPHRASE_WORDS[$index]
    }

    $rng.Dispose()
    return ($words -join "-")
}

function Get-SecurePassword {
    param([int]$MaxAttempts = 3)

    Write-Host "Password Options:" -ForegroundColor Yellow
    Write-Host "  - Enter your own password (minimum $MIN_PASSWORD_LENGTH characters)" -ForegroundColor Gray
    Write-Host "  - Press Enter for auto-generated passphrase (recommended)" -ForegroundColor Gray
    Write-Host "  - Will be transmitted out-of-band (phone, SMS, in-person)" -ForegroundColor Gray
    Write-Host ""

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        if ($attempt -gt 1) {
            Write-Host ""
            Write-Host "Attempt $attempt of $MaxAttempts" -ForegroundColor Yellow
        }

        Write-Host "(Characters will not appear as you type, or press Enter for auto-generate)" -ForegroundColor Gray
        $password = Read-Host "Enter encryption password" -AsSecureString

        # Convert to plain text (cross-platform)
        $plain1 = ConvertFrom-SecureStringPlain -SecureString $password

        # Check if user wants auto-generated passphrase
        if ([string]::IsNullOrEmpty($plain1)) {
            $passphrase = New-Passphrase -WordCount 4
            Write-Host ""
            Write-Host "Generated passphrase:" -ForegroundColor Green
            Write-Host "  $passphrase" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "IMPORTANT: Save this passphrase now - you will share it separately!" -ForegroundColor Yellow
            Write-Host ""

            $confirm = Read-Host "Press Enter to accept, or type 'new' for a different passphrase"
            while ($confirm -eq "new") {
                $passphrase = New-Passphrase -WordCount 4
                Write-Host ""
                Write-Host "Generated passphrase:" -ForegroundColor Green
                Write-Host "  $passphrase" -ForegroundColor Cyan
                Write-Host ""
                $confirm = Read-Host "Press Enter to accept, or type 'new' for a different passphrase"
            }

            return $passphrase
        }

        Write-Host "(Characters will not appear as you type)" -ForegroundColor Gray
        $confirm = Read-Host "Confirm password" -AsSecureString
        $plain2 = ConvertFrom-SecureStringPlain -SecureString $confirm

        if ($plain1 -ne $plain2) {
            Write-Host "ERROR: Passwords do not match!" -ForegroundColor Red
            if ($attempt -lt $MaxAttempts) {
                Write-Host "Please try again." -ForegroundColor Yellow
            }
            continue
        }

        if ($plain1.Length -lt $MIN_PASSWORD_LENGTH) {
            Write-Host "ERROR: Password must be at least $MIN_PASSWORD_LENGTH characters!" -ForegroundColor Red
            if ($attempt -lt $MaxAttempts) {
                Write-Host "Please try again." -ForegroundColor Yellow
            }
            continue
        }

        # Password accepted
        return $plain1
    }

    Write-Host ""
    Write-Host "Maximum password attempts reached. Exiting." -ForegroundColor Red
    return $null
}

function Encrypt-File {
    param(
        [string]$InputPath,
        [string]$Password
    )

    try {
        # Read input file
        $plainBytes = [System.IO.File]::ReadAllBytes($InputPath)

        # Generate random salt and IV
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $salt = New-Object byte[] $SALT_SIZE
        $iv = New-Object byte[] $IV_SIZE
        $rng.GetBytes($salt)
        $rng.GetBytes($iv)

        # Derive key using PBKDF2
        $keyDeriver = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
            $Password,
            $salt,
            $ITERATIONS,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256
        )
        $key = $keyDeriver.GetBytes($KEY_SIZE)

        # Create AES encryptor
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $key
        $aes.IV = $iv

        # Encrypt
        $encryptor = $aes.CreateEncryptor()
        $cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)

        # Combine: Salt + IV + Ciphertext
        $outputBytes = New-Object byte[] ($SALT_SIZE + $IV_SIZE + $cipherBytes.Length)
        [Array]::Copy($salt, 0, $outputBytes, 0, $SALT_SIZE)
        [Array]::Copy($iv, 0, $outputBytes, $SALT_SIZE, $IV_SIZE)
        [Array]::Copy($cipherBytes, 0, $outputBytes, $SALT_SIZE + $IV_SIZE, $cipherBytes.Length)

        # Write output file
        $outputPath = "$InputPath.Locked"
        [System.IO.File]::WriteAllBytes($outputPath, $outputBytes)

        # Cleanup
        $aes.Dispose()
        $keyDeriver.Dispose()
        $rng.Dispose()

        return $outputPath
    }
    catch {
        Write-Host "ERROR encrypting $InputPath : $_" -ForegroundColor Red
        return $null
    }
}

function Get-FilesToEncrypt {
    param([string[]]$Paths)

    $files = @()

    foreach ($p in $Paths) {
        if (Test-Path $p -PathType Container) {
            # It's a folder - get all files recursively
            $folderFiles = Get-ChildItem -Path $p -File -Recurse |
                           Where-Object { $_.Extension -ne ".Locked" -and $_.Name -ne "README.md" }
            $files += $folderFiles.FullName
        }
        elseif (Test-Path $p -PathType Leaf) {
            # It's a file
            if ($p -notlike "*.Locked" -and (Split-Path $p -Leaf) -ne "README.md") {
                $files += (Resolve-Path $p).Path
            }
        }
        else {
            Write-Host "WARNING: Path not found: $p" -ForegroundColor Yellow
        }
    }

    return $files
}

function Generate-ReadMe {
    param(
        [string]$OutputDir,
        [string[]]$EncryptedFiles,
        [hashtable]$CUICategory = @{ Short = "CUI"; Full = "CONTROLLED UNCLASSIFIED INFORMATION (CUI)" }
    )

    $fileList = ($EncryptedFiles | ForEach-Object { "- ``$(Split-Path $_ -Leaf)``" }) -join "`n"

    $readme = @"
# $($CUICategory.Short) - Encrypted Files - Decryption Instructions

> **$($CUICategory.Full)**
> This document contains CUI handling instructions. Protect accordingly.

## Why You Received Password-Encrypted Files

This email uses password-based encryption rather than certificate-based encryption (S/MIME) because one of the following applies:

- You do not have a PIV/CAC smart card with email encryption certificate
- Your certificate was not accessible to the sender (different organization, no directory access)
- Your email client does not support S/MIME decryption
- This is one-time or infrequent communication where certificate exchange was not practical

When both parties have PIV/CAC, native S/MIME (Outlook Sign+Encrypt) is preferred. This tool uses AES-256 encryption via Windows CNG (Cryptography Next Generation), which is FIPS 140-2 validated when Windows FIPS mode is enabled (see [CMVP Certificate #4515](https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4515)).

## Receiving the Password

**You will receive the password via a separate channel.** Per NIST SP 800-63B, passwords for encrypted files should be transmitted out-of-band (not in the same email as the encrypted files).

**Approved channels:**
| Method | Why It's Approved |
|--------|-------------------|
| Phone call (PSTN landline) | Proves possession of phone number |
| SMS text message | Proves possession of device/SIM |
| In-person | Direct verification |
| S/MIME encrypted email | Password protected by asymmetric encryption |

**Not approved:** Unencrypted email (even if sent separately) does not meet out-of-band requirements.

**References:**
- [NIST SP 800-63B §5.1.3](https://pages.nist.gov/800-63-3/sp800-63b.html#-513-out-of-band-devices) - Out-of-band authenticator requirements
- [NIST SP 800-171 §3.13.8](https://csrc.nist.gov/publications/detail/sp/800-171/rev-2/final) - CUI transmission protection
- [32 CFR Part 2002](https://www.ecfr.gov/current/title-32/subtitle-B/chapter-XX/part-2002) - CUI handling requirements

## Encrypted Files

$fileList

## How to Decrypt (Windows PowerShell)

**Quick Start:** Press ``Win+X`` then click "Windows PowerShell" or "Terminal"

### Option 1: File Picker (Recommended - No Typing Paths)

Open PowerShell, then paste this command:

``````powershell
$($DECRYPTION_ONELINER -replace '\$', '`$')
``````

1. **Open dialog** - Browse to and select the .Locked file
2. **Password prompt** - Enter the password (characters won't appear)
3. **Save dialog** - Filename auto-fills (e.g., ``Document.pdf.Locked`` → ``Document.pdf``)

### Option 2: Manual Path Entry

If the file picker doesn't work, use this version instead:

``````powershell
`$f=Read-Host "Full path to .Locked file";`$p=Read-Host "Password" -AsSecureString;`$d=[IO.File]::ReadAllBytes(`$f);`$k=[Security.Cryptography.Rfc2898DeriveBytes]::new([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR(`$p)),`$d[0..15],100000,"SHA256");`$a=[Security.Cryptography.Aes]::Create();`$a.Key=`$k.GetBytes(32);`$a.IV=`$d[16..31];`$c=`$a.CreateDecryptor().TransformFinalBlock(`$d,32,`$d.Length-32);[IO.File]::WriteAllBytes(`$f-replace'\.Locked`$','',`$c);Write-Host "Decrypted:"(`$f-replace'\.Locked`$','')
``````

When prompted, enter the **full path** (e.g., ``C:\Users\YourName\Downloads\Document.pdf.Locked``)

### Option 2: Step-by-Step Script

Save this as ``Decrypt.ps1`` and run it, or paste line-by-line:

``````powershell
# Decrypt a .Locked file
# Usage: Change `$filePath to your file, then run

`$filePath = "C:\Path\To\YourFile.ext.Locked"  # <-- CHANGE THIS

# Prompt for password
`$securePassword = Read-Host "Enter decryption password" -AsSecureString
`$password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR(`$securePassword)
)

# Read encrypted file
`$data = [System.IO.File]::ReadAllBytes(`$filePath)

# Extract salt (first 16 bytes) and IV (next 16 bytes)
`$salt = `$data[0..15]
`$iv = `$data[16..31]
`$ciphertext = `$data[32..(`$data.Length - 1)]

# Derive key using PBKDF2
`$keyDeriver = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
    `$password, `$salt, 100000, "SHA256"
)
`$key = `$keyDeriver.GetBytes(32)

# Decrypt using AES-256-CBC
`$aes = [System.Security.Cryptography.Aes]::Create()
`$aes.Mode = "CBC"
`$aes.Padding = "PKCS7"
`$aes.Key = `$key
`$aes.IV = `$iv

`$decryptor = `$aes.CreateDecryptor()
`$plainBytes = `$decryptor.TransformFinalBlock(`$ciphertext, 0, `$ciphertext.Length)

# Write decrypted file (removes .Locked extension)
`$outputPath = `$filePath -replace '\.Locked`$', ''
[System.IO.File]::WriteAllBytes(`$outputPath, `$plainBytes)

Write-Host "Decrypted successfully: `$outputPath" -ForegroundColor Green

# Cleanup
`$aes.Dispose()
`$keyDeriver.Dispose()
``````

## Technical Details

| Parameter | Value | Standard |
|-----------|-------|----------|
| Encryption | AES-256-CBC | FIPS 197, FIPS 140-2 |
| Key Derivation | PBKDF2-HMAC-SHA256 | NIST SP 800-132 |
| Iterations | 100,000 | NIST SP 800-132 minimum: 10,000 |
| Salt | 128-bit random (unique per file) | NIST SP 800-132 |
| IV | 128-bit random (unique per file) | NIST SP 800-38A |

**File Format**: Each ``.Locked`` file contains: Salt (16 bytes) + IV (16 bytes) + Ciphertext

**Security Note**: Salt and IV are cryptographically random and unique for each encrypted file. They are automatically extracted from the file during decryption---you only need the password.

**Compliance**: This encryption uses algorithms approved under FIPS 197 (AES) and NIST SP 800-132 (PBKDF2). For full NIST SP 800-171 §3.13.11 compliance, ensure Windows FIPS mode is enabled on systems handling CUI.

## Troubleshooting

- **"Access denied"**: Run PowerShell as Administrator, or save file to Desktop first
- **"Path not found"**: Use full path with drive letter (e.g., ``C:\Users\...``)
- **Garbled output**: Wrong password - try again
- **Script won't run**: Execution policy - use the one-liner instead, or run:
  ``Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned``

---
*Encrypted with SendCUIEmail - $(Get-Date -Format "yyyy-MM-dd HH:mm")*
"@

    $readmePath = Join-Path $OutputDir "README.md"
    [System.IO.File]::WriteAllText($readmePath, $readme)

    return $readmePath
}

function Generate-OutlookEmail {
    param(
        [string]$OutputDir,
        [string[]]$EncryptedFiles,
        [string]$ReadmePath,
        [hashtable]$CUICategory
    )

    # Check platform - Outlook COM only available on Windows
    if (-not $IsWindowsPlatform) {
        Write-Host "  NOTE: Outlook .msg generation requires Windows" -ForegroundColor Yellow
        Write-Host "        (Files are ready to attach manually)" -ForegroundColor Gray
        return $null
    }

    # Check if Outlook is available
    try {
        $outlook = New-Object -ComObject Outlook.Application -ErrorAction Stop
    }
    catch {
        Write-Host "  NOTE: Outlook not available - skipping .msg generation" -ForegroundColor Yellow
        Write-Host "        (Files are ready to attach manually)" -ForegroundColor Gray
        return $null
    }

    try {
        # Create new mail item (draft with no recipients - user must add and review)
        $mail = $outlook.CreateItem(0)  # 0 = olMailItem

        # NOTE: $mail.To is intentionally NOT set
        # This creates a draft that requires the user to:
        # 1. Add recipients manually
        # 2. Review the email contents
        # 3. Click Send
        # This is a safety feature to prevent accidental transmission.

        # Build file list for body
        $fileListText = ($EncryptedFiles | ForEach-Object {
            "  - $(Split-Path $_ -Leaf)"
        }) -join "`r`n"

        # Build optional organization sections
        $orgHandling = ""
        if (-not [string]::IsNullOrEmpty($ORG_HANDLING_INSTRUCTIONS)) {
            $orgHandling = "`r`n$ORG_HANDLING_INSTRUCTIONS"
        }

        $orgSupport = ""
        if (-not [string]::IsNullOrEmpty($ORG_SUPPORT_CONTACT)) {
            $orgSupport = "`r`nQUESTIONS: $ORG_SUPPORT_CONTACT`r`n"
        }

        # CUI-compliant subject line
        $mail.Subject = "$($CUICategory.Short) - Encrypted Files - See README for Decryption Instructions"

        # CUI-compliant body with sender instructions and banner markings
        $mail.Body = @"
********************************************************************************
*                    SENDER INSTRUCTIONS - DELETE BEFORE SENDING               *
********************************************************************************

BEFORE YOU SEND THIS EMAIL:

1. ADD RECIPIENT
   - Enter the recipient's email address in the "To:" field
   - Verify they are authorized to receive CUI

2. SIGN AND ENCRYPT (if you have PIV/CAC)
   - Click "Sign" to prove this email came from you
   - Click "Encrypt" if you have the recipient's S/MIME certificate
   - S/MIME encryption adds transport protection on top of file encryption

3. REVIEW ATTACHMENTS
   - Verify the correct .Locked files are attached
   - Verify README.md is attached
   - Remove any files that should not be sent

4. TEST DECRYPTION (recommended for first-time use)
   - Before sending, decrypt one file yourself using the README instructions
   - Confirms the password works and files are intact

5. PLAN PASSWORD DELIVERY
   - You must send the password via a SEPARATE channel
   - COMPLIANT: Phone call, SMS text, in-person, S/MIME encrypted email
   - NOT COMPLIANT: Unencrypted email (even if separate)

DELETE THIS ENTIRE SECTION BEFORE SENDING as acknowledgement that you have
reviewed these instructions.

********************************************************************************

$($CUICategory.Full)
================================================================================

This email contains Controlled Unclassified Information (CUI) that requires
safeguarding per 32 CFR Part 2002 and NIST SP 800-171.

ENCRYPTED FILES ATTACHED:
$fileListText
  - README.md (Decryption Instructions)

DECRYPTION:
The attached files are encrypted using AES-256 (FIPS 140-2 compliant).
Please refer to the attached README.md for step-by-step decryption instructions.
You will need the password, which will be provided via separate communication.

HANDLING REQUIREMENTS:
- This information is CUI and must be protected accordingly
- Do not forward without authorization
- Store on approved systems only
- Destroy when no longer needed per retention requirements$orgHandling
$orgSupport
================================================================================
$($CUICategory.Full)
"@

        # Attach all encrypted files
        foreach ($file in $EncryptedFiles) {
            $mail.Attachments.Add($file) | Out-Null
        }

        # Attach README
        $mail.Attachments.Add($ReadmePath) | Out-Null

        # Save as .msg file
        $msgPath = Join-Path $OutputDir "CUI_Email_$(Get-Date -Format 'yyyyMMdd_HHmmss').msg"
        $mail.SaveAs($msgPath, 3)  # 3 = olMSG format

        # Cleanup COM objects
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($mail) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook) | Out-Null

        return $msgPath
    }
    catch {
        Write-Host "  WARNING: Failed to create .msg file: $_" -ForegroundColor Yellow
        if ($mail) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($mail) | Out-Null }
        if ($outlook) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook) | Out-Null }
        return $null
    }
}

function Generate-PasswordEmail {
    param(
        [string]$OutputDir,
        [string]$Password,
        [hashtable]$CUICategory
    )

    # Check platform - Outlook COM only available on Windows
    if (-not $IsWindowsPlatform) {
        return $null
    }

    # Check if Outlook is available
    try {
        $outlook = New-Object -ComObject Outlook.Application -ErrorAction Stop
    }
    catch {
        return $null
    }

    try {
        # Create new mail item (draft with no recipients - user must add and review)
        $mail = $outlook.CreateItem(0)  # 0 = olMailItem

        # NOTE: $mail.To is intentionally NOT set
        # This creates a draft that requires the user to:
        # 1. Add recipients manually
        # 2. Review the email contents
        # 3. Click Send
        # This is a safety feature to prevent accidental transmission.

        # Subject line - intentionally vague for security
        $mail.Subject = "RE: Encrypted Files - Additional Information"

        # Build optional organization support section
        $pwdOrgSupport = ""
        if (-not [string]::IsNullOrEmpty($ORG_SUPPORT_CONTACT)) {
            $pwdOrgSupport = "`r`nQUESTIONS: $ORG_SUPPORT_CONTACT`r`n"
        }

        # Try to set S/MIME encryption flag by default
        # PR_SECURITY_FLAGS: 1 = Encrypt, 2 = Sign, 3 = Both
        $encryptionSet = $false
        try {
            $PR_SECURITY_FLAGS = "http://schemas.microsoft.com/mapi/proptag/0x6E010003"
            $mail.PropertyAccessor.SetProperty($PR_SECURITY_FLAGS, 1)  # 1 = Encrypt
            $encryptionSet = $true
        }
        catch {
            # If setting encryption fails (e.g., no certificate), continue without it
            $encryptionSet = $false
        }

        # Build Option B text based on whether encryption was pre-set
        if ($encryptionSet) {
            $optionBText = @"
OPTION B: S/MIME ENCRYPT THIS EMAIL (If recipient has PIV/CAC)
   [ENCRYPTION PRE-ENABLED] This email is configured to encrypt automatically.
   - Enter recipient's email in "To:" field
   - Click "Sign" (proves it came from you)
   - Verify the lock icon appears (encryption active)
   - If encryption fails, you need the recipient's S/MIME certificate
   - Then send this email
"@
        }
        else {
            $optionBText = @"
OPTION B: S/MIME ENCRYPT THIS EMAIL (If recipient has PIV/CAC)
   [ENCRYPTION NOT PRE-SET] You must manually enable encryption.
   - Enter recipient's email in "To:" field
   - Click "Sign" (proves it came from you)
   - Click "Encrypt" (requires recipient's S/MIME certificate)
   - Then send this email
"@
        }

        # Body with password and security warning
        $mail.Body = @"
********************************************************************************
*                    SENDER INSTRUCTIONS - DELETE BEFORE SENDING               *
********************************************************************************

CHOOSE ONE DELIVERY METHOD:

OPTION A: DO NOT SEND THIS EMAIL (Recommended)
   - Call the recipient and read them the password below
   - Or send via SMS text message
   - Or deliver in person
   - Then DELETE this .msg file

$optionBText

OPTION C: UNENCRYPTED EMAIL - NOT COMPLIANT
   Sending this email unencrypted violates NIST SP 800-63B out-of-band
   requirements, even if sent separately from the encrypted files.

DELETE THIS INSTRUCTION SECTION BEFORE SENDING as acknowledgement that you
understand the compliance requirements.

********************************************************************************

DECRYPTION COMMAND (paste into PowerShell):

$DECRYPTION_ONELINER

================================================================================

DECRYPTION PASSWORD:

    $Password

================================================================================

AFTER DELIVERY:
- Delete this email/file (contains plaintext password)
- Confirm recipient successfully decrypted the files
- Document password transmission per your security procedures
$pwdOrgSupport
================================================================================
"@

        # No attachments for password email

        # Save as .msg file
        $msgPath = Join-Path $OutputDir "Password_Email_$(Get-Date -Format 'yyyyMMdd_HHmmss').msg"
        $mail.SaveAs($msgPath, 3)  # 3 = olMSG format

        # Cleanup COM objects
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($mail) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook) | Out-Null

        return $msgPath
    }
    catch {
        if ($mail) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($mail) | Out-Null }
        if ($outlook) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook) | Out-Null }
        return $null
    }
}

# Main execution
Write-Banner

# Collect files to encrypt
Write-Host "Scanning for files..." -ForegroundColor Gray
$files = Get-FilesToEncrypt -Paths $Path

if ($files.Count -eq 0) {
    Write-Host "ERROR: No files found to encrypt!" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($files.Count) file(s) to encrypt:" -ForegroundColor Green
foreach ($f in $files) {
    Write-Host "  - $(Split-Path $f -Leaf)" -ForegroundColor Gray
}
Write-Host ""

# Get CUI category
$cuiCategory = Get-CUICategory
Write-Host ""
Write-Host "Selected: $($cuiCategory.Full)" -ForegroundColor Green
Write-Host ""

# Get password
$password = Get-SecurePassword
if ($null -eq $password) {
    exit 1
}
Write-Host ""

# Determine and display output location upfront
$outputDir = Split-Path $files[0] -Parent
if ([string]::IsNullOrEmpty($outputDir)) {
    $outputDir = Get-Location
}
Write-Host "Output folder:" -ForegroundColor Yellow
Write-Host "  $outputDir" -ForegroundColor White
Write-Host ""

# Encrypt each file
$encryptedFiles = @()

Write-Host "Encrypting files (AES-256-CBC, FIPS 140-2)..." -ForegroundColor Cyan
foreach ($file in $files) {
    Write-Host "  Encrypting: $(Split-Path $file -Leaf)..." -NoNewline
    $result = Encrypt-File -InputPath $file -Password $password
    if ($result) {
        Write-Host " Done" -ForegroundColor Green
        $encryptedFiles += $result
        if ([string]::IsNullOrEmpty($outputDir)) {
            $outputDir = Split-Path $result -Parent
            if ([string]::IsNullOrEmpty($outputDir)) {
                $outputDir = Get-Location
            }
        }
    }
    else {
        Write-Host " FAILED" -ForegroundColor Red
    }
}

# Generate README and email
if ($encryptedFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "Generating README.md..." -NoNewline
    $readmePath = Generate-ReadMe -OutputDir $outputDir -EncryptedFiles $encryptedFiles -CUICategory $cuiCategory
    Write-Host " Done" -ForegroundColor Green

    Write-Host "Generating Outlook emails (.msg)..." -NoNewline
    $msgPath = Generate-OutlookEmail -OutputDir $outputDir -EncryptedFiles $encryptedFiles -ReadmePath $readmePath -CUICategory $cuiCategory
    $pwdMsgPath = Generate-PasswordEmail -OutputDir $outputDir -Password $password -CUICategory $cuiCategory
    if ($msgPath) {
        Write-Host " Done" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "================================================" -ForegroundColor Green
    Write-Host "  Encryption Complete!" -ForegroundColor Green
    Write-Host "  $($cuiCategory.Short)" -ForegroundColor Yellow

    # Show FIPS status in summary
    $fipsStatus = Test-FIPSMode
    if ($fipsStatus.Applicable) {
        if ($fipsStatus.Enabled) {
            Write-Host "  FIPS Mode: ENABLED" -ForegroundColor Green
        }
        else {
            Write-Host "  FIPS Mode: DISABLED (see warning above)" -ForegroundColor Yellow
        }
    }

    Write-Host "================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Output folder:" -ForegroundColor Yellow
    Write-Host "  $outputDir" -ForegroundColor White
    Write-Host ""
    Write-Host "Files ready to send:" -ForegroundColor Cyan
    foreach ($ef in $encryptedFiles) {
        Write-Host "  $ef" -ForegroundColor White
    }
    Write-Host "  $(Join-Path $outputDir 'README.md')" -ForegroundColor White
    if ($msgPath) {
        Write-Host ""
        Write-Host "Email drafts created:" -ForegroundColor Cyan
        Write-Host "  1. $msgPath" -ForegroundColor White
        Write-Host "     (Encrypted files + README)" -ForegroundColor Gray
        if ($pwdMsgPath) {
            Write-Host "  2. $pwdMsgPath" -ForegroundColor White
            Write-Host "     (Password only - SEND SEPARATELY or use alternate channel)" -ForegroundColor Gray
        }
    }
    Write-Host ""
    Write-Host "PASSWORD TRANSMISSION (per NIST SP 800-63B):" -ForegroundColor Yellow
    Write-Host "  [COMPLIANT] Phone call, SMS, or in-person" -ForegroundColor Green
    Write-Host "  [COMPLIANT] S/MIME encrypted email (if recipient has PIV/CAC)" -ForegroundColor Green
    Write-Host "  [NOT COMPLIANT] Unencrypted email - even if separate" -ForegroundColor Red
    Write-Host ""
    Write-Host "OTHER REMINDERS:" -ForegroundColor Yellow
    Write-Host "  - Verify recipient is authorized for CUI" -ForegroundColor Yellow
    Write-Host "  - Document transmission per your retention policy" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "CLEANUP (after sending):" -ForegroundColor Yellow
    Write-Host "  - Delete .msg files from output folder" -ForegroundColor Yellow
    Write-Host "  - Password_Email contains plaintext password" -ForegroundColor Red
    if ($IsWindowsPlatform) {
        Write-Host ""
        Write-Host "TIP: Open output folder:" -ForegroundColor Cyan
        Write-Host "  explorer.exe `"$outputDir`"" -ForegroundColor Gray
    }
}
else {
    Write-Host ""
    Write-Host "ERROR: No files were encrypted successfully." -ForegroundColor Red
    exit 1
}
