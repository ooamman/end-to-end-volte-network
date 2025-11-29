# Quick Start Guide

This guide walks you through setting up the VoLTE IMS testbed from scratch on a fresh Ubuntu system. Each step includes the actual commands used and expected outcomes.

## System Requirements

**Hardware (Virtual Machine is fine):**
- 4 GB RAM minimum (8 GB recommended)
- 20 GB disk space
- 2+ CPU cores

**Software:**
- Ubuntu 24.04 LTS (tested) or Ubuntu 22.04/20.04
- Internet connection for package installation
- Root/sudo access

## Overview of Setup Steps

1. Install Open5GS (EPC core network)
2. Install srsRAN (RAN simulation)
3. Install Kamailio (IMS/SIP core)
4. **Clone this repository and install configurations**
5. Configure network interfaces
6. Configure subscriber database
7. Deploy and test

**Estimated setup time:** 30-45 minutes (with pre-configured files)

---

## Quick Install (For Users Cloning This Repo)

If you're setting up from this repository:

```bash
# 1. Install packages (Steps 1-3 below)
# 2. Clone the repository
git clone <repository-url>
cd volte-ims-testbed

# 3. Install all configurations automatically
sudo ./install-configs.sh

# This script will:
# - Backup your existing configs
# - Copy Open5GS configs to /etc/open5gs/
# - Copy Kamailio config to /etc/kamailio/
# - Verify all required packages are installed

# 4. Continue with network setup and subscriber configuration below
```

The install-configs.sh script handles all configuration file deployment. You only need to:
- Add subscribers via Open5GS WebUI
- Run initialize-system.sh for network setup
- Execute volte-demo.sh to test

**For detailed installation of packages, continue reading below.**

---

## Step 1: Install Open5GS

Open5GS provides the EPC core network components (MME, HSS, SGW, PGW, etc.).

### Add Open5GS PPA and Install

```bash
# Add Open5GS repository
sudo add-apt-repository ppa:open5gs/latest
sudo apt update

# Install Open5GS core network components
sudo apt install -y open5gs
```

This installs all core network functions. You should see services like:
- `open5gs-mmed` - MME
- `open5gs-sgwcd`, `open5gs-sgwud` - SGW
- `open5gs-hssd` - HSS
- `open5gs-pcrfd` - PCRF
- `open5gs-smfd` - SMF
- `open5gs-upfd` - UPF

### Verify Installation

```bash
# Check Open5GS version
open5gs-mmed --version

# Check services status
systemctl list-units "open5gs*" --all
```

Expected output: `Open5GS daemon v2.7.6` (or later)

All services should be `active (running)` after installation.

---

## Step 2: Install srsRAN

srsRAN provides the software-based eNodeB and UE for testing.

### Install Dependencies

```bash
sudo apt install -y build-essential cmake libfftw3-dev libmbedtls-dev \
                    libboost-program-options-dev libconfig++-dev libsctp-dev \
                    libzmq3-dev
```

### Build and Install srsRAN

```bash
# Clone srsRAN repository
cd ~
git clone https://github.com/srsran/srsRAN_4G.git
cd srsRAN_4G

# Build with ZMQ support (for virtual radio)
mkdir build
cd build
cmake ../ -DENABLE_ZMQ=ON
make -j$(nproc)
sudo make install
sudo ldconfig
```

### Verify Installation

```bash
# Check srsRAN version
srsenb --version
srsue --version
```

Expected: Version info showing srsRAN_4G build

---

## Step 3: Install Kamailio

Kamailio acts as the IMS core (P-CSCF/I-CSCF/S-CSCF).

### Install Kamailio with MySQL

```bash
# Install Kamailio and MySQL module
sudo apt install -y kamailio kamailio-mysql-modules mysql-server
```

### Initialize Kamailio Database

```bash
# Create Kamailio database and tables
sudo kamdbctl create
```

When prompted:
- MySQL root password: (set during MySQL installation or press Enter if none)
- Create database: `yes`
- Install presence tables: `no` (not needed for basic VoLTE)
- Install extra tables: `yes`

This creates the `kamailio` database with necessary tables.

### Create Kamailio MySQL User

```bash
# Log into MySQL
sudo mysql -u root -p

# Create user and grant privileges
CREATE USER 'kamailio'@'localhost' IDENTIFIED BY 'kamailiorw';
GRANT ALL PRIVILEGES ON kamailio.* TO 'kamailio'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

### Verify Kamailio Installation

```bash
# Check version
kamailio -v

