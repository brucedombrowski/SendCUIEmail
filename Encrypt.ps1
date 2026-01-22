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

# Configuration - FIPS 140-2 / NIST SP 800-132 compliant
$ITERATIONS = 100000  # PBKDF2 iterations (NIST SP 800-132 recommends minimum 10,000)
$SALT_SIZE = 16       # bytes (128 bits)
$KEY_SIZE = 32        # bytes (256 bits for AES-256)
$IV_SIZE = 16         # bytes (128 bits for AES block size)

# Platform detection
$IsWindowsPlatform = $PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows

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
$CUI_CATEGORIES = @{
    "1" = @{ Short = "CUI"; Full = "CONTROLLED UNCLASSIFIED INFORMATION (CUI)" }
    "2" = @{ Short = "CUI//SP-CTI"; Full = "CUI//SP-CTI (Controlled Technical Information)" }
    "3" = @{ Short = "CUI//SP-EXPT"; Full = "CUI//SP-EXPT (Export Controlled)" }
    "4" = @{ Short = "CUI//SP-PRVCY"; Full = "CUI//SP-PRVCY (Privacy)" }
    "5" = @{ Short = "CUI//SP-PROPIN"; Full = "CUI//SP-PROPIN (Proprietary Business Information)" }
}

function Write-Banner {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  SendCUIEmail - CUI File Encryption Tool" -ForegroundColor Cyan
    Write-Host "  FIPS 140-2 / NIST SP 800-171 Compliant" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Get-CUICategory {
    Write-Host "Select CUI Category:" -ForegroundColor Yellow
    Write-Host ""
    foreach ($key in ($CUI_CATEGORIES.Keys | Sort-Object)) {
        Write-Host "  [$key] $($CUI_CATEGORIES[$key].Full)" -ForegroundColor White
    }
    Write-Host ""

    do {
        $selection = Read-Host "Enter selection (1-5)"
    } while (-not $CUI_CATEGORIES.ContainsKey($selection))

    return $CUI_CATEGORIES[$selection]
}

function Get-SecurePassword {
    param([int]$MaxAttempts = 3)

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        if ($attempt -gt 1) {
            Write-Host ""
            Write-Host "Attempt $attempt of $MaxAttempts" -ForegroundColor Yellow
        }

        $password = Read-Host "Enter encryption password" -AsSecureString
        $confirm = Read-Host "Confirm password" -AsSecureString

        # Convert to plain text for comparison (cross-platform)
        $plain1 = ConvertFrom-SecureStringPlain -SecureString $password
        $plain2 = ConvertFrom-SecureStringPlain -SecureString $confirm

        if ($plain1 -ne $plain2) {
            Write-Host "ERROR: Passwords do not match!" -ForegroundColor Red
            if ($attempt -lt $MaxAttempts) {
                Write-Host "Please try again." -ForegroundColor Yellow
            }
            continue
        }

        if ($plain1.Length -lt 8) {
            Write-Host "ERROR: Password must be at least 8 characters!" -ForegroundColor Red
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

### Option 1: One-Liner (Copy & Paste)

Open **PowerShell** (Start Menu → type "PowerShell" → Enter), then paste this command:

``````powershell
`$f=Read-Host "File";`$p=Read-Host "Password" -AsSecureString;`$d=[IO.File]::ReadAllBytes(`$f);`$k=[Security.Cryptography.Rfc2898DeriveBytes]::new([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR(`$p)),`$d[0..15],100000,"SHA256");`$a=[Security.Cryptography.Aes]::Create();`$a.Key=`$k.GetBytes(32);`$a.IV=`$d[16..31];`$c=`$a.CreateDecryptor().TransformFinalBlock(`$d,32,`$d.Length-32);[IO.File]::WriteAllBytes(`$f-replace'\.Locked`$','',`$c);Write-Host "Decrypted:"(`$f-replace'\.Locked`$','')
``````

When prompted:
1. Enter the full path to the .Locked file (e.g., ``C:\Downloads\Document.pdf.Locked``)
2. Enter the password

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

        # CUI-compliant subject line
        $mail.Subject = "$($CUICategory.Short) - Encrypted Files - See README for Decryption Instructions"

        # CUI-compliant body with banner markings
        $mail.Body = @"
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
- Destroy when no longer needed per retention requirements

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

        # Body with password and security warning
        $mail.Body = @"
SECURITY NOTICE - READ BEFORE SENDING
================================================================================

COMPLIANT OPTIONS FOR PASSWORD DELIVERY:

1. PHONE/SMS/IN-PERSON (Recommended)
   Share this password via separate channel - do not send this email.

2. S/MIME SIGN AND ENCRYPT THIS EMAIL (If both parties have PIV/CAC)
   Click "Sign" and "Encrypt" in Outlook before sending.
   - Encrypts with recipient's public certificate (only they can read it)
   - Signs with your private key (proves it came from you)

3. UNENCRYPTED EMAIL - NOT COMPLIANT per NIST SP 800-63B
   Sending this email unencrypted does not meet out-of-band requirements.

================================================================================

DECRYPTION PASSWORD:

    $Password

================================================================================

AFTER DELIVERY:
- Delete this email from your Sent folder
- Confirm recipient received and successfully decrypted the files
- Document password transmission per your security procedures

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

# Encrypt each file
$encryptedFiles = @()
$outputDir = $null

Write-Host "Encrypting files (AES-256-CBC, FIPS 140-2)..." -ForegroundColor Cyan
foreach ($file in $files) {
    Write-Host "  Encrypting: $(Split-Path $file -Leaf)..." -NoNewline
    $result = Encrypt-File -InputPath $file -Password $password
    if ($result) {
        Write-Host " Done" -ForegroundColor Green
        $encryptedFiles += $result
        if ($null -eq $outputDir) {
            $outputDir = Split-Path $result -Parent
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
    Write-Host "================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Files ready to send:" -ForegroundColor Cyan
    foreach ($ef in $encryptedFiles) {
        Write-Host "  - $(Split-Path $ef -Leaf)" -ForegroundColor White
    }
    Write-Host "  - README.md" -ForegroundColor White
    if ($msgPath) {
        Write-Host ""
        Write-Host "Email drafts created:" -ForegroundColor Cyan
        Write-Host "  1. $(Split-Path $msgPath -Leaf)" -ForegroundColor White
        Write-Host "     (Encrypted files + README)" -ForegroundColor Gray
        if ($pwdMsgPath) {
            Write-Host "  2. $(Split-Path $pwdMsgPath -Leaf)" -ForegroundColor White
            Write-Host "     (Password only - SEND SEPARATELY or use alternate channel)" -ForegroundColor Gray
        }
    }
    Write-Host ""
    Write-Host "Location: $outputDir" -ForegroundColor Gray
    Write-Host ""
    Write-Host "SECURITY REMINDERS:" -ForegroundColor Yellow
    Write-Host "  - PREFERRED: Share password via phone, text, or in-person" -ForegroundColor Yellow
    Write-Host "  - If using email: Send password SEPARATELY from encrypted files" -ForegroundColor Yellow
    Write-Host "  - Verify recipient is authorized for CUI" -ForegroundColor Yellow
    Write-Host "  - Document transmission per your retention policy" -ForegroundColor Yellow
}
else {
    Write-Host ""
    Write-Host "ERROR: No files were encrypted successfully." -ForegroundColor Red
    exit 1
}
