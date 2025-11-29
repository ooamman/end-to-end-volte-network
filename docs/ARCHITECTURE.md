# Architecture Overview

This document explains the system architecture, component interactions, network flows, and design decisions for the VoLTE IMS testbed.

## Table of Contents

1. [High-Level Architecture](#high-level-architecture)
2. [Component Breakdown](#component-breakdown)
3. [Network Topology](#network-topology)
4. [Protocol Stack](#protocol-stack)
5. [Call Flows](#call-flows)
6. [Design Decisions](#design-decisions)

---

## High-Level Architecture

The testbed implements a complete end-to-end VoLTE system with three main subsystems:

```
┌─────────────────────────────────────────────────────────────────┐
│                    VoLTE IMS Testbed                            │
│                                                                  │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐       │
│  │     RAN      │   │     EPC      │   │     IMS      │       │
│  │   (srsRAN)   │   │  (Open5GS)   │   │  (Kamailio)  │       │
│  │              │   │              │   │              │       │
│  │  eNB    UE   │◄──┤  MME   HSS   │   │   P-CSCF     │       │
│  │              │   │  SGW   PGW   │◄──┤   I-CSCF     │       │
│  │  (ZMQ RF)    │   │  PCRF  SMF   │   │   S-CSCF     │       │
│  │              │   │       UPF    │   │   (MySQL)    │       │
│  └──────────────┘   └──────────────┘   └──────────────┘       │
│         │                   │                   │               │
│         └───────────────────┴───────────────────┘               │
│                     Linux Kernel                                │
│            (IP forwarding, TUN/TAP interfaces)                  │
└─────────────────────────────────────────────────────────────────┘
```

### Three-Tier Design

1. **Radio Access Network (RAN)** - Handles radio communication and baseband processing
2. **Evolved Packet Core (EPC)** - Manages mobility, session management, and user plane forwarding
3. **IP Multimedia Subsystem (IMS)** - Provides SIP-based voice call signaling

---

## Component Breakdown

### 1. Radio Access Network (srsRAN)

#### eNodeB (Base Station)
- **Purpose:** Simulates an LTE base station
- **Key Functions:**
  - Radio Resource Management (RRM)
  - S1-AP interface to MME (control plane)
  - GTP-U tunneling to SGW (user plane)
  - Physical layer processing (OFDM, turbo coding)
  
- **Configuration:**
  - LTE Band 7 (FDD)
  - 10 MHz bandwidth (50 PRBs)
  - EARFCN 3350 (DL), 21500 (UL calculated)
  - PLMN: MCC=001, MNC=01
  - TAC: 7
  - Cell ID: 0x01, PCI: 1
  
- **Virtual Radio (ZMQ):**
  - TX port: tcp://*:2000 (broadcasts I/Q samples)
  - RX port: tcp://localhost:2001 (receives I/Q samples)
  - Base sample rate: 23.04 MHz
  - Eliminates need for RF hardware

#### UE (User Equipment)
- **Purpose:** Simulates an LTE smartphone
- **Key Functions:**
  - Cell search and synchronization
  - Random access procedure (RACH)
  - RRC connection establishment
  - NAS attach procedure
  - PDN connectivity request
  - Creates TUN interface for IP traffic
  
- **Configuration:**
  - IMSI: 001010000000001
  - USIM credentials (K, OPc)
  - Milenage authentication algorithm
  - APN: "internet"
  - Virtual radio (ZMQ, ports reversed from eNB)
  
- **TUN Interface:** `tun_srsue`
  - Receives IP address from PGW (e.g., 10.45.0.6)
  - Routes all IP traffic through the EPC

### 2. Evolved Packet Core (Open5GS)

#### MME (Mobility Management Entity)
- **Purpose:** Control plane entity for mobility management
- **Key Functions:**
  - UE authentication with HSS (S6a Diameter interface)
  - Tracking Area Update (TAU) management
  - Bearer setup and modification
  - S1-AP interface to eNB
  - GTP-C interface to SGW
  
- **Listen Addresses:**
  - S1-AP: 127.0.0.2:36412
  - GTP-C: 127.0.0.2:2123

#### HSS (Home Subscriber Server)
- **Purpose:** Subscriber database and authentication center
- **Key Functions:**
  - Stores IMSI, K, OPc, APN profiles
  - Generates authentication vectors for MME
  - S6a Diameter interface
  
- **Backend:** MongoDB
- **Database:** `open5gs`
- **Collection:** `subscribers`

#### SGW-C/SGW-U (Serving Gateway)
- **Purpose:** User plane anchor point within EPC
- **Key Functions:**
  - GTP-U tunnel endpoint for eNB
  - Packet routing between eNB and PGW
  - Mobility anchor during handover (not used in single-cell setup)
  
- **Interfaces:**
  - S1-U: GTP-U with eNB
  - S5-U: GTP-U with PGW
  - S11: GTP-C with MME

#### PGW-C/PGW-U (Packet Data Network Gateway)
- **Purpose:** Gateway to external networks
- **Key Functions:**
  - IP address allocation for UEs
  - Creates `ogstun` TUN interface
  - NAT and routing to external networks
  - Policy enforcement with PCRF
  
- **ogstun Interface:** 
  - 10.45.0.1/16 - Data APN
  - 10.46.0.1/16 - IMS APN

#### PCRF (Policy and Charging Rules Function)
- **Purpose:** Policy control and QoS management
- **Key Functions:**
  - Gx interface with PGW
  - QoS rule provisioning
  - Not heavily used in basic testbed

#### SMF (Session Management Function)
- **Purpose:** 5G control plane function (used for session management in this setup)
- **Key Functions:**
  - Session establishment and modification
  - Interworks with PGW functions

#### UPF (User Plane Function)
- **Purpose:** 5G user plane function
- **Key Functions:**
  - Packet forwarding
  - QoS enforcement
  - Works with SMF for session management

### 3. IMS Core (Kamailio)

#### P-CSCF (Proxy-Call Session Control Function)
- **Purpose:** First point of contact for UE in IMS
- **Key Functions:**
  - SIP registration
  - SIP message routing
  - Security (in full IMS; simplified here)
  
#### I-CSCF (Interrogating-CSCF)
- **Purpose:** Entry point to home network
- **Key Functions:**
  - HSS query for user location (in full IMS)
  - Routes SIP requests to appropriate S-CSCF
  - Simplified/combined with S-CSCF in our setup

#### S-CSCF (Serving-CSCF)
- **Purpose:** Central SIP session control
- **Key Functions:**
  - SIP registration handling
  - Authentication (SIP Digest in our case)
  - Call routing and session control
  - Location database (`usrloc` module)
  
- **Simplified Architecture:**
  - All three CSCF functions run in single Kamailio instance
  - No Diameter Cx interface to HSS
  - Uses SIP Digest MD5 authentication instead of 3GPP AKA
  - MySQL backend for subscriber data

---

## Network Topology

### IP Address Allocation

```
┌─────────────────────────────────────────────────────────────────┐
│                  Localhost (127.0.0.0/8)                        │
│                                                                  │
│  MME:     127.0.0.2 (S1-AP, GTP-C)                              │
│  SGW:     127.0.0.3 (GTP-C/U)                                   │
│  HSS:     127.0.0.8 (Diameter)                                  │
│  PCRF:    127.0.0.9 (Diameter)                                  │
│  SMF:     127.0.0.4 (GTP-C)                                     │
│  UPF:     127.0.0.7 (GTP-U)                                     │
│  eNB:     127.0.1.1 (S1-AP, GTP-U)                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                 ogstun Interface (TUN)                          │
│                                                                  │
│  Data APN:  10.45.0.1/16   (PGW endpoint)                       │
│             10.45.0.0/16   (UE address pool)                    │
│                                                                  │
│  IMS APN:   10.46.0.1/16   (IMS network, Kamailio listens here)│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│              tun_srsue Interface (UE side)                      │
│                                                                  │
│  UE IP:     10.45.0.X/24   (Allocated by PGW)                   │
│             Routes to ogstun via kernel routing                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Dual APN Configuration

This testbed uses two APNs to separate data and IMS traffic:

1. **Data APN (10.45.0.0/16):**
   - Default bearer for internet connectivity
   - UE gets IP from this range
   - Routes to external networks (in production)
   - Currently routes to ogstun interface

2. **IMS APN (10.46.0.0/16):**
   - Dedicated bearer for VoLTE signaling
   - Kamailio listens on 10.46.0.1:5060
   - SIP traffic flows over this network
   - QoS priority for voice (in production)

In this testbed, both APNs share the same `ogstun` interface, but in a production network, they would have separate bearers with different QoS profiles.

### Routing Flow

```
UE Application (SIP client)
    │
    ▼
tun_srsue (10.45.0.X)
    │
    ▼
Kernel routing (IP forwarding enabled)
    │
    ▼
ogstun (10.46.0.1) ◄───── Kamailio listens here
    │
    ▼
Kamailio SIP Proxy
```

---

## Protocol Stack

### Control Plane Stack

```
┌─────────────────────────────────────────────────────────────────┐
│                      Control Plane                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  UE ◄──── RRC ────► eNB                                         │
│                      │                                           │
│                      ▼                                           │
│                   S1-AP ◄────────────► MME                       │
│                                        │                         │
│                                        ▼                         │
│                                    GTP-C ◄──► SGW-C              │
│                                               │                  │
│                                               ▼                  │
│                                           GTP-C ◄──► PGW-C       │
│                                                                  │
│  NAS (EMM/ESM) ◄────────────────────────────────────► MME       │
│                                        │                         │
│                                        ▼                         │
│                                   S6a Diameter ◄──► HSS          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### User Plane Stack

```
┌─────────────────────────────────────────────────────────────────┐
│                      User Plane                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  IP (Application data)                                          │
│   │                                                              │
│   ▼                                                              │
│  PDCP (Compression, Ciphering)                                  │
│   │                                                              │
│   ▼                                                              │
│  RLC (Segmentation, ARQ)                                        │
│   │                                                              │
│   ▼                                                              │
│  MAC (Scheduling, HARQ)                                         │
│   │                                                              │
│   ▼                                                              │
│  PHY (Modulation, Coding)                                       │
│   │                                                              │
│   └──► ZMQ ──► eNB ──► GTP-U ──► SGW-U ──► GTP-U ──► PGW-U     │
│                                                      │           │
│                                                      ▼           │
│                                                   ogstun         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### SIP/IMS Stack

```
┌─────────────────────────────────────────────────────────────────┐
│                     SIP/IMS Stack                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  SIP Application (Python test script)                           │
│   │                                                              │
│   ▼                                                              │
│  UDP Socket (port 5060)                                         │
│   │                                                              │
│   ▼                                                              │
│  IP (tun_srsue → ogstun)                                        │
│   │                                                              │
│   ▼                                                              │
│  Kamailio SIP Proxy (10.46.0.1:5060)                            │
│   │                                                              │
│   ├──► usrloc (Location database)                               │
│   ├──► auth_db (Authentication via MySQL)                       │
│   └──► tm (Transaction management)                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Call Flows

### 1. UE Attach Procedure

```
UE                eNB              MME              HSS         SGW/PGW
│                  │                │                │            │
│─── RACH ────────>│                │                │            │
│                  │                │                │            │
│<── RAR ──────────┤                │                │            │
│                  │                │                │            │
│─── RRC Conn ────>│                │                │            │
│    Request       │                │                │            │
│                  │                │                │            │
│<── RRC Conn ─────┤                │                │            │
│    Setup         │                │                │            │
│                  │                │                │            │
│─── RRC Conn ────>│                │                │            │
│    Complete      │                │                │            │
│  (NAS Attach)    │                │                │            │
│                  │                │                │            │
│                  │─── S1-AP ─────>│                │            │
│                  │  Initial UE    │                │            │
│                  │  Message       │                │            │
│                  │                │                │            │
│                  │                │─── S6a ───────>│            │
│                  │                │  Auth Info Req │            │
│                  │                │                │            │
│                  │                │<── S6a ────────┤            │
│                  │                │  Auth Info Ans │            │
│                  │                │  (Auth Vectors)│            │
│                  │                │                │            │
│<─────────────────┴─── Auth Req ──┤                │            │
│  (via RRC/S1-AP) │                │                │            │
│                  │                │                │            │
│────────────────────── Auth Res ──>│                │            │
│                  │                │                │            │
│                  │                │─── S6a ───────>│            │
│                  │                │  Update Loc    │            │
│                  │                │                │            │
│                  │                │<── S6a ────────┤            │
│                  │                │  Update Loc Ans│            │
│                  │                │                │            │
│                  │                │─── S11 GTP-C ─────────────>│
│                  │                │  Create Session Req         │
│                  │                │                │            │
│                  │                │<── S11 GTP-C ───────────────┤
│                  │                │  Create Session Res         │
│                  │                │  (UE IP: 10.45.0.X)         │
│                  │                │                │            │
│<─────────────────┴─── Attach ────┤                │            │
│                      Accept       │                │            │
│                   (w/ IP config)  │                │            │
│                  │                │                │            │
│─── Attach ──────────────────────>│                │            │
│    Complete      │                │                │            │
│                  │                │                │            │
│  [UE now has IP address and tun_srsue interface]   │            │
│                  │                │                │            │
```

**Key Points:**
- RACH: Random Access Channel procedure for initial access
- Authentication uses Milenage algorithm (USIM credentials)
- MME queries HSS for authentication vectors
- SGW/PGW allocates IP address from data APN pool
- UE creates `tun_srsue` interface with assigned IP

### 2. SIP Registration Flow

```
UE (SIP UA)              tun_srsue           Kamailio P/I/S-CSCF
    │                        │                        │
    │─── REGISTER ───────────┼───────────────────────>│
    │    (no auth)           │                        │
    │                        │                        ├─ Check auth_db
    │                        │                        │  (no credentials)
    │                        │                        │
    │<── 401 Unauthorized ───┼────────────────────────┤
    │    WWW-Authenticate:   │                        │
    │    Digest nonce="..."  │                        │
    │    realm="ims.localdomain"                      │
    │                        │                        │
    │  [Client computes MD5 response]                 │
    │   ha1 = MD5(user:realm:password)                │
    │   ha2 = MD5(method:uri)                         │
    │   response = MD5(ha1:nonce:ha2)                 │
    │                        │                        │
    │─── REGISTER ───────────┼───────────────────────>│
    │    Authorization:      │                        │
    │    Digest response="..."│                       │
    │                        │                        ├─ auth_check()
    │                        │                        │  queries MySQL
    │                        │                        │  validates response
    │                        │                        │
    │                        │                        ├─ save("location")
    │                        │                        │  stores contact in
    │                        │                        │  usrloc database
    │                        │                        │
    │<── 200 OK ─────────────┼────────────────────────┤
    │                        │                        │
    │  [Registration complete - UE is reachable]      │
    │                        │                        │
```

**Key Points:**
- Two-step authentication: challenge (401) then authenticated request
- SIP Digest MD5 authentication (not 3GPP AKA)
- Kamailio stores contact binding in `usrloc` memory
- Registration typically expires after 3600 seconds
- Our testbed measures: challenge response ~6ms, auth ~12ms

### 3. SIP INVITE Call Flow (Simplified)

```
UE1 (Caller)      Kamailio         UE2 (Callee)
    │                 │                 │
    │─── INVITE ─────>│                 │
    │   (SDP offer)   │                 │
    │                 ├─ lookup("location")
    │                 │  finds UE2 contact
    │                 │                 │
    │                 │─── INVITE ─────>│
    │                 │                 │
    │                 │<── 180 Ringing ─┤
    │<── 180 Ringing ─┤                 │
    │                 │                 │
    │                 │<── 200 OK ──────┤
    │<── 200 OK ──────┤   (SDP answer)  │
    │                 │                 │
    │─── ACK ────────────────────────────>│
    │                 │                 │
    │ [RTP Media Session Established]   │
    │<═══════════ RTP Media ═══════════>│
    │                 │                 │
    │─── BYE ────────>│                 │
    │                 │─── BYE ────────>│
    │                 │<── 200 OK ──────┤
    │<── 200 OK ──────┤                 │
    │                 │                 │
```

**Key Points:**
- SDP (Session Description Protocol) negotiates media parameters
- In production, RTP would carry voice packets
- Kamailio acts as SIP proxy, does not handle RTP
- Media flows peer-to-peer (or through media server in production)

---

## Design Decisions

### 1. Why ZMQ Virtual Radio?

**Decision:** Use ZMQ-based I/Q sample transport instead of real RF hardware.

**Rationale:**
- No need for expensive SDR hardware (USRP, bladeRF)
- Eliminates RF interference and propagation issues
- Reproducible results without environmental factors
- Easy to run on standard laptop/VM
- Same protocol stack as real LTE - only PHY layer is virtualized

**Trade-offs:**
- Cannot test real RF conditions
- No over-the-air testing
- Limited to single-host deployment

### 2. Why Single-Host Architecture?

**Decision:** Run all components on one machine using localhost addresses.

**Rationale:**
- Simplifies setup for academic environment
- No need for multiple VMs or physical machines
- Easy to debug with all logs in one place
- Follows Open5GS and srsRAN default configurations
- Sufficient for demonstrating VoLTE call flows

**Trade-offs:**
- Not representative of real network topology
- Cannot test distributed system characteristics
- Single point of failure

### 3. Why SIP Digest Instead of 3GPP AKA?

**Decision:** Use SIP Digest MD5 authentication instead of full 3GPP IMS authentication.

**Rationale:**
- 3GPP AKA requires Diameter Cx interface between S-CSCF and HSS
- Open5GS HSS doesn't expose Cx interface (only S6a for LTE MME)
- Kamailio would need additional modules (cdp, cdp_avp, ims_auth)
- Adds significant complexity for academic demonstration
- SIP Digest achieves the same goal (authenticated registration)
- Students can focus on call flows rather than authentication protocol details

**Trade-offs:**
- Not production-ready IMS architecture
- Cannot demonstrate full IMS security model
- Requires separate subscriber database in Kamailio

**Why This Is Acceptable:**
- Project goal: demonstrate VoLTE call setup and measure SIP delays
- Educational focus: understanding component integration
- Authentication still occurs - just different mechanism
- Core concepts (CSCF roles, SIP registration) are preserved

### 4. Why Dual APN on Same Interface?

**Decision:** Configure two IP addresses on `ogstun` for data and IMS APNs.

**Rationale:**
- Production VoLTE uses separate bearers for data and IMS
- Demonstrates network slicing concept
- Allows isolation of IMS traffic for measurement
- Simple to implement with secondary IP address
- Kamailio can bind specifically to IMS address

**Trade-offs:**
- Both APNs share same physical interface
- No QoS differentiation between bearers
- Simplified compared to real multi-bearer PDN

### 5. Why Network Namespace Was Removed?

**Decision:** UE creates `tun_srsue` in default namespace instead of dedicated `ue1` namespace.

**Rationale:**
- srsUE cannot create network namespaces without `CAP_NET_ADMIN` capability
- Even with sudo, namespace creation fails
- Unnecessary complexity for single-UE testbed
- Default namespace works fine with proper routing

**Trade-offs:**
- Cannot easily test multiple UEs simultaneously
- All interfaces visible in default namespace

### 6. Why Absolute Paths in Configs?

**Decision:** Use absolute paths for `sib.conf` and `rr.conf` in `enb.conf`.

**Rationale:**
- Relative paths depend on working directory
- Script execution changes CWD unpredictably
- Absolute paths guarantee config files are found
- Prevents "file not found" errors

**Lesson Learned:**
- Initially used relative paths - caused eNB to load wrong configs
- Led to TAC mismatch and S1 Setup failures
- Always use absolute paths in production configs

### 7. Why Automated Demo Script?

**Decision:** Create comprehensive `volte-demo.sh` instead of manual testing.

**Rationale:**
- Repeatable results for academic evaluation
- Eliminates human error in test execution
- Generates timestamped results for comparison
- Includes retry logic for robustness
- Provides packet captures for analysis
- Professional presentation for colleagues

**Features:**
- Health checks before starting
- Automated UE attachment polling
- Performance measurement
- Packet capture and analysis
- Timestamped result directories

---

## Performance Characteristics

### Expected Timings

| Operation | Typical Duration |
|-----------|------------------|
| UE Cell Search | 1-2 seconds |
| RACH Procedure | 10-50 ms |
| RRC Connection Setup | 50-200 ms |
| NAS Attach (with auth) | 500-1500 ms |
| S1 Setup | 10-100 ms |
| PDN Connectivity | 200-500 ms |
| **Total UE Attachment** | **2-4 seconds** |
| SIP Challenge (401) | 5-10 ms |
| SIP Authentication (200 OK) | 10-20 ms |
| **Total SIP Registration** | **15-30 ms** |

### Bottlenecks

1. **ZMQ Transport:** Adds minimal overhead (~1-2 ms) compared to real RF
2. **MongoDB HSS Queries:** Database lookup adds 5-10 ms to authentication
3. **Kamailio MySQL Auth:** Database query adds 3-5 ms per SIP transaction
4. **Kernel Routing:** Negligible overhead (<1 ms) for TUN interface routing

### Scalability Limits

This single-host testbed can handle:
- 1 eNB (single cell)
- 1-5 UEs (limited by CPU and ZMQ port conflicts)
- ~100 SIP registrations/second (Kamailio limit on standard hardware)
- ~50 concurrent RRC connections (eNB memory limit)

---

## Integration Points

### Open5GS ↔ srsRAN

**Interface:** S1-AP (control) + GTP-U (data)

**Configuration Requirements:**
- MME address must match in `enb.conf`
- PLMN (MCC/MNC) must match
- TAC must match
- Security algorithms must align

**Common Issues:**
- "Unknown PLMN" - MCC/MNC mismatch
- "Cannot find Served TAI" - TAC mismatch
- "S1 Setup failed" - MME address unreachable

### Open5GS ↔ Kamailio

**Interface:** IP routing via `ogstun`

**Configuration Requirements:**
- PGW must route IMS APN (10.46.0.0/16) to `ogstun`
- Kamailio must listen on IMS APN address (10.46.0.1)
- IP forwarding must be enabled
- UE must be able to reach 10.46.0.1 from its assigned IP

**Common Issues:**
- "Destination unreachable" - IP forwarding disabled
- "Connection refused" - Kamailio not listening on correct interface

### srsRAN ↔ Application

**Interface:** TUN interface (`tun_srsue`)

**Configuration Requirements:**
- UE must successfully attach to get IP address
- TUN interface must be created by srsUE
- Kernel routing must direct traffic to `ogstun`

**Common Issues:**
- "Failed to setup GW interface" - Permission issue creating TUN
- "No route to host" - Kernel routing not configured

---

## Summary

This architecture demonstrates a complete VoLTE system with:
- Proper separation of RAN, EPC, and IMS layers
- Standards-based interfaces (S1-AP, GTP, SIP)
- Simplified authentication for educational purposes
- Automated testing and measurement
- Realistic protocol flows

While simplified compared to production deployments, it preserves the essential characteristics of VoLTE systems and provides a solid foundation for learning LTE and IMS concepts.