# Check MySQL connection
mysql -u kamailio -pkamailiorw kamailio -e "SHOW TABLES;"
```

Expected: Version 5.7.x and a list of database tables

---

## Step 4: Configure Network Interfaces

### Enable IP Forwarding

This allows traffic routing between the EPC and IMS networks.

```bash
# Enable IP forwarding permanently
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Configure Dual APN on ogstun Interface

The `ogstun` interface is created by Open5GS and needs two IP addresses for data and IMS APNs.

```bash
# Wait for Open5GS to create ogstun (start services first)
sudo systemctl start open5gs-mmed
sleep 2

# Add IMS APN address
sudo ip addr add 10.46.0.1/16 dev ogstun 2>/dev/null || true

# Verify both addresses exist
ip addr show ogstun
```

Expected output should show:
```
inet 10.45.0.1/16 scope global ogstun    (Data APN - already configured by Open5GS)
inet 10.46.0.1/16 scope global ogstun    (IMS APN - just added)
```

**Note:** The IMS address needs to be re-added after each reboot. The `initialize-system.sh` script handles this automatically.

---

## Step 5: Configure Open5GS

### Edit MME Configuration

The MME needs proper PLMN and TAC settings.

```bash
sudo nano /etc/open5gs/mme.yaml
```

Key settings to verify/set:

```yaml
mme:
    freeDiameter: /etc/freeDiameter/mme.conf
    s1ap:
      - addr: 127.0.0.2
    gtpc:
      - addr: 127.0.0.2
    gummei:
      plmn_id:
        mcc: 001
        mnc: 01
      mme_gid: 2
      mme_code: 1
    tai:
      plmn_id:
        mcc: 001
        mnc: 01
      tac: 7
    security:
        integrity_order : [ EIA2, EIA1, EIA0 ]
        ciphering_order : [ EEA0, EEA1, EEA2 ]
```

Critical values:
- **TAC: 7** (must match srsRAN configuration)
- **MCC: 001, MNC: 01** (PLMN must match UE and eNB)

Restart MME after changes:

```bash
sudo systemctl restart open5gs-mmed
```

### Edit HSS Configuration (Optional)

The HSS configuration is usually fine by default, but verify:

```bash
sudo nano /etc/open5gs/hss.yaml
```

Ensure MongoDB connection is present:

```yaml
hss:
    freeDiameter: /etc/freeDiameter/hss.conf

db_uri: mongodb://localhost/open5gs
```

---

## Step 6: Configure Subscriber in HSS

Add a test subscriber to the HSS database.

### Using Open5GS WebUI (Recommended)

```bash
# Install WebUI dependencies
sudo apt install -y nodejs npm

# Install and run WebUI
cd ~
git clone https://github.com/open5gs/open5gs.git
cd open5gs/webui
npm install
npm run dev
```

The WebUI will start on port 9999. Access it at `http://<your-ip>:9999/`

For example, if your IP is 192.168.16.1, access: `http://192.168.16.1:9999/`

Default credentials: `admin` / `1423`

Add subscriber:
- Click the "+" button to add new subscriber
- **IMSI:** 001010000000001
- **Subscriber Key (K):** 465B5CE8B199B49FAA5F0A2EE238A6BC
- **Operator Key (OPc):** E8ED289DEBA952E4283B54E88E6183CA
- **APN:** internet (leave other fields as default)
- Click "Save"

You can add multiple subscribers (e.g., 001010000000002 for a second UE) using the same K and OPc values or different ones for testing.

### Using MongoDB CLI (Alternative)

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
        "downlink": 1000000000,
        "uplink": 1000000000
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
                "downlink": 1000000000,
                "uplink": 1000000000
            }
        }]
    }]
})
```

---

## Step 7: Configure Kamailio

### Backup Default Config

```bash
sudo cp /etc/kamailio/kamailio.cfg /etc/kamailio/kamailio.cfg.backup
```

### Create Basic IMS Configuration

Create a minimal Kamailio config for IMS/VoLTE:

```bash
sudo nano /etc/kamailio/kamailio.cfg
```

Paste the following configuration:

```
#!KAMAILIO

# Basic VoLTE IMS Configuration
# Simplified P-CSCF/I-CSCF/S-CSCF

####### Global Parameters #########

debug=2
log_stderror=no
log_facility=LOG_LOCAL0
fork=yes
children=4

listen=udp:10.46.0.1:5060
port=5060

####### Modules Section ########

