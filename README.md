# Abstract

A complete end-to-end VoLTE (Voice over LTE) testbed integrating Open5GS (EPC core), srsRAN (RAN simulation), and Kamailio (IMS core) to demonstrate voice call setup over LTE networks with SIP-based registration and call control.

## Project Overview

This testbed was developed as part of a Masters program in Telecommunications & Networks for the "Network Virtualization & Optimization" course. It provides a fully functional VoLTE environment that can be deployed on a single machine using software-defined networking and virtualized radio access.

**Key Achievement:** SIP registration delay of ~18ms, demonstrating efficient IMS core integration with the EPC.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         VoLTE IMS Testbed                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐         ┌──────────────┐      ┌───────────────┐  │
│  │   srsRAN     │         │   Open5GS    │      │   Kamailio    │  │
│  │              │         │              │      │               │  │
│  │  ┌────────┐  │  S1-AP  │  ┌────────┐  │      │  ┌─────────┐  │  │
│  │  │  eNB   │◄─┼─────────┤  │  MME   │  │      │  │P-CSCF   │  │  │
│  │  └────────┘  │         │  └────────┘  │      │  │I-CSCF   │  │  │
│  │      ▲       │         │      │       │      │  │S-CSCF   │  │  │
│  │      │ ZMQ   │         │  ┌────────┐  │      │  └─────────┘  │  │
│  │      │       │         │  │  HSS   │  │      │       ▲       │  │
│  │  ┌────────┐  │         │  └────────┘  │      │       │ SIP   │  │
│  │  │   UE   │  │         │      │       │      │       │       │  │
│  │  └────────┘  │  S1-U   │  ┌────────┐  │  GTP │  ┌─────────┐  │  │
│  │      │       │◄────────┤  │SGW/PGW │◄─┼──────┤  │   UE    │  │  │
│  └──────┼───────┘         │  └────────┘  │      │  │(SIP UA) │  │  │
│         │                 │      │       │      │  └─────────┘  │  │
│         │                 │  ┌────────┐  │      │               │  │
│         │                 │  │  PCRF  │  │      │   MySQL DB    │  │
│         │                 │  └────────┘  │      │               │  │
│         │                 │      │       │      │               │  │
│         │                 │  ┌────────┐  │      │               │  │
│         │                 │  │  SMF   │  │      │               │  │
│         │                 │  └────────┘  │      │               │  │
│         │                 │      │       │      │               │  │
│         │                 │  ┌────────┐  │      │               │  │
│         │                 │  │  UPF   │  │      │               │  │
│         │                 │  └────────┘  │      │               │  │
│         │                 └──────┼───────┘      └───────────────┘  │
│         │                        │                                 │
│         │    ┌───────────────────┴─────────────────────┐           │
│         └────┤           ogstun Interface               │           │
│              │  Data APN: 10.45.0.0/16 (Internet)       │           │
│              │   IMS APN: 10.46.0.0/16 (VoLTE/IMS)      │           │
│              └──────────────────────────────────────────┘           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

Data Flow:
  [UE] ──ZMQ──> [eNB] ──S1-AP──> [MME] ──GTP──> [SGW/PGW] ──ogstun──> [Kamailio]
                                    │                                      │
                                    └──────────> [HSS] (Authentication)   │
                                                                           │
  [UE SIP Client] ───────────────── SIP REGISTER/INVITE ─────────────────>│
```

## Tech Stack

### Core Network (Open5GS v2.7.6)
- **MME** (Mobility Management Entity) - Handles UE attachment, authentication, tracking area updates
- **HSS** (Home Subscriber Server) - Subscriber database (MongoDB backend)
- **PCRF** (Policy Control and Charging Rules Function) - QoS policy management
- **SGW-C/SGW-U** (Serving Gateway Control/User plane) - Data plane anchoring
- **PGW-C/PGW-U** (Packet Data Network Gateway) - External network connectivity
- **SMF** (Session Management Function) - PDN session management
- **UPF** (User Plane Function) - Packet forwarding and routing

### Radio Access Network (srsRAN 23.04)
- **srsENB** - Software eNodeB implementation with ZMQ virtual radio
- **srsUE** - Software UE implementation for testing
- **Configuration:** FDD LTE, Band 7, 10 MHz bandwidth, PLMN 001-01, TAC 7

### IMS Core (Kamailio v5.7)
- **SIP Proxy/Registrar** - Combines P-CSCF, I-CSCF, S-CSCF functionality
- **Authentication** - SIP Digest MD5 (simplified IMS for academic use)
- **Backend** - MySQL database for subscriber management

### Testing & Monitoring
- **Python 3** - Custom SIP test clients with microsecond-precision timing
- **tcpdump** - SIP packet capture for Wireshark analysis
- **Bash automation** - Complete demo script with retry logic and result archiving

## Key Features

- **Automated Demo Script** - One-command deployment with health checks, attachment polling, and performance measurement
- **Dual APN Support** - Separate data (10.45.0.0/16) and IMS (10.46.0.0/16) network slices
- **SIP Registration Testing** - MD5 Digest authentication with detailed timing metrics
- **Performance Monitoring** - Microsecond-precision measurement of registration delays
- **Packet Capture** - Filtered SIP capture for protocol analysis
- **Timestamped Results** - Each run generates a dated directory with logs, captures, and summaries

## Performance Metrics

Based on testing conducted November 29, 2025:

| Metric | Value |
|--------|-------|
| Challenge Response Time | 6.088 ms |
| Authentication Time | 12.154 ms |
| **Total Registration Delay** | **18.711 ms** |
| UE Attachment Time | ~2-4 seconds |
| S1 Setup Success Rate | 100% |

## Quick Start

For colleagues wanting to replicate this setup:

```bash
# 1. Install required packages (Open5GS, srsRAN, Kamailio)
#    See docs/QUICKSTART.md for detailed installation steps

