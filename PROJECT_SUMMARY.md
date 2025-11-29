# Project Summary

## VoLTE IMS Testbed - Complete Implementation

This document provides a high-level overview of the project for colleagues and supervisors.

---

## Project Information

**Course:** Network Virtualization & Optimization  
**Level:** Masters in Telecommunications & Networks  
**Date:** November 2025  
**Status:** ✅ Complete and Functional

---

## What Was Built

A complete end-to-end VoLTE (Voice over LTE) testbed that demonstrates:
- LTE network attachment and mobility management
- IMS-based SIP call signaling
- VoLTE call setup with real protocol interactions
- Performance measurement and analysis

**All components run on a single machine** using software-defined networking and virtual radio.

---

## Key Components

### 1. EPC Core Network (Open5GS)
- MME, HSS, SGW, PGW, PCRF, SMF, UPF
- Handles UE authentication and session management
- Allocates IP addresses and manages bearers

### 2. Radio Access Network (srsRAN)
- Software eNodeB (base station)
- Software UE (user equipment)
- ZMQ virtual radio (no RF hardware needed)

### 3. IMS Core (Kamailio)
- SIP proxy/registrar
- P-CSCF, I-CSCF, S-CSCF functions
- MySQL-backed subscriber database

---

## Technical Achievements

### Performance Metrics

| Metric | Value |
|--------|-------|
| SIP Registration Delay | **18.7 ms** |
| Challenge Response Time | 6.1 ms |
| Authentication Time | 12.2 ms |
| UE Attachment Time | 2-4 seconds |
| S1 Setup Success Rate | 100% |

### Network Configuration

- **PLMN:** 001-01 (MCC=001, MNC=01)
- **TAC:** 7
- **Bandwidth:** 10 MHz (50 PRBs)
- **Frequency:** Band 7 (2680 MHz DL, 2560 MHz UL)
- **Dual APN:** Data (10.45.0.0/16) + IMS (10.46.0.0/16)

---

## What Makes This Work

### Integration Points

1. **srsRAN ↔ Open5GS**
   - S1-AP interface for control plane
   - GTP-U tunneling for user plane
   - Proper PLMN and TAC configuration

2. **Open5GS ↔ Kamailio**
   - Dual APN configuration
   - IP routing through ogstun interface
   - Separate data and IMS networks

3. **UE ↔ IMS**
   - TUN interface for IP connectivity
   - SIP registration with MD5 authentication
   - VoLTE call setup with SDP negotiation

### Key Design Decisions

**Why ZMQ Virtual Radio?**
- No expensive SDR hardware needed
- Reproducible results
- Same protocol stack as real LTE

**Why Single-Host Architecture?**
- Easy setup for academic environment
- Simple debugging
- Follows standard configurations

**Why SIP Digest Instead of 3GPP AKA?**
- Open5GS HSS doesn't expose Diameter Cx interface
- Kamailio integration would be complex
- Core concepts preserved (CSCF roles, SIP flows)
- Acceptable for academic demonstration

---

## File Organization

```
volte-ims-testbed/
├── README.md                    # Project overview
├── docs/                        # Comprehensive documentation
│   ├── QUICKSTART.md           # Setup from scratch
│   ├── ARCHITECTURE.md         # System design
│   ├── TECHNICAL_DETAILS.md   # Deep dive into configs
│   └── TROUBLESHOOTING.md     # Common issues
├── srsran-config/              # RAN configurations
│   ├── enb.conf               # eNodeB config
│   ├── ue.conf                # UE config
│   ├── rr.conf                # Radio resources
│   └── sib.conf               # System information
├── volte-demo.sh              # Automated demonstration
├── initialize-system.sh       # System setup script
├── cleanup-demo.sh            # Cleanup utility
├── sip_register_test.py       # SIP testing tool
├── volte_call_test.py         # Call setup test
└── demo/                      # Results (timestamped)
    └── YYYYMMDD_HHMMSS/
        ├── summary.txt        # Performance metrics
        ├── sip_capture.pcap   # Packet capture
        └── *.log              # Component logs
```

---

## How to Use

### Quick Demo

```bash
# Initialize the system
sudo ./initialize-system.sh

# Run automated demo
sudo ./volte-demo.sh

# Results saved to: demo/<timestamp>/
```

### Manual Testing

```bash
# Start eNB
sudo srsenb srsran-config/enb.conf < /dev/null > /tmp/enb.log 2>&1 &

# Start UE (wait 5 seconds first)
sudo srsue srsran-config/ue.conf < /dev/null > /tmp/ue.log 2>&1 &

# Wait for attachment (~3 seconds)

# Run SIP test
python3 sip_register_test.py
```