loadmodule "tm.so"
loadmodule "sl.so"
loadmodule "rr.so"
loadmodule "pv.so"
loadmodule "maxfwd.so"
loadmodule "usrloc.so"
loadmodule "registrar.so"
loadmodule "textops.so"
loadmodule "siputils.so"
loadmodule "xlog.so"
loadmodule "sanity.so"
loadmodule "ctl.so"
loadmodule "cfg_rpc.so"
loadmodule "mi_rpc.so"
loadmodule "db_mysql.so"
loadmodule "auth.so"
loadmodule "auth_db.so"

####### Module Parameters ########

# Database connection - IMPORTANT: Use socket parameter for MySQL 8.0+
modparam("auth_db", "db_url", "mysql://kamailio:kamailiorw@localhost/kamailio?socket=/var/run/mysqld/mysqld.sock")
modparam("auth_db", "user_column", "username")
modparam("auth_db", "password_column", "password")
modparam("auth_db", "calculate_ha1", yes)
modparam("auth_db", "load_credentials", "")

modparam("usrloc", "db_url", "mysql://kamailio:kamailiorw@localhost/kamailio?socket=/var/run/mysqld/mysqld.sock")
modparam("usrloc", "db_mode", 2)

modparam("registrar", "method_filtering", 1)

####### Routing Logic ########

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

# REGISTER handling
route[REGISTER] {
    xlog("L_INFO", "REGISTER from $fu\n");
    
    if (!auth_check("$fd", "subscriber", "1")) {
        auth_challenge("$fd", "0");
        exit;
    }

    if (!save("location")) {
        sl_reply_error();
    }
}

# Call routing
route[CALL] {
    xlog("L_INFO", "Call from $fu to $ru\n");
    
    if (!lookup("location")) {
        sl_send_reply("404", "Not Found");
        exit;
    }

    t_relay();
}
```

**Key configuration points:**
- **Listen address:** 10.46.0.1:5060 (IMS APN)
- **MySQL socket parameter:** Required for MySQL 8.0+ compatibility
- **Authentication:** SIP Digest with `auth_db` module

### Fix MySQL Socket Issue (Critical)

Modern MySQL uses a different socket path. Update the database URL:

```bash
# Verify socket location
ls -la /var/run/mysqld/mysqld.sock
```

If socket exists, the config above is correct. If Kamailio fails to start, check:

```bash
sudo journalctl -u kamailio -f
```

Look for "Can't connect to local MySQL server" errors.

### Add SIP Subscriber to Kamailio

```bash
# Add subscriber for UE1
sudo kamctl add 001010000000001@ims.localdomain test123

# Verify subscriber
mysql -u kamailio -pkamailiorw kamailio -e "SELECT * FROM subscriber;"
```

Expected output: One row with username `001010000000001@ims.localdomain`

### Start Kamailio

```bash
sudo systemctl restart kamailio
sudo systemctl enable kamailio
sudo systemctl status kamailio
```

Kamailio should be `active (running)`.

---

## Step 8: Configure srsRAN

### Create Configuration Directory

```bash
mkdir -p ~/srsran-config
cd ~/srsran-config
```

### Create eNB Configuration

Create `enb.conf`:

```bash
nano enb.conf
```

Paste the following (adjust paths as needed):

```ini
[enb]
enb_id = 0x19B
mcc = 001
mnc = 01
mme_addr = 127.0.0.2
gtp_bind_addr = 127.0.1.1
s1c_bind_addr = 127.0.1.1
n_prb = 50

[enb_files]
sib_config = /home/<your_username>/srsran-config/sib.conf
rr_config = /home/<your_username>/srsran-config/rr.conf
rb_config = /etc/srsran/rb.conf

[rf]
dl_earfcn = 3350
tx_gain = 80
rx_gain = 40

device_name = zmq
device_args = fail_on_disconnect=true,tx_port=tcp://*:2000,rx_port=tcp://localhost:2001,id=enb,base_srate=23.04e6

[expert]
rrc_inactivity_timer = 600000
```

**Important:** Use absolute paths for `sib_config` and `rr_config` (replace `<your_username>` with actual username).

### Create RR Configuration

Create `rr.conf`:

```bash
nano rr.conf
```

```ini
mac_cnfg =
{
  phr_cnfg = 
  {
    dl_pathloss_change = "dB3";
    periodic_phr_timer = 50;
    prohibit_phr_timer = 0;
  };
  ulsch_cnfg = 
  {
    max_harq_tx = 4;
    periodic_bsr_timer = 20;
    retx_bsr_timer = 320;
  };
  
  time_alignment_timer = -1;
};