# 2. Clone this repository
git clone <repository-url>
cd volte-ims-testbed

# 3. Install configurations to system directories
sudo ./install-configs.sh

# 4. Add subscribers via Open5GS WebUI
#    Access at: http://<your-ip>:9999 (default: admin/1423)
#    Add IMSI: 001010000000001 with K and OPc from srsran-config/ue.conf

# 5. Initialize the system (network interfaces, service verification)
sudo ./initialize-system.sh

# 6. Run the automated demonstration
./volte-demo.sh

# Results will be in: demo/<timestamp>/
```

**What's Included:**
- Pre-configured Open5GS, Kamailio, and srsRAN config files
- Automated installation script that backs up existing configs
- Complete testing suite (SIP registration, call setup)
- Comprehensive documentation and troubleshooting guides

For detailed setup instructions, see [docs/QUICKSTART.md](docs/QUICKSTART.md).

## Documentation

- **[Quick Start Guide](docs/QUICKSTART.md)** - Step-by-step setup on a fresh Ubuntu system
- **[Architecture Overview](docs/ARCHITECTURE.md)** - System design and component interactions
- **[Technical Details](docs/TECHNICAL_DETAILS.md)** - Deep dive into configuration and integration
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)** - Common issues and solutions

## Project Structure

```
volte-ims-testbed/
├── README.md                       # This file
├── PROJECT_SUMMARY.md              # Academic project overview
├── QUICK_REFERENCE.md              # One-page command reference
├── install-configs.sh              # Configuration installer (run first!)
├── initialize-system.sh            # System initialization script
├── volte-demo.sh                   # Main demonstration script
├── cleanup-demo.sh                 # Cleanup utility
├── sip_register_test.py           # SIP registration test client
├── volte_call_test.py             # SIP INVITE test client
│
├── open5gs-config/                # Open5GS configuration files
│   ├── mme.yaml                   # MME configuration
│   ├── hss.yaml                   # HSS configuration
│   ├── sgwc.yaml, sgwu.yaml       # SGW configuration
│   ├── upf.yaml                   # UPF configuration
│   ├── pcrf.yaml                  # PCRF configuration
│   └── smf.yaml                   # SMF configuration
│
├── kamailio-config/               # Kamailio IMS configuration
│   └── kamailio.cfg               # SIP proxy/registrar config
│
├── srsran-config/                 # srsRAN configuration files
│   ├── enb.conf                   # eNodeB configuration
│   ├── ue.conf, ue2.conf          # UE configurations
│   ├── rr.conf                    # Radio resource configuration
│   └── sib.conf                   # System information blocks
│
├── docs/                          # Documentation
│   ├── QUICKSTART.md              # Step-by-step setup guide
│   ├── ARCHITECTURE.md            # System design overview
│   ├── TECHNICAL_DETAILS.md       # Configuration deep dive
│   └── TROUBLESHOOTING.md         # Common issues & solutions
│
└── demo/                          # Demo results (timestamped)
    └── YYYYMMDD_HHMMSS/
        ├── summary.txt            # Performance summary
        ├── sip_capture.pcap       # Wireshark-compatible capture
        ├── enb_output.log         # eNodeB logs
        ├── ue_output.log          # UE logs
        └── registration_test_output.log
```

## Academic Context

This project demonstrates:
- **Network Virtualization** - Multiple network functions on a single host
- **Protocol Integration** - S1-AP, GTP, Diameter (HSS), SIP coordination
- **Performance Analysis** - Quantitative measurement of signaling delays
- **IMS Architecture** - Simplified CSCF implementation for VoLTE
- **Software-Defined RAN** - ZMQ-based virtual radio for testing

## Requirements

- Ubuntu 20.04 LTS or later (tested on Ubuntu 22.04)
- 4+ GB RAM recommended
- Open5GS v2.7.6+ installed
- srsRAN 23.04+ installed
- Kamailio v5.7+ installed
- Python 3.8+
- Root/sudo access for network configuration

## Repository

**Project Name:** volte-ims-testbed  
**Purpose:** Academic demonstration of VoLTE/IMS integration  
**Course:** Network Virtualization & Optimization  
**Level:** Masters in Telecommunications & Networks

## License

This project is developed for academic purposes. Feel free to use and modify for educational and research activities.

## Acknowledgments

Built using open-source components:
- [Open5GS](https://open5gs.org/) - Open source 5G/LTE core network
- [srsRAN](https://www.srslte.com/) - Software radio systems for LTE
- [Kamailio](https://www.kamailio.org/) - Open source SIP server

---

For questions or issues, refer to the [Troubleshooting Guide](docs/TROUBLESHOOTING.md).