---

## Problems Solved

### Technical Challenges Overcome

1. **Kamailio MySQL Socket Issue**
   - MySQL 8.0+ uses different socket path
   - Solution: Added socket parameter to connection string

2. **TAC Mismatch Causing S1 Failures**
   - eNB loaded wrong config file (relative paths)
   - Solution: Used absolute paths in enb.conf

3. **UE Process Exiting in Background**
   - srsUE exits when stdin closes
   - Solution: Redirect stdin from /dev/null

4. **Network Namespace Permission Failure**
   - srsUE cannot create namespaces
   - Solution: Disabled netns, use default namespace

5. **IMS Connectivity Issues**
   - Missing IMS APN address on ogstun
   - Solution: Manually add 10.46.0.1/16 to ogstun

---

## Documentation Highlights

### For Quick Setup
Start with **docs/QUICKSTART.md** - complete step-by-step installation and configuration guide.

### For Understanding Architecture
Read **docs/ARCHITECTURE.md** - explains system design, component interactions, and protocol flows.

### For Configuration Details
See **docs/TECHNICAL_DETAILS.md** - every config file, every parameter, every integration point explained.

### For Troubleshooting
Check **docs/TROUBLESHOOTING.md** - all real issues we encountered and their solutions.

---

## Testing Results

### SIP Registration Flow

```
Step 1: REGISTER (no auth)     →  401 Unauthorized (6ms)
Step 2: REGISTER (with auth)   →  200 OK (12ms)
Total: 18ms
```

### UE Attachment Flow

```
Cell Search          → 1-2 seconds
Random Access        → 10-50 ms
Authentication       → 200-500 ms
PDN Connectivity     → 200-500 ms
Total: 2-4 seconds
```

---

## Academic Value

This project demonstrates:
- **Network Virtualization:** Multiple network functions on single host
- **Protocol Integration:** S1-AP, GTP, SIP coordination
- **Performance Analysis:** Quantitative measurement of signaling delays
- **Software-Defined Networking:** TUN/TAP interfaces, virtual radio
- **IMS Architecture:** Understanding of CSCF roles and SIP flows

---

## Limitations & Future Work

### Current Limitations
- Single-host deployment (not distributed)
- Single UE testing (no multi-user scenarios)
- SIP Digest auth (not full 3GPP AKA/Diameter)
- No RTP media (signaling only)
- ZMQ virtual radio (no real RF testing)

### Potential Enhancements
- Multi-UE testing with namespace isolation
- Full 3GPP IMS with Diameter Cx interface
- RTP media server integration (Asterisk/FreeSWITCH)
- Distributed deployment across multiple VMs
- Real RF testing with USRP hardware
- Performance under load testing
- Handover scenarios (multi-cell)

---

## Skills Demonstrated

- **Telecommunications:** LTE, IMS, VoLTE protocols
- **System Integration:** Multiple complex systems working together
- **Linux Networking:** TUN/TAP, routing, IP forwarding
- **Debugging:** Protocol analysis, log interpretation, systematic troubleshooting
- **Automation:** Bash scripting, error handling, retry logic
- **Documentation:** Comprehensive technical writing
- **Performance Analysis:** Microsecond-precision timing measurements

---

## Repository Ready

This project is organized and documented for:
- ✅ Colleagues to replicate the setup
- ✅ Supervisor to evaluate the work
- ✅ Portfolio/CV inclusion
- ✅ Future students as reference
- ✅ GitHub public repository

---

## Quick Reference

**Repository Name:** `volte-ims-testbed`

**Key Commands:**
```bash
sudo ./initialize-system.sh    # Setup after reboot
sudo ./volte-demo.sh           # Run demonstration
sudo ./cleanup-demo.sh         # Stop RAN processes
```

**Key Files:**
- Configuration: `srsran-config/*.conf`
- Scripts: `*.sh`
- Tests: `*_test.py`
- Docs: `docs/*.md`

**Key Ports:**
- 2000/2001: ZMQ virtual radio (TCP)
- 5060: SIP (UDP)
- 36412: S1-AP (SCTP)
- 2152: GTP-U (UDP)

---

## Conclusion

This testbed provides a complete, working VoLTE implementation that demonstrates the integration of multiple complex systems. All components are properly configured, tested, and documented. The automated demo script provides reproducible results, and comprehensive documentation enables others to understand and replicate the work.

**Status:** Production-ready for academic demonstration and evaluation.