phy_cnfg =
{
  phich_cnfg = 
  {
    duration = "Normal";
    resources = "1/6";
  };

  pusch_cnfg_ded =
  {
    beta_offset_ack_idx = 6;
    beta_offset_ri_idx = 6;
    beta_offset_cqi_idx = 6;
  };
  
  sched_request_cnfg =
  {
    dsr_trans_max = 64;
    period = 20;
    subframe = [1];
  };
  
  cqi_report_cnfg =
  {
    mode = "periodic";
    simultaneousAckCQI = true;
    period = 40;
    subframe = [0];
  };
};

cell_list =
(
  {
    rf_port = 0;
    cell_id = 0x01;
    tac = 0x0007;
    pci = 1;
    root_seq_idx = 204;
    dl_earfcn = 3350;
    
    ho_active = false;
  }
);
```

**Critical:** `tac = 0x0007` must match MME configuration (TAC 7).

### Create SIB Configuration

Create `sib.conf`:

```bash
nano sib.conf
```

```ini
sib1 =
{
  intra_freq_reselection = "Allowed";
  q_rx_lev_min = -65;
  p_max = 3;
  freq_band_indicator = 7;
  sched_info =
  (
    {
      si_periodicity = 16;
      si_mapping_info = []; 
    }
  );
  system_info_value_tag = 0;
};

