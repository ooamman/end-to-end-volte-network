# Technical Details

This document provides an in-depth technical breakdown of every component, configuration file, and integration point in the VoLTE IMS testbed. Use this as a reference when troubleshooting or modifying the system.

## Table of Contents

1. [Open5GS Setup and Configuration](#open5gs-setup-and-configuration)
2. [srsRAN Setup and Configuration](#srsran-setup-and-configuration)
3. [Kamailio Setup and Configuration](#kamailio-setup-and-configuration)
4. [Network Configuration](#network-configuration)
5. [Integration and Testing](#integration-and-testing)

---

## Open5GS Setup and Configuration

Open5GS provides the EPC (Evolved Packet Core) network functions. Version 2.7.6 was used in this testbed.

### Installation

Open5GS was installed from the official PPA:

```bash
sudo add-apt-repository ppa:open5gs/latest
sudo apt update
sudo apt install open5gs
```

This installs all EPC components as systemd services:
- `open5gs-mmed` - MME daemon
- `open5gs-sgwcd` - SGW Control plane
- `open5gs-sgwud` - SGW User plane
- `open5gs-hssd` - HSS daemon
- `open5gs-pcrfd` - PCRF daemon
- `open5gs-smfd` - SMF daemon
- `open5gs-upfd` - UPF daemon

### MME Configuration

**File:** `/etc/open5gs/mme.yaml`

The MME is the control plane entity that handles UE attach, authentication, and mobility management.

#### Critical Configuration Sections

**Network Identity (PLMN):**

```yaml
mme:
    freeDiameter: /etc/freeDiameter/mme.conf
    s1ap:
      - addr: 127.0.0.2    # S1-AP listening address
    gtpc:
      - addr: 127.0.0.2    # GTP-C address for SGW communication
    gummei:
      plmn_id:
        mcc: 001           # Must match eNB and UE
        mnc: 01            # Must match eNB and UE
      mme_gid: 2
      mme_code: 1
    tai:                   # Tracking Area Identity
      plmn_id:
        mcc: 001
        mnc: 01
      tac: 7               # CRITICAL: Must match rr.conf in srsRAN
```

**Why TAC=7?**
- TAC (Tracking Area Code) identifies the geographical area served by the eNB
- eNB announces TAC=7 in its SIB1 broadcast
- MME must have TAC=7 in its served TAI list
- Mismatch causes "Cannot find Served TAI" error during S1 Setup

**Security Algorithms:**

```yaml
    security:
        integrity_order : [ EIA2, EIA1, EIA0 ]
        ciphering_order : [ EEA0, EEA1, EEA2 ]
```

- **EIA** = EPS Integrity Algorithm (NAS/RRC message integrity)
- **EEA** = EPS Encryption Algorithm (user plane encryption)
- **Order matters**: MME proposes algorithms in this order, UE selects one
- **EEA0/EIA0** = null algorithms (no encryption/integrity) - acceptable for testing

**S1-AP Interface:**

The S1-AP interface connects eNB to MME for control plane signaling:
- **Listen address:** 127.0.0.2:36412 (standard S1-AP port)
- **Protocol:** SCTP (Stream Control Transmission Protocol)
- **Purpose:** Carries RRC messages, paging, handover commands

**GTP-C Interface:**

The GTP-C interface connects MME to SGW for session management:
- **Address:** 127.0.0.2:2123
- **Protocol:** GTP Control Plane (GTPv2-C)
- **Purpose:** Create/modify/delete bearer requests

#### Restart MME After Changes

```bash
sudo systemctl restart open5gs-mmed
sudo journalctl -u open5gs-mmed -f    # Monitor logs
```

### HSS Configuration

**File:** `/etc/open5gs/hss.yaml`

The HSS stores subscriber data and generates authentication vectors.

#### MongoDB Backend

```yaml
hss:
    freeDiameter: /etc/freeDiameter/hss.conf

db_uri: mongodb://localhost/open5gs
```

- **Database:** `open5gs` (created automatically)
- **Collection:** `subscribers`
- **Interface:** S6a Diameter to MME

#### Open5GS WebUI

The Open5GS WebUI provides a graphical interface for subscriber management, making it easier to add/edit/delete subscribers compared to manual MongoDB commands.

**Access:** `http://<your-ip>:9999/`
- Example: `http://192.168.16.1:9999/`
- Binds to your host IP address
- Port 9999 by default

**Default Credentials:**
- Username: `admin`
- Password: `1423`

**Installation (if not already installed):**

```bash
# Clone Open5GS repository
cd ~
git clone https://github.com/open5gs/open5gs.git
cd open5gs/webui

# Install dependencies
npm install

# Run WebUI
npm run dev
```

The WebUI will start and display:
```
> open5gs-webui@1.0.0 dev
> node server/index.js

Open5GS WebUI listening on http://0.0.0.0:9999
```

**Adding Subscribers via WebUI:**

1. Open `http://<your-ip>:9999/` in browser
2. Login with admin/1423
3. Navigate to "Subscribers" page
4. Click "+" button to add new subscriber
5. Fill in details:
   - **IMSI:** 001010000000001 (15 digits)
   - **Subscriber Key (K):** 465B5CE8B199B49FAA5F0A2EE238A6BC
   - **Operator Key (OPc):** E8ED289DEBA952E4283B54E88E6183CA
   - **APN:** internet
6. Click "Save"

The WebUI automatically inserts the subscriber into MongoDB with proper formatting, which is much easier than manual database insertion.

**Running WebUI as Service (Optional):**

To keep WebUI running permanently:

```bash
# Create systemd service
sudo nano /etc/systemd/system/open5gs-webui.service
```

```ini
[Unit]
Description=Open5GS WebUI
After=network.target

[Service]
Type=simple
User=open5gs
WorkingDirectory=/home/open5gs/open5gs/webui
ExecStart=/usr/bin/node server/index.js
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable open5gs-webui
sudo systemctl start open5gs-webui
```

#### Subscriber Database Schema

Each subscriber document in MongoDB contains:

```json
{
  "_id": ObjectId("..."),
  "imsi": "001010000000001",
  "security": {
    "k": "465B5CE8B199B49FAA5F0A2EE238A6BC",      // 128-bit key
    "opc": "E8ED289DEBA952E4283B54E88E6183CA",    // Operator code
    "amf": "8000",                                 // Authentication Management Field
    "sqn": NumberLong(32)                          // Sequence number (for replay protection)
  },
  "ambr": {
    "downlink": { "value": 1, "unit": 3 },        // 1 Gbps
    "uplink": { "value": 1, "unit": 3 }
  },
  "slice": [
    {
      "sst": 1,                                    // Slice/Service Type
      "default_indicator": true,
      "session": [
        {
          "name": "internet",                      // APN name
          "type": 3,                                // IPv4
          "qos": {
            "index": 9,                             // QCI (QoS Class Identifier)
            "arp": {
              "priority_level": 8,
              "pre_emption_capability": 1,
              "pre_emption_vulnerability": 1
            }
          },
          "ambr": {
            "downlink": { "value": 1, "unit": 3 },
            "uplink": { "value": 1, "unit": 3 }
          }
        }
      ]
    }
  ],
  "__v": 0
}
```

**Key Fields Explained:**

- **IMSI:** International Mobile Subscriber Identity (15 digits)
  - Format: MCC (3) + MNC (2-3) + MSIN (remaining)
  - Example: 001-01-0000000001
  
- **K:** Master subscriber key (shared secret with USIM)
  - Used in Milenage algorithm for authentication
  - Must match UE configuration
  
- **OPc:** Derived operator code
  - Computed from K and OP (operator key)
  - Used in authentication vector generation
  
- **AMF:** Authentication Management Field
  - Typically 0x8000 for standard authentication
  
- **SQN:** Sequence number for replay protection
  - Increments with each authentication
  - Prevents reuse of old authentication vectors

#### Adding Subscribers via MongoDB

```bash
mongo open5gs

db.subscribers.insert({
    "imsi": "001010000000001",
    "security": {
        "k": "465B5CE8B199B49FAA5F0A2EE238A6BC",
        "opc": "E8ED289DEBA952E4283B54E88E6183CA",
        "amf": "8000"
    },
    "ambr": {
        "downlink": {"value": 1, "unit": 3},
        "uplink": {"value": 1, "unit": 3}
    },
    "slice": [{
        "sst": 1,
        "default_indicator": true,
        "session": [{
            "name": "internet",
            "type": 3,
            "qos": {
                "index": 9,
                "arp": {
                    "priority_level": 8,
                    "pre_emption_capability": 1,
                    "pre_emption_vulnerability": 1
                }
            },
            "ambr": {
                "downlink": {"value": 1, "unit": 3},
                "uplink": {"value": 1, "unit": 3}
            }
        }]
    }]
})
```

### SGW/PGW Configuration

The SGW and PGW handle user plane data forwarding.

**File:** `/etc/open5gs/sgwc.yaml`, `/etc/open5gs/sgwu.yaml`, `/etc/open5gs/upf.yaml`

#### Key Configuration

Default configuration works fine, but verify:

**SGW-C:**
```yaml
sgwc:
    gtpc:
      - addr: 127.0.0.3    # GTP-C address
    pfcp:
      - addr: 127.0.0.3    # PFCP to SGW-U
```

**SGW-U:**
```yaml
sgwu:
    pfcp:
      - addr: 127.0.0.6    # PFCP listening address
    gtpu:
      - addr: 127.0.0.6    # GTP-U for data plane
```

**UPF (acts as PGW-U):**
```yaml
upf:
    pfcp:
      - addr: 127.0.0.7
    gtpu:
      - addr: 127.0.0.7
    subnet:
      - addr: 10.45.0.1/16    # Data APN subnet
      - addr: 10.46.0.1/16    # IMS APN subnet (manually added to ogstun)
```

The `subnet` configuration tells UPF to create the `ogstun` TUN interface with address 10.45.0.1/16. The IMS subnet (10.46.0.1/16) must be added manually.

### PCRF Configuration

**File:** `/etc/open5gs/pcrf.yaml`

PCRF provides policy control. Default configuration is sufficient:

```yaml
pcrf:
    freeDiameter: /etc/freeDiameter/pcrf.conf

db_uri: mongodb://localhost/open5gs
```

### Service Management

```bash
# Start all services
sudo systemctl start open5gs-mmed
sudo systemctl start open5gs-sgwcd open5gs-sgwud
sudo systemctl start open5gs-upfd open5gs-smfd
sudo systemctl start open5gs-hssd open5gs-pcrfd

# Enable auto-start on boot
sudo systemctl enable open5gs-*

# Check status
systemctl list-units "open5gs*"

# View logs
sudo journalctl -u open5gs-mmed -f
```

---

## srsRAN Setup and Configuration

srsRAN provides software-defined RAN components: eNodeB and UE. Build commit: 1fab3df86.

### Installation

srsRAN was compiled from source with ZMQ support:

```bash
sudo apt install -y build-essential cmake libfftw3-dev libmbedtls-dev \
                    libboost-program-options-dev libconfig++-dev libsctp-dev \
                    libzmq3-dev

git clone https://github.com/srsran/srsRAN_4G.git
cd srsRAN_4G
mkdir build && cd build
cmake ../ -DENABLE_ZMQ=ON
make -j$(nproc)
sudo make install
sudo ldconfig
```

**Key Dependency:** `libzmq3-dev` enables ZMQ virtual radio.

### eNodeB Configuration

**File:** `/home/open5gs/srsran-config/enb.conf`

#### Main Configuration Section

```ini
[enb]
enb_id = 0x19B              # 20-bit eNB identifier (decimal 411)
mcc = 001                   # Must match MME and UE
mnc = 01                    # Must match MME and UE
mme_addr = 127.0.0.2        # MME S1-AP address
gtp_bind_addr = 127.0.1.1   # Local address for GTP-U tunnel endpoint
s1c_bind_addr = 127.0.1.1   # Local address for S1-AP
s1c_bind_port = 0           # 0 = any available port
n_prb = 50                  # 50 PRBs = 10 MHz bandwidth
```

**Network Resource Blocks (PRBs):**
- 6 PRBs = 1.4 MHz
- 15 PRBs = 3 MHz
- 25 PRBs = 5 MHz
- **50 PRBs = 10 MHz** ← Used in testbed
- 75 PRBs = 15 MHz
- 100 PRBs = 20 MHz

#### Configuration Files Section

```ini
[enb_files]
sib_config = /home/open5gs/srsran-config/sib.conf   # ABSOLUTE PATH REQUIRED
rr_config  = /home/open5gs/srsran-config/rr.conf    # ABSOLUTE PATH REQUIRED
rb_config = /etc/srsran/rb.conf                      # Can use system default
```

**Critical Lesson:** Always use absolute paths. Relative paths caused the eNB to load the wrong configuration files (from /etc/srsran/), which had TAC=1 instead of TAC=7, causing S1 Setup failures.

#### RF Configuration (ZMQ)

```ini
[rf]
dl_earfcn = 3350            # Downlink EARFCN (determines frequency)
tx_gain = 80                # Transmit gain in dB
rx_gain = 40                # Receive gain in dB

device_name = zmq
device_args = fail_on_disconnect=true,tx_port=tcp://*:2000,rx_port=tcp://localhost:2001,id=enb,base_srate=23.04e6
```

**EARFCN (E-UTRA Absolute Radio Frequency Channel Number):**
- Maps to actual RF frequency
- EARFCN 3350 (Band 7):
  - Downlink: 2680 MHz
  - Uplink: 2560 MHz (automatically calculated)

**ZMQ Device Arguments:**
- `fail_on_disconnect=true`: Crash if UE disconnects (ensures clean shutdown)
- `tx_port=tcp://*:2000`: Broadcast I/Q samples on port 2000
- `rx_port=tcp://localhost:2001`: Listen for I/Q samples on port 2001
- `id=enb`: Identifier for logging
- `base_srate=23.04e6`: Base sample rate (23.04 MHz, LTE standard)

#### Expert Settings

```ini
[expert]
rrc_inactivity_timer = 600000    # 10 minutes (prevents premature disconnection)
```

### Radio Resource Configuration

**File:** `/home/open5gs/srsran-config/rr.conf`

This file defines cell-specific parameters.

#### Cell List

```ini
cell_list =
(
  {
    rf_port = 0;           # RF port index (0 for single cell)
    cell_id = 0x01;        # Cell ID (8-bit)
    tac = 0x0007;          # TAC = 7 (MUST MATCH MME)
    pci = 1;               # Physical Cell ID (0-503)
    root_seq_idx = 204;    # PRACH root sequence index
    dl_earfcn = 3350;      # Must match enb.conf
    ho_active = false;     # Handover disabled (single cell)
  }
);
```

**Critical Parameter:** `tac = 0x0007`
- Hexadecimal representation of TAC 7
- Announced in SIB1 broadcast
- MME checks this during S1 Setup
- Must match `/etc/open5gs/mme.yaml` tai.tac value

#### MAC Configuration

```ini
mac_cnfg =
{
  phr_cnfg =                    # Power Headroom Report
  {
    dl_pathloss_change = "dB3";
    periodic_phr_timer = 50;
    prohibit_phr_timer = 0;
  };
  ulsch_cnfg =                  # Uplink Shared Channel
  {
    max_harq_tx = 4;            # Max HARQ retransmissions
    periodic_bsr_timer = 20;    # Buffer Status Report timer
    retx_bsr_timer = 320;
  };
  time_alignment_timer = -1;    # Disabled
};
```

#### PHY Configuration

```ini
phy_cnfg =
{
  phich_cnfg =                  # Physical HARQ Indicator Channel
  {
    duration = "Normal";
    resources = "1/6";
  };

  pusch_cnfg_ded =              # Physical Uplink Shared Channel
  {
    beta_offset_ack_idx = 6;    # ACK/NACK power offset
    beta_offset_ri_idx = 6;     # Rank Indicator power offset
    beta_offset_cqi_idx = 6;    # CQI power offset
  };
  
  sched_request_cnfg =          # Scheduling Request
  {
    dsr_trans_max = 64;         # Max SR transmissions
    period = 20;                # SR periodicity (ms)
    subframe = [1];             # SR subframe
  };
  
  cqi_report_cnfg =             # Channel Quality Indicator
  {
    mode = "periodic";
    simultaneousAckCQI = true;
    period = 40;                # CQI report period (ms)
    subframe = [0];
  };
};
```

### System Information Blocks (SIB)

**File:** `/home/open5gs/srsran-config/sib.conf`

SIBs are broadcast by eNB to inform UEs about cell configuration.

#### SIB1 (Master Information Block)

```ini
sib1 =
{
  intra_freq_reselection = "Allowed";
  q_rx_lev_min = -65;           # Minimum required RX level (dBm)
  p_max = 3;                    # Max UE transmit power (dBm)
  freq_band_indicator = 7;      # LTE Band 7
  sched_info =
  (
    {
      si_periodicity = 16;      # SIB scheduling periodicity (ms)
      si_mapping_info = [];     # No additional SIBs
    }
  );
  system_info_value_tag = 0;
};
```

#### SIB2 (Radio Resource Common Configuration)

```ini
sib2 =
{
  rr_config_common_sib =
  {
    rach_cnfg =                 # Random Access Channel
    {
      num_ra_preambles = 52;    # Number of PRACH preambles
      preamble_init_rx_target_pwr = -104;  # Initial RX target power
      pwr_ramping_step = 6;     # Power ramping step (dB)
      preamble_trans_max = 10;  # Max preamble transmissions
      ra_resp_win_size = 10;    # Random Access Response window
      mac_con_res_timer = 64;   # Contention resolution timer
      max_harq_msg3_tx = 4;     # Max HARQ transmissions for Msg3
    };
    
    prach_cnfg =                # PRACH configuration
    {
      root_seq_idx = 204;       # Must match rr.conf
      prach_cnfg_info =
      {
        high_speed_flag = false;
        prach_config_idx = 3;   # PRACH configuration index
        prach_freq_offset = 2;  # Frequency offset in PRBs
        zero_correlation_zone_config = 11;
      };
    };
    
    pdsch_cnfg =                # Physical Downlink Shared Channel
    {
      p_b = 1;                  # Power boosting
      rs_power = 20;            # Reference signal power (dBm)
    };
    
    pusch_cnfg =                # Physical Uplink Shared Channel
    {
      n_sb = 1;                 # Number of subbands
      hopping_mode = "inter-subframe";
      pusch_hopping_offset = 2;
      enable_64_qam = false;    # 64-QAM disabled for simplicity
      ul_rs =
      {
        cyclic_shift = 0;
        group_assignment_pusch = 0;
        group_hopping_enabled = false;
        sequence_hopping_enabled = false;
      };
    };
    
    ul_pwr_ctrl =               # Uplink Power Control
    {
      p0_nominal_pusch = -85;   # Target received power (dBm)
      alpha = 0.7;              # Path loss compensation factor
      p0_nominal_pucch = -107;
      delta_flist_pucch =
      {
        format_1 = 0;
        format_1b = 3;
        format_2 = 1;
        format_2a = 2;
        format_2b = 2;
      };
      delta_preamble_msg3 = 6;
    };
  };

  ue_timers_and_constants =
  {
    t300 = 2000;                # RRC connection establishment timer
    t301 = 100;                 # RRC connection re-establishment timer
    t310 = 200;                 # Out-of-sync timer
    n310 = 1;                   # Out-of-sync counter
    t311 = 10000;               # Post-failure timer
    n311 = 1;                   # In-sync counter
  };

  time_alignment_timer = "INFINITY";  # No realignment needed (ZMQ)
};
```

### UE Configuration

**File:** `/home/open5gs/srsran-config/ue.conf`

#### RF Configuration

```ini
[rf]
freq_offset = 0
tx_gain = 80
device_name = zmq
device_args = tx_port=tcp://*:2001,rx_port=tcp://localhost:2000,id=ue,base_srate=23.04e6
```

**Note:** Ports are reversed from eNB:
- UE TX (2001) → eNB RX (2001)
- UE RX (2000) ← eNB TX (2000)

#### RAT Configuration

```ini
[rat.eutra]
dl_earfcn = 3350            # Must match eNB
```

#### USIM Configuration

```ini
[usim]
mode = soft                 # Software USIM (no physical SIM card)
algo = milenage             # 3GPP authentication algorithm
opc  = E8ED289DEBA952E4283B54E88E6183CA
k    = 465B5CE8B199B49FAA5F0A2EE238A6BC
imsi = 001010000000001
imei = 353490069873319
```

**Critical:** K and OPc must match HSS database entry.

#### NAS Configuration

```ini
[nas]
apn = internet              # Must match HSS APN configuration
apn_protocol = ipv4         # IPv4 only
```

#### Gateway Configuration

```ini
[gw]
# Network namespace disabled - creates tun_srsue in default namespace
#netns = ue1
```

**Why Commented Out:**
- srsUE cannot create network namespaces without `CAP_NET_ADMIN`
- Even with sudo, namespace creation fails
- Default namespace works fine with proper routing
- Simplifies single-UE testing

#### Logging Configuration

```ini
[log]
all_level = warning         # Reduces log verbosity
phy_lib_level = none        # Disables PHY library debug
all_hex_limit = 32          # Limits hex dumps
filename = /tmp/ue.log
file_max_size = -1          # Unlimited log file size
```

### Running srsRAN Components

#### Starting eNodeB

```bash
sudo srsenb /home/open5gs/srsran-config/enb.conf < /dev/null > /tmp/enb.log 2>&1 &
```

**Important flags:**
- `sudo`: Required for network operations
- `< /dev/null`: Redirects stdin to prevent "Closing stdin thread" exit
- `> /tmp/enb.log 2>&1`: Captures stdout and stderr
- `&`: Runs in background

Expected output in log:
```
==== eNodeB started ===
Type <t> to view trace
Setting frequency: DL=2680.0 Mhz, UL=2560.0 MHz for cc_idx=0 nof_prb=50
```

#### Starting UE

```bash
sudo srsue /home/open5gs/srsran-config/ue.conf < /dev/null > /tmp/ue.log 2>&1 &
```

Expected output in log:
```
Attaching UE...
Found Cell:  Mode=FDD, PCI=1, PRB=50, Ports=1, CP=Normal, CFO=-0.2 KHz
Found PLMN:  Id=00101, TAC=7
Random Access Transmission: seq=39, tti=341, ra-rnti=0x2
RRC Connected
Random Access Complete.     c-rnti=0x46, ta=0
Network attach successful. IP: 10.45.0.X
```

#### Checking Attachment

```bash
# Check if tun_srsue interface exists
ip addr show tun_srsue

# Expected output:
# inet 10.45.0.X/24 scope global tun_srsue
```

---

## Kamailio Setup and Configuration

Kamailio acts as the IMS core (P-CSCF/I-CSCF/S-CSCF combined). Version 5.7.4 was used.

### Installation

```bash
sudo apt install -y kamailio kamailio-mysql-modules mysql-server
```

### Database Setup

#### Create Kamailio Database

```bash
sudo kamdbctl create
```

This creates:
- Database: `kamailio`
- Tables: `subscriber`, `location`, `version`, etc.

#### Create MySQL User

```bash
sudo mysql -u root -p

CREATE USER 'kamailio'@'localhost' IDENTIFIED BY 'kamailiorw';
GRANT ALL PRIVILEGES ON kamailio.* TO 'kamailio'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

#### Add SIP Subscribers

```bash
# Add subscriber for UE1
sudo kamctl add 001010000000001@ims.localdomain test123

# Verify
mysql -u kamailio -pkamailiorw kamailio -e "SELECT username, domain, ha1 FROM subscriber;"
```

**Subscriber Table Schema:**

```sql
CREATE TABLE `subscriber` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL DEFAULT '',
  `domain` varchar(64) NOT NULL DEFAULT '',
  `password` varchar(64) NOT NULL DEFAULT '',
  `ha1` varchar(128) NOT NULL DEFAULT '',      -- MD5(username:domain:password)
  `ha1b` varchar(128) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  UNIQUE KEY `account_idx` (`username`,`domain`)
);
```

**ha1 Calculation:**
```
ha1 = MD5(username:realm:password)
Example: MD5("001010000000001@ims.localdomain:ims.localdomain:test123")
```

### Kamailio Configuration

**File:** `/etc/kamailio/kamailio.cfg`

#### Global Parameters

```
#!KAMAILIO

debug=2                     # Log level (2 = info)
log_stderror=no            # Log to syslog, not stderr
log_facility=LOG_LOCAL0
fork=yes                   # Run as daemon
children=4                 # Worker processes

listen=udp:10.46.0.1:5060  # CRITICAL: Listen on IMS APN address
port=5060
```

**Why 10.46.0.1?**
- This is the IMS APN address on ogstun
- UE can reach this address through its PDN connection
- Separates IMS traffic from data traffic

#### Module Loading

```
loadmodule "tm.so"          # Transaction module
loadmodule "sl.so"          # Stateless replies
loadmodule "rr.so"          # Record-routing
loadmodule "pv.so"          # Pseudo-variables
loadmodule "maxfwd.so"      # Max-forwards checking
loadmodule "usrloc.so"      # User location database
loadmodule "registrar.so"   # REGISTER handling
loadmodule "textops.so"     # Text operations
loadmodule "siputils.so"    # SIP utilities
loadmodule "xlog.so"        # Logging
loadmodule "sanity.so"      # Message sanity checks
loadmodule "db_mysql.so"    # MySQL database
loadmodule "auth.so"        # Authentication framework
loadmodule "auth_db.so"     # Database authentication
```

#### Module Parameters

**Authentication:**

```
modparam("auth_db", "db_url", "mysql://kamailio:kamailiorw@localhost/kamailio?socket=/var/run/mysqld/mysqld.sock")
modparam("auth_db", "user_column", "username")
modparam("auth_db", "password_column", "password")
modparam("auth_db", "calculate_ha1", yes)
modparam("auth_db", "load_credentials", "")
```

**Critical:** MySQL 8.0+ requires `?socket=/var/run/mysqld/mysqld.sock` parameter in the connection URL. Without this, Kamailio fails with "Can't connect to local MySQL server through socket '/tmp/mysql.sock'".

**User Location:**

```
modparam("usrloc", "db_url", "mysql://kamailio:kamailiorw@localhost/kamailio?socket=/var/run/mysqld/mysqld.sock")
modparam("usrloc", "db_mode", 2)    # Write-through cache
```

- **db_mode=2**: Writes to database immediately, keeps in-memory copy
- Location database stores current contact bindings (where UE can be reached)

**Registrar:**

```
modparam("registrar", "method_filtering", 1)
```

- Enables method filtering in REGISTER handling

#### Routing Logic

**Main Request Route:**

```
request_route {
    
    # Sanity checks
    if (!mf_process_maxfwd_header("10")) {
        sl_send_reply("483", "Too Many Hops");
        exit;
    }

    if (!sanity_check()) {
        exit;
    }

    # Record routing for dialog-forming requests
    if (is_method("INVITE|SUBSCRIBE")) {
        record_route();
    }

    # Handle REGISTER
    if (is_method("REGISTER")) {
        route(REGISTER);
        exit;
    }

    # Handle calls
    if (is_method("INVITE|ACK|BYE|CANCEL|UPDATE|MESSAGE|PRACK|REFER|NOTIFY")) {
        route(CALL);
        exit;
    }
}
```

**REGISTER Route:**

```
route[REGISTER] {
    xlog("L_INFO", "REGISTER from $fu\n");
    
    # Check authentication
    if (!auth_check("$fd", "subscriber", "1")) {
        auth_challenge("$fd", "0");    # Send 401 Unauthorized
        exit;
    }

    # Save location
    if (!save("location")) {
        sl_reply_error();
    }
}
```

**How Authentication Works:**

1. UE sends REGISTER without credentials
2. `auth_check()` fails (no Authorization header)
3. `auth_challenge()` sends 401 with:
   ```
   WWW-Authenticate: Digest realm="ims.localdomain", nonce="..."
   ```
4. UE computes response:
   ```
   ha1 = MD5(user:realm:password)
   ha2 = MD5(REGISTER:sip:ims.localdomain)
   response = MD5(ha1:nonce:ha2)
   ```
5. UE sends REGISTER with Authorization header
6. `auth_check()` queries MySQL, validates response
7. `save("location")` stores contact in usrloc database
8. 200 OK sent to UE

**CALL Route:**

```
route[CALL] {
    xlog("L_INFO", "Call from $fu to $ru\n");
    
    # Look up callee location
    if (!lookup("location")) {
        sl_send_reply("404", "Not Found");
        exit;
    }

    # Forward request
    t_relay();
}
```

- `lookup("location")`: Queries usrloc for callee's contact URI
- `t_relay()`: Statefully forwards the request

### Service Management

```bash
# Start Kamailio
sudo systemctl start kamailio

# Enable auto-start
sudo systemctl enable kamailio

# Check status
sudo systemctl status kamailio

# View logs
sudo journalctl -u kamailio -f

# Check if listening
sudo netstat -tulpn | grep 5060
```

### Testing Kamailio

```bash
# Check MySQL connection
mysql -u kamailio -pkamailiorw kamailio -e "SELECT * FROM subscriber;"

# Monitor SIP messages
sudo tcpdump -i any port 5060 -nn -A

# Send test REGISTER
# (Use sip_register_test.py script)
```

---

## Network Configuration

### IP Forwarding

Enable IP forwarding to allow routing between ogstun and tun_srsue:

```bash
# Temporary
sudo sysctl -w net.ipv4.ip_forward=1

# Permanent
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

**Why Required:**
- UE (tun_srsue) needs to reach Kamailio (ogstun)
- Traffic must be routed through the kernel
- Without forwarding, packets are dropped

### ogstun Interface Configuration

The ogstun interface is created by Open5GS UPF and needs dual APN addresses:

```bash
# Data APN (created automatically by UPF)
# 10.45.0.1/16 - already present

# IMS APN (must be added manually)
sudo ip addr add 10.46.0.1/16 dev ogstun 2>/dev/null || true

# Verify
ip addr show ogstun
```

Expected output:
```
ogstun: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UNKNOWN
    link/none 
    inet 10.45.0.1/16 scope global ogstun
    inet 10.46.0.1/16 scope global ogstun
```

**Note:** This configuration is lost on reboot. Use `initialize-system.sh` to restore it.

### Routing Table

Check routing:

```bash
ip route show
```

Should include:
```
10.45.0.0/16 dev ogstun proto kernel scope link src 10.45.0.1
10.46.0.0/16 dev ogstun proto kernel scope link src 10.46.0.1
```

This ensures:
- Traffic to 10.45.0.0/16 goes to ogstun (UE data)
- Traffic to 10.46.0.0/16 goes to ogstun (IMS)

### Firewall Considerations

If using firewall (ufw, iptables), allow:

```bash
# Allow GTP-U
sudo iptables -A INPUT -p udp --dport 2152 -j ACCEPT

# Allow SCTP (S1-AP)
sudo iptables -A INPUT -p sctp -j ACCEPT

# Allow SIP
sudo iptables -A INPUT -p udp --dport 5060 -j ACCEPT

# Allow traffic on ogstun
sudo iptables -A FORWARD -i ogstun -j ACCEPT
sudo iptables -A FORWARD -o ogstun -j ACCEPT
```

---

## Integration and Testing

### Integration Checklist

Before running the demo, verify:

**Open5GS:**
- [ ] All services running: `systemctl status open5gs-*`
- [ ] MME TAC = 7
- [ ] Subscriber exists in HSS with correct K, OPc
- [ ] ogstun interface has both 10.45.0.1 and 10.46.0.1

**srsRAN:**
- [ ] eNB config uses absolute paths for sib.conf and rr.conf
- [ ] TAC in rr.conf = 0x0007
- [ ] PLMN matches MME (001-01)
- [ ] UE IMSI matches HSS subscriber

**Kamailio:**
- [ ] Service running
- [ ] MySQL connection works
- [ ] Subscriber exists in subscriber table
- [ ] Listening on 10.46.0.1:5060

**Network:**
- [ ] IP forwarding enabled
- [ ] ogstun has both APN addresses
- [ ] No firewall blocking S1-AP, GTP, SIP

### Testing Procedure

#### 1. Start Core Network

```bash
# Verify Open5GS services
systemctl status open5gs-mmed open5gs-sgwcd open5gs-sgwud open5gs-upfd open5gs-smfd open5gs-hssd

# Verify Kamailio
systemctl status kamailio
```

#### 2. Start eNodeB

```bash
sudo srsenb /home/open5gs/srsran-config/enb.conf < /dev/null > /tmp/enb.log 2>&1 &
ENB_PID=$!

# Wait 3 seconds
sleep 3

# Check if running
ps -p $ENB_PID

# Check logs
tail -20 /tmp/enb.log
```

Look for:
```
==== eNodeB started ===
Setting frequency: DL=2680.0 Mhz, UL=2560.0 MHz
```

#### 3. Start UE

```bash
sudo srsue /home/open5gs/srsran-config/ue.conf < /dev/null > /tmp/ue.log 2>&1 &
UE_PID=$!

# Wait for attachment (10 seconds)
sleep 10

# Check logs
tail -30 /tmp/ue.log
```

Look for:
```
Found Cell:  Mode=FDD, PCI=1, PRB=50, Ports=1, CP=Normal
Found PLMN:  Id=00101, TAC=7
Random Access Transmission: seq=39, tti=341, ra-rnti=0x2
RRC Connected
Random Access Complete.     c-rnti=0x46, ta=0
Network attach successful. IP: 10.45.0.X
```

#### 4. Verify Attachment

```bash
# Check tun_srsue interface
ip addr show tun_srsue

# Should show:
# inet 10.45.0.X/24 scope global tun_srsue

# Test connectivity to IMS
ping -c 2 10.46.0.1
```

#### 5. Run SIP Test

```bash
cd /home/open5gs
python3 sip_register_test.py
```

Expected output:
```
SIP REGISTER Authentication Test with Timing
...
✓ Received 401 Unauthorized (challenge)
✓ Received 200 OK - REGISTRATION SUCCESSFUL!

Total Registration Delay:      18.711 ms
```

#### 6. Packet Capture

```bash
# Start capture
sudo tcpdump -i any port 5060 -w /tmp/sip_test.pcap -nn &
TCPDUMP_PID=$!

# Run test
python3 sip_register_test.py

# Stop capture
sudo kill $TCPDUMP_PID

# Analyze
wireshark /tmp/sip_test.pcap
```

### Automated Demo Script

The `volte-demo.sh` script automates all the above steps:

```bash
sudo ./volte-demo.sh
```

It performs:
1. Service health checks
2. eNB startup
3. UE startup  
4. Attachment polling (with retry)
5. Packet capture
6. SIP registration test
7. Performance analysis
8. Result archiving

Results saved to `/home/open5gs/demo/<timestamp>/`:
- `summary.txt` - Performance metrics
- `sip_capture.pcap` - Wireshark file
- `enb_output.log` - eNB logs
- `ue_output.log` - UE logs
- `registration_test_output.log` - Test output

---

## Performance Tuning

### Reducing SIP Registration Delay

Current: ~18ms

**Optimizations:**
1. Use prepared statements in Kamailio MySQL queries
2. Increase Kamailio worker processes (`children=8`)
3. Use in-memory usrloc (`db_mode=0`)
4. Disable unnecessary Kamailio modules
5. Use localhost for Kamailio (avoid network stack)

### Reducing UE Attachment Time

Current: ~2-4 seconds

**Factors:**
- Cell search time (~1s)
- Random access backoff
- Authentication vector generation (MongoDB query)
- GTP tunnel setup

**Optimizations:**
1. Pre-warm MongoDB connections
2. Reduce RACH contention window
3. Optimize UE cell search parameters

---

## Summary

This testbed demonstrates a complete VoLTE system with:
- Open5GS providing all EPC functions
- srsRAN simulating RAN with virtual radio
- Kamailio providing simplified IMS core
- Automated testing and measurement

All components are configured to work together using standard 3GPP interfaces, with the exception of using SIP Digest instead of full 3GPP AKA for authentication.
