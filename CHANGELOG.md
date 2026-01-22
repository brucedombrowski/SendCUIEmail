# Changelog

All notable changes to SendCUIEmail will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### v1.0.0 Target (Non-Technical User Release)
- Any UX improvements from developer beta feedback
- Production-ready for non-technical CUI handlers

### Backlog
- Request for signed email reply feature (draft email requesting recipient's digital signature)

## [0.7.1] - 2026-01-22

### Changed
- **Recipient Decryption One-Liner** - Now uses file picker dialogs instead of typing paths
  - Open dialog to browse and select .Locked file
  - Save dialog to choose where to save decrypted file
  - No more path typing errors or System32 working directory issues
  - README.md instructions updated with new one-liner

## [0.7.0] - 2026-01-22

### Added
- **Sender Instructions in Email Drafts** - On-the-spot training to prevent leakage
  - CUI_Email: 5-step checklist before sending (add recipient, sign/encrypt, review attachments, test decryption, plan password delivery)
  - Password_Email: Clear delivery options (phone/SMS, S/MIME encrypt, or non-compliant warning)
  - Instructions must be deleted before sending as acknowledgement
- **Password Email Pre-Configured for Encryption** - S/MIME encryption enabled by default
  - Sets PR_SECURITY_FLAGS via MAPI to enable encryption automatically
  - Email body shows `[ENCRYPTION PRE-ENABLED]` or `[ENCRYPTION NOT PRE-SET]` status
  - Guides sender based on whether encryption was successfully configured
- **Organization Configuration Variables** - Customize for your organization when forking
  - `$ORG_NAME` - Organization name for branding
  - `$ORG_SUPPORT_CONTACT` - Support contact info for recipients
  - `$ORG_HANDLING_INSTRUCTIONS` - Additional handling requirements
  - `$MIN_PASSWORD_LENGTH` - Minimum password length (default 8)
  - `$DEFAULT_CUI_CATEGORY` - Default CUI category selection

## [0.6.1] - 2026-01-22

### Fixed
- **Empty Path Error** - Fixed "cannot bind argument to Path" error when encrypting files without full path
  - `Split-Path -Parent` returns empty for files like `document.pdf` vs `C:\path\document.pdf`
  - Now defaults to current directory when parent path is empty

### Added
- **Release Scripts** - New two-step release workflow
  - `stage-release.sh` - Prepares release (updates versions, compiles docs, runs tests)
  - `publish-release.sh` - Publishes release (commits, tags, pushes, creates GitHub release)

## [0.6.0] - 2026-01-21

### Added
- **Quick-Start Guide PDF** - 2-page guide in Docs/QuickStart_Guide.pdf
  - Part A: Encrypting Files (Sender) - 5 steps with color-coded boxes
  - Part B: Decrypting Files (Recipient) - 5 steps
  - S/MIME security hierarchy guidance (3 options for different scenarios)
  - Defense-in-depth rationale for combining S/MIME + file encryption
- **Auto-Generated Passphrase** - Press Enter at password prompt for secure passphrase
  - 4-word passphrase using cryptographic RNG (e.g., "beach-flame-ocean-pride")
  - Aligns with NIST SP 800-63B guidance: length > complexity
  - Type "new" to regenerate if desired
- **Output Folder Shown at Start** - Path displayed before encryption begins
- **Explorer Tip on Windows** - Shows `explorer.exe` command to open output folder

### Fixed
- Password delivery guidance now correctly lists S/MIME encrypted email as compliant

## [0.5.3] - 2026-01-21

### Changed
- **Password Entry UX** - Added hint "(Characters will not appear as you type)" before each password prompt
- **Output Location Display** - Output folder now shown prominently at top of file list with full paths
  - Yellow "Output folder:" label draws attention
  - All encrypted/decrypted files shown with full absolute paths
  - Easier for users to locate their files

### Documentation
- DM-2026-006: Beta readiness assessment with implementation plan

## [0.5.2] - 2026-01-21

### Added
- Cleanup reminder in console output warning users to delete .msg files after sending
- Password_Email warning highlighted in red (contains plaintext password)

## [0.5.1] - 2026-01-21

### Changed
- Password requirements now shown upfront before first prompt (not just after validation failure)
- Password transmission guidance now shows explicit compliance status:
  - `[COMPLIANT]` Phone call, SMS, in-person, S/MIME encrypted email
  - `[NOT COMPLIANT]` Unencrypted email - even if separate

## [0.5.0] - 2026-01-21

### Added
- **Multiple CUI Subcategory Selection** per 32 CFR Part 2002.20(a)(3)
  - Users can now select multiple subcategories (e.g., "1,2" for CTI+EXPT)
  - Generates proper compound markings like `CUI//SP-CTI//SP-EXPT`
  - Option 0 or empty input defaults to basic `CUI`

### Documentation
- DM-2026-005: Multiple CUI subcategory selection support decision memo

## [0.4.0] - 2026-01-21

### Added
- **Shell Wrapper Scripts** for macOS/Linux convenience
  - `Encrypt.sh` - Calls Encrypt.ps1 via pwsh
  - `Decrypt.sh` - Calls Decrypt.ps1 via pwsh
  - Both scripts encrypt/decrypt all files in directory when called with no arguments
  - Automatic filtering of scripts, .Locked files, and README from encryption

## [0.3.0] - 2026-01-21

### Documentation
- DM-2026-004: VER document numbering policy (stable IDs across releases)

## [0.2.0] - 2026-01-21

### Added
- **FIPS Mode Detection**
  - Automatic detection of Windows FIPS mode via registry key
  - Visual warning when FIPS mode is disabled
  - FIPS status displayed in completion summary

- **Cryptographic Compliance Verification**
  - VER-2026-001: Formal verification document for cryptographic compliance
  - Line-by-line code verification against NIST SP 800-132 and FIPS 197
  - Compliance summary matrix with verification status

- **Test Infrastructure**
  - Test output logging to `.builds/test_YYYYMMDD_HHMMSS.log`
  - Automatic PDF compilation of verification document when tests pass
  - Console output preserved while logging to file

### Changed
- Test script now produces verification PDF in `.builds/test/` directory
- Improved test output organization

### Documentation
- VER-2026-001_cryptographic_compliance.tex - Full cryptographic verification document
- DM-2026-004: VER document numbering policy (stable IDs across releases)
- LaTeX-formatted compliance verification with code listings
- Cross-referenced NIST/FIPS standards

## [0.1.0] - 2026-01-21

### Added
- **Core Encryption**
  - AES-256-CBC encryption (FIPS 140-2 compliant)
  - PBKDF2-HMAC-SHA256 key derivation (100,000 iterations per NIST SP 800-132)
  - 128-bit random salt and IV generation

- **CUI Support**
  - Five CUI category options per 32 CFR Part 2002
  - Proper CUI banners in email templates
  - Compliance documentation in decision memos

- **Email Integration (Windows)**
  - Outlook .msg draft generation for encrypted files
  - Separate password email draft with security warnings
  - CUI-compliant subject lines and body formatting

- **Recipient Experience**
  - README.md with PowerShell one-liner for decryption
  - Step-by-step decryption script included
  - NIST/FIPS compliance references in decryption instructions
  - No executable files sent - only PowerShell built-in APIs

- **Cross-Platform**
  - Windows PowerShell 5.1+ support (primary target)
  - PowerShell Core 7+ support for macOS/Linux (development/testing)
  - Graceful fallback when Outlook not available

- **Testing**
  - Automated test suite (`test.sh` / `Test.bat`)
  - Unit tests for encryption/decryption round-trip
  - Integration tests with full workflow
  - Test data generation scripts
  - `.builds/test/` output directory for inspection

- **Documentation**
  - Security hierarchy guidance (S/MIME vs SendCUIEmail)
  - NIST SP 800-63B compliance notes for password transmission
  - Decision memos (DM-2026-002 file size limit, DM-2026-003 password transmission)
  - File size limit guidance (10 MB maximum)

### Security
- Password confirmation required (prevents typos)
- Minimum 8-character password enforcement
- Password email includes compliance warnings
- Out-of-band password delivery guidance per NIST SP 800-63B
- S/MIME hybrid approach documented for organizations with PIV/CAC

### Dependencies
- Windows: PowerShell 5.1+ (built-in)
- macOS/Linux: PowerShell Core 7+ (optional)
- Microsoft Outlook (optional, for .msg generation)
