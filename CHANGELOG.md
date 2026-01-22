# Changelog

All notable changes to SendCUIEmail will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Request for signed email reply feature (draft email requesting recipient's digital signature)

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
