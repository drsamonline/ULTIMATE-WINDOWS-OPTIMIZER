# 🚀 ULTIMATE WINDOWS OPTIMIZER SUITE v5.1

[![License: BSD 3-Clause](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-5.1.0-brightgreen.svg)]()
[![Status](https://img.shields.io/badge/Status-Production%20Ready-success.svg)]()
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D4.svg)]()
[![Creator](https://img.shields.io/badge/Creator-Coding%20For%20Fun-blueviolet.svg)](https://about.me/drsohil)

# Ultimate Windows Optimizer Suite v5.1


> A comprehensive Windows optimization toolkit offering multiple profiles, advanced modules, rollback and undo capabilities, and complete logging for enhanced system performance and management.

---

## Features

- **8 Optimization Profiles** tailored for different user needs:
  - Daily Home User (+25-35%)
  - Gaming Enthusiast (+40-50%)
  - Office/Productivity (+20%)
  - Laptop/Battery (+30%)
  - Extreme Performance (+60-80%)
  - Godlike Nuclear (+80-120%)
  - Server/VM Optimized (+25%)
  - Streaming/Creator (+45%)

- **Advanced PowerShell Modules** for granular system tuning:
  - Network, Storage, GPU, Memory, CPU, Boot, Display, Audio

- **System Utilities:**
  - Dependency Downloader (auto-fetch required tools)
  - System Cleanup (temporary files, recycle bin, etc.)
  - Comprehensive Undo and Rollback (using restore points)
  - Performance Before/After Comparison
  - Hardware Detection and Compatibility Checks
  - Performance Monitoring

- **Robust Error Handling and Logging** for all operations
- **Safe and Reversible Tweaks**, with user confirmations for critical changes
- **Full Admin and Environment Checks** to prevent faulty executions
- **Guided Restart Prompts** after changes
- **Detailed Documentation** included (setup guides, troubleshooting, audit results)

---

## Getting Started

These instructions will guide you through setting up and using the optimizer suite on your Windows system.

### Prerequisites

- Windows 10 (Build 1909+) or Windows 11
- Administrator privileges to run scripts
- PowerShell 5.0 or higher
- At least 4GB RAM and 500MB free disk space

### Installation

1. Download the ZIP package from the releases or clone this repository.
2. Extract all files preserving folder structure.
3. Open the folder, right-click on `00_Ultimate_Master_v5.1_Production.bat`.
4. Select **Run as Administrator** to launch the main menu.

### Usage

1. From the main menu, choose `[0] Create Restore Point` first for safety.
2. Download dependencies with `[1] Download Dependencies` (optional).
3. Choose an optimization profile `[10-17]` based on your needs.
4. Follow prompts for confirmation and restart your system when asked.
5. Use utilities (cleanup, privacy boost, view logs) as needed.
6. For advanced tweaks, use the `[30] Advanced Modules` option.
7. Undo changes via `[31] Undo Changes` or recover system via `[32] Full Rollback`.

---

## File Structure

Ultimate_Windows_Optimizer_v5.1/

│

├── scripts/

│ ├── 00_Ultimate_Master_v5.1_Production.bat # Main interactive menu

│ ├── 01_Auto_Dependency_Downloader_FINAL.bat # Auto downloader for tools

│ ├── 02_Undo_Last_Change.bat # Undo last applied optimization

│ ├── 03_Full_System_Rollback.bat # System restore rollback batch

│ ├── Optimize-*.ps1 # PowerShell profile modules

│ ├── Advanced-Modules.ps1 # 8 advanced system modules

│ ├── 04_Compare_Results.ps1 # Before/after performance compare

│ ├── Hardware-Detection.ps1 # Detect CPU, GPU, RAM etc.

│ ├── Compatibility-Check.ps1 # Check Windows compatibility

│ ├── Performance-Monitor.ps1 # Real-time performance monitoring

│ ├── Undo-All-Changes.ps1 # Undo all PowerShell changes

│ ├── System-Rollback.ps1 # Advanced rollback PowerShell script

│ ├── Cleanup-System.ps1 # System cleanup PowerShell script

│

├── README.md # This file

├── QUICK_START.txt # Quick setup guide

├── INSTALLATION_GUIDE.md # Detailed setup and troubleshooting

├── FEATURES_COMPLETE.txt # Comprehensive feature list

├── TROUBLESHOOTING.txt # Troubleshooting guide

├── ADVANCED_OPTIONS.txt # Advanced usage and scheduling guide

├── AUDIT_FIXES_APPLIED.txt # Audit report and fix summary

├── LICENSE # BSD 3-Clause license

│

└── Dependencies/

└── README.txt # Info on downloaded utilities



---

## Contributing

Contributions are welcome! Please fork the repository and submit pull requests.

- Follow coding style and consistency.
- Test your changes thoroughly before submission.
- Include descriptive commit messages.
- Update documentation where necessary.

---

## Support

For issues, reach out via:

- Email: sohilmomin2000@gmail.com
- GitHub Issues: [github.com/DrSamOnline/Ultimate-Windows-Optimizer-Suite](https://github.com/DrSamOnline/Ultimate-Windows-Optimizer-Suite)

---

## License

This project is licensed under the BSD 3-Clause License — see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- Thanks to all contributors, testers, and users who helped improve this suite.
- Inspired by best practices in system optimization and automation scripting.

---

## Disclaimer

Use these optimizations at your own risk. Always back up your data and create a system restore point before applying changes. Some profiles (e.g., Godlike) disable security features and should be used only on offline or dedicated machines.

---

Happy optimizing! 🚀