sib2 =
{
  rr_config_common_sib =
  {
    rach_cnfg = 
    {
      num_ra_preambles = 52;
      preamble_init_rx_target_pwr = -104;
      pwr_ramping_step = 6;
      preamble_trans_max = 10;
      ra_resp_win_size = 10;
      mac_con_res_timer = 64;
      max_harq_msg3_tx = 4;
    };
    bcch_cnfg = 
    {
      modification_period_coeff = 16;
    };
    pcch_cnfg =
    {
      default_paging_cycle = 32;
      nB = "1";
    };
    prach_cnfg =
    {
      root_seq_idx = 204;
      prach_cnfg_info =
      {
        high_speed_flag = false;
        prach_config_idx = 3;
        prach_freq_offset = 2;
        zero_correlation_zone_config = 11;
      };
    };
    pdsch_cnfg = 
    {
      p_b = 1;
      rs_power = 20;
    };
    pusch_cnfg =
    {
      n_sb = 1;
      hopping_mode = "inter-subframe";
      pusch_hopping_offset = 2;
      enable_64_qam = false;
      ul_rs =
      {
        cyclic_shift = 0;
        group_assignment_pusch = 0;
        group_hopping_enabled = false; 
        sequence_hopping_enabled = false; 
      };
    };
    pucch_cnfg =
    {
      delta_pucch_shift = 2;
      n_rb_cqi = 2;
      n_cs_an = 0;
      n1_pucch_an = 12;
    };
    ul_pwr_ctrl =
    {
      p0_nominal_pusch = -85;
      alpha = 0.7;
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
    ul_cp_length = "len1";
  };

  ue_timers_and_constants =
  {
    t300 = 2000;
    t301 = 100;
    t310 = 200;
    n310 = 1;
    t311 = 10000;
    n311 = 1;
  };

  freqInfo =
  {
    ul_carrier_freq_present = false; 
    additional_spectrum_emission = 1;
  };

  time_alignment_timer = "INFINITY";
};
```

### Create UE Configuration

Create `ue.conf`:

```bash
nano ue.conf
```

```ini
[rf]
freq_offset = 0
tx_gain = 80
device_name = zmq
device_args = tx_port=tcp://*:2001,rx_port=tcp://localhost:2000,id=ue,base_srate=23.04e6

[rat.eutra]
dl_earfcn = 3350

[pcap]
enable = none
mac_filename = /tmp/ue_mac.pcap
nas_filename = /tmp/ue_nas.pcap

[log]
all_level = warning
phy_lib_level = none
all_hex_limit = 32
filename = /tmp/ue.log
file_max_size = -1

[usim]
mode = soft
algo = milenage
opc  = E8ED289DEBA952E4283B54E88E6183CA
k    = 465B5CE8B199B49FAA5F0A2EE238A6BC
imsi = 001010000000001
imei = 353490069873319

[rrc]

[nas]
apn = internet
apn_protocol = ipv4

[gw]
# Network namespace disabled - creates tun_srsue in default namespace
#netns = ue1

[gui]
enable = false
```

**Important:** The `netns` line is commented out. This allows the UE to create the TUN interface without needing network namespace capabilities.

---

## Step 9: Clone This Repository

Now that all components are installed, clone this repository to get the automation scripts and test tools.

```bash
cd ~
git clone <repository-url> volte-ims-testbed
cd volte-ims-testbed

# Copy your configs (or use the provided ones)
cp -r ~/srsran-config ./srsran-config
```

Make scripts executable:

```bash
chmod +x volte-demo.sh
chmod +x initialize-system.sh
chmod +x cleanup-demo.sh
```

---

## Step 10: Initialize and Test

### Run System Initialization

```bash
sudo ./initialize-system.sh
```

This script:
- Verifies all services are running
- Adds the IMS APN address to ogstun
- Checks IP forwarding
- Validates network connectivity

### Run the Demo

```bash
sudo ./volte-demo.sh
```

The demo script will:
1. Check prerequisites
2. Verify all services are running
3. Start eNodeB
4. Start UE
5. Wait for UE attachment (polls for ~2-4 seconds)
6. Start packet capture
7. Run SIP registration test
8. Display performance results
9. Save everything to a timestamped directory

Expected output:
```
[SUCCESS] UE attached successfully with IP: 10.45.0.X
[SUCCESS] SIP registration test completed
Total Registration Delay: ~18-40 ms
```

### Check Results

```bash
# List demo runs
ls -lh demo/

# View latest results
cat demo/<timestamp>/summary.txt

# Analyze packet capture in Wireshark
wireshark demo/<timestamp>/sip_capture.pcap
```

---

## Verification Checklist

After setup, verify each component:

### Open5GS Core Network
```bash
# All services should be active
systemctl status open5gs-mmed
systemctl status open5gs-sgwcd
systemctl status open5gs-sgwud
systemctl status open5gs-upfd
systemctl status open5gs-smfd
systemctl status open5gs-hssd
systemctl status open5gs-pcrfd

# Check MME is listening on S1-AP port
sudo netstat -tulpn | grep 36412
```

### Kamailio IMS
```bash
# Kamailio should be active
systemctl status kamailio

# Check SIP port
sudo netstat -tulpn | grep 5060

# Check database connection
mysql -u kamailio -pkamailiorw kamailio -e "SELECT username FROM subscriber;"
```

### Network Configuration
```bash
# Check ogstun interface has both APNs
ip addr show ogstun | grep "inet 10"

# Should show:
# inet 10.45.0.1/16 (Data)
# inet 10.46.0.1/16 (IMS)

# Check IP forwarding
sysctl net.ipv4.ip_forward
# Should output: net.ipv4.ip_forward = 1
```

### srsRAN Components
```bash
# Start eNB manually for testing
sudo srsenb ~/srsran-config/enb.conf

# In another terminal, start UE
sudo srsue ~/srsran-config/ue.conf

# Check if tun_srsue interface is created
ip addr show tun_srsue
```

If the UE attaches successfully, you'll see "Network attach successful. IP: 10.45.0.X" in the UE output.

---

## Next Steps

Once everything is working:

1. **Explore the demo results** - Each run creates logs, packet captures, and performance summaries
2. **Modify configurations** - Try different TACs, PLMNs, or QoS settings
3. **Read the technical details** - See [TECHNICAL_DETAILS.md](TECHNICAL_DETAILS.md) for in-depth explanations
4. **Troubleshoot issues** - Refer to [TROUBLESHOOTING.md](TROUBLESHOOTING.md) if you encounter problems

---

## Common Post-Setup Tasks

### Adding Additional Subscribers

```bash
# In HSS (MongoDB)
mongo open5gs
db.subscribers.insert({
    "imsi": "001010000000002",
    "security": {
        "k": "YOUR_K_VALUE_HERE",
        "opc": "YOUR_OPC_VALUE_HERE",
        "amf": "8000"
    },
    "ambr": {"downlink": 1000000000, "uplink": 1000000000},
    "slice": [...]  # Same as first subscriber
})

# In Kamailio
sudo kamctl add 001010000000002@ims.localdomain test123
```

### Restarting After Reboot

```bash
# Run the initialization script
sudo ./initialize-system.sh

# All services should auto-start, but verify
systemctl status open5gs-mmed
systemctl status kamailio
```

### Cleaning Up Processes

```bash
# Kill all RAN processes
sudo pkill -f srsenb
sudo pkill -f srsue

# Or use the cleanup script
sudo ./cleanup-demo.sh
```

---

## Summary

You now have a complete VoLTE IMS testbed with:
- Open5GS providing the EPC core
- srsRAN simulating the radio access network
- Kamailio providing SIP/IMS functionality
- Automated testing and performance measurement

For detailed technical explanations, see the other documentation files in the `docs/` directory.
