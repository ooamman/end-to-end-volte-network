# Troubleshooting Guide

This guide covers common issues encountered during setup and operation of the VoLTE IMS testbed, along with their solutions. All issues listed here were actually encountered and resolved during development.

## Table of Contents

1. [Kamailio Issues](#kamailio-issues)
2. [srsRAN Issues](#srsran-issues)
3. [Open5GS Issues](#open5gs-issues)
4. [Network Configuration Issues](#network-configuration-issues)
5. [Integration Issues](#integration-issues)
6. [Demo Script Issues](#demo-script-issues)

---

## Kamailio Issues

### Issue 1: MySQL Connection Failed

**Symptom:**
```
ERROR: db_mysql [km_my_con.c:109]: db_mysql_new_connection(): driver error: Can't connect to local MySQL server through socket '/tmp/mysql.sock'
```

**Cause:**
- MySQL 8.0+ uses a different socket path
- Default Kamailio connection string looks for `/tmp/mysql.sock`
- Actual socket is at `/var/run/mysqld/mysqld.sock`

**Solution:**

Add socket parameter to database URL in `/etc/kamailio/kamailio.cfg`:

```
modparam("auth_db", "db_url", "mysql://kamailio:kamailiorw@localhost/kamailio?socket=/var/run/mysqld/mysqld.sock")
modparam("usrloc", "db_url", "mysql://kamailio:kamailiorw@localhost/kamailio?socket=/var/run/mysqld/mysqld.sock")
```

Restart Kamailio:
```bash
sudo systemctl restart kamailio
```

### Issue 2: Kamailio Not Listening on IMS Interface

**Symptom:**
- SIP registration fails with "Connection refused"
- `netstat` shows Kamailio listening on 0.0.0.0:5060 instead of 10.46.0.1:5060

**Cause:**
- Default configuration uses `listen=udp:*:5060`
- Kamailio binds to all interfaces but UE can't reach it

**Solution:**

Specify exact listen address in `/etc/kamailio/kamailio.cfg`:

```
listen=udp:10.46.0.1:5060
```

Verify:
```bash
sudo systemctl restart kamailio
sudo netstat -tulpn | grep 5060
# Should show: udp 0 0 10.46.0.1:5060
```

### Issue 3: Authentication Always Fails (401)

**Symptom:**
- First REGISTER gets 401 (expected)
- Second REGISTER with credentials also gets 401
- Kamailio logs show: "auth_db: user not found"

**Cause:**
- Subscriber not added to Kamailio database
- Or realm mismatch in SIP URI

**Solution:**

Add subscriber:
```bash
sudo kamctl add 001010000000001@ims.localdomain test123
```

Verify:
```bash
mysql -u kamailio -pkamailiorw kamailio -e "SELECT username, domain FROM subscriber;"
```

Check realm matches:
- SIP URI: `sip:001010000000001@ims.localdomain`
- Domain must be `ims.localdomain`

---

## srsRAN Issues

### Issue 4: eNB S1 Setup Failed - "Unknown PLMN"

**Symptom:**
```
ERROR: S1 Setup Failure. S1SetupFailureIEs: Cause: misc=unknown-PLMN
```

**Cause:**
- PLMN mismatch between eNB and MME
- eNB sends MCC=001, MNC=01
- MME expects different values

**Solution:**

Verify PLMN configuration matches:

**eNB (`enb.conf`):**
```ini
mcc = 001
mnc = 01
```

**MME (`/etc/open5gs/mme.yaml`):**
```yaml
gummei:
  plmn_id:
    mcc: 001
    mnc: 01
tai:
  plmn_id:
    mcc: 001
    mnc: 01
```

Restart both:
```bash
sudo systemctl restart open5gs-mmed
sudo pkill srsenb
sudo srsenb /home/open5gs/srsran-config/enb.conf < /dev/null > /tmp/enb.log 2>&1 &
```

### Issue 5: eNB S1 Setup Failed - "Cannot find Served TAI"

**Symptom:**
```
ERROR: S1 Setup Failure. Cause: radioNetwork=unknown-TAC
```

**Cause:**
- TAC mismatch between eNB and MME
- eNB announces TAC=1 in SIB1
- MME is configured with TAC=7

**Root Cause of This Issue:**
- eNB config used relative paths: `sib_config = sib.conf`
- When launched from different directory, eNB loaded `/etc/srsran/sib.conf`
- System file had different configuration (TAC=1)
- Custom config has TAC=7

**Solution:**

Use absolute paths in `/home/open5gs/srsran-config/enb.conf`:

```ini
[enb_files]
sib_config = /home/open5gs/srsran-config/sib.conf
rr_config  = /home/open5gs/srsran-config/rr.conf
```

Verify TAC in `/home/open5gs/srsran-config/rr.conf`:

```ini
cell_list =
(
  {
    tac = 0x0007;     # TAC = 7 in hexadecimal
  }
);
```

Verify MME TAC in `/etc/open5gs/mme.yaml`:

```yaml
tai:
  plmn_id:
    mcc: 001
    mnc: 01
  tac: 7              # Must be decimal 7
```

### Issue 6: UE Process Exits Immediately After Start

**Symptom:**
- UE starts but dies after 2-3 seconds
- Log shows: "Closing stdin thread" then process exits
- No error messages

**Cause:**
- srsUE expects stdin to remain open
- When launched in background with `&`, stdin is closed
- UE interprets closed stdin as signal to exit gracefully

**Solution:**

Redirect stdin from `/dev/null`:

```bash
sudo srsue /home/open5gs/srsran-config/ue.conf < /dev/null > /tmp/ue.log 2>&1 &
```

This keeps stdin "open" but reading from null device.

Same fix applies to eNB:

```bash
sudo srsenb /home/open5gs/srsran-config/enb.conf < /dev/null > /tmp/enb.log 2>&1 &
```

### Issue 7: UE Fails to Create TUN Interface

**Symptom:**
```
Network attach successful. IP: 10.45.0.5
Failed to setup/configure GW interface
```

**Cause:**
- UE configured to create interface in network namespace (`netns = ue1`)
- srsUE cannot create namespaces even with sudo
- Missing `CAP_NET_ADMIN` capability

**Solution:**

Comment out netns in `/home/open5gs/srsran-config/ue.conf`:

```ini
[gw]
#netns = ue1          # Disabled - creates TUN in default namespace
```

Restart UE:
```bash
sudo pkill srsue
sudo srsue /home/open5gs/srsran-config/ue.conf < /dev/null > /tmp/ue.log 2>&1 &
```

Verify:
```bash
ip addr show tun_srsue
# Should show inet 10.45.0.X/24
```

### Issue 8: UE Cannot Find Cell

**Symptom:**
```
Attaching UE...
(hangs indefinitely, no cell found)
```

**Causes:**

1. **eNB not running:**
   ```bash
   ps aux | grep srsenb
   ```

2. **EARFCN mismatch:**
   - UE searches for EARFCN 3350
   - eNB broadcasting different EARFCN
   
   Verify in `enb.conf` and `ue.conf`:
   ```ini
   [rf]
   dl_earfcn = 3350
   ```

3. **ZMQ port conflict:**
   - Another process using port 2000 or 2001
   
   Check:
   ```bash
   sudo lsof -i :2000
   sudo lsof -i :2001
   ```

4. **eNB crashed after startup:**
   Check eNB logs:
   ```bash
   tail -50 /tmp/enb.log
   ```

**Solutions:**

Start eNB first, wait 5 seconds, then start UE:
```bash
sudo srsenb /home/open5gs/srsran-config/enb.conf < /dev/null > /tmp/enb.log 2>&1 &
sleep 5
sudo srsue /home/open5gs/srsran-config/ue.conf < /dev/null > /tmp/ue.log 2>&1 &
```

Kill processes holding ZMQ ports:
```bash
sudo lsof -ti:2000 | xargs -r sudo kill -9
sudo lsof -ti:2001 | xargs -r sudo kill -9
```

---

## Open5GS Issues

### Issue 9: UE Authentication Fails

**Symptom:**
- UE gets "Attach Reject" from MME
- MME logs show: "Authentication failure"

**Causes:**

1. **Subscriber not in HSS database**
2. **K or OPc mismatch between HSS and UE**
3. **IMSI mismatch**

**Solution:**

Verify subscriber exists:
```bash
mongo open5gs
db.subscribers.find({"imsi": "001010000000001"})
```

Check K and OPc match UE config:

**HSS (MongoDB):**
```json
{
  "imsi": "001010000000001",
  "security": {
    "k": "465B5CE8B199B49FAA5F0A2EE238A6BC",
    "opc": "E8ED289DEBA952E4283B54E88E6183CA"
  }
}
```

**UE (`ue.conf`):**
```ini
[usim]
k    = 465B5CE8B199B49FAA5F0A2EE238A6BC
opc  = E8ED289DEBA952E4283B54E88E6183CA
imsi = 001010000000001
```

### Issue 10: No Service Running

**Symptom:**
```bash
systemctl status open5gs-mmed
# Output: inactive (dead)
```

**Solution:**

Start all services:
```bash
sudo systemctl start open5gs-mmed
sudo systemctl start open5gs-sgwcd open5gs-sgwud
sudo systemctl start open5gs-upfd open5gs-smfd
sudo systemctl start open5gs-hssd open5gs-pcrfd

# Enable auto-start
sudo systemctl enable open5gs-*
```

Verify all running:
```bash
systemctl list-units "open5gs*" --all
```

### Issue 11: MongoDB Connection Failed

**Symptom:**
```
ERROR: Cannot connect to MongoDB at mongodb://localhost/open5gs
```

**Cause:**
- MongoDB service not running

**Solution:**

```bash
sudo systemctl start mongod
sudo systemctl enable mongod
sudo systemctl status mongod
```

---

## Network Configuration Issues

### Issue 12: UE Cannot Reach IMS (10.46.0.1)

**Symptom:**
```bash
ping -c 2 10.46.0.1
# Destination Host Unreachable
```

**Causes:**

1. **IMS APN address not added to ogstun:**
   ```bash
   ip addr show ogstun
   # Only shows 10.45.0.1/16, missing 10.46.0.1/16
   ```

2. **IP forwarding disabled:**
   ```bash
   sysctl net.ipv4.ip_forward
   # net.ipv4.ip_forward = 0
   ```

**Solutions:**

Add IMS address:
```bash
sudo ip addr add 10.46.0.1/16 dev ogstun
```

Enable IP forwarding:
```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

Make permanent:
```bash
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Issue 13: ogstun Interface Missing

**Symptom:**
```bash
ip addr show ogstun
# Device "ogstun" does not exist
```

**Cause:**
- Open5GS UPF not running
- UPF creates ogstun interface on startup

**Solution:**

Start UPF:
```bash
sudo systemctl start open5gs-upfd
sleep 2
ip addr show ogstun
```

### Issue 14: Firewall Blocking Traffic

**Symptom:**
- Services running but communication fails
- tcpdump shows packets but no responses

**Solution:**

Check firewall:
```bash
sudo iptables -L -n
sudo ufw status
```

Allow necessary traffic:
```bash
# Disable ufw temporarily for testing
sudo ufw disable

# Or add specific rules
sudo ufw allow 36412/sctp  # S1-AP
sudo ufw allow 2152/udp    # GTP-U
sudo ufw allow 5060/udp    # SIP
```

---

## Integration Issues

### Issue 15: SIP Registration Gets 404 Not Found

**Symptom:**
- REGISTER sent to 10.46.0.1:5060
- Response: "404 Not Found"

**Cause:**
- Kamailio not handling REGISTER method
- Route configuration missing

**Solution:**

Verify routing in `/etc/kamailio/kamailio.cfg`:

```
request_route {
    if (is_method("REGISTER")) {
        route(REGISTER);
        exit;
    }
}

route[REGISTER] {
    if (!auth_check("$fd", "subscriber", "1")) {
        auth_challenge("$fd", "0");
        exit;
    }
    
    if (!save("location")) {
        sl_reply_error();
    }
}
```

### Issue 16: Wrong Network Namespace in Demo Script

**Symptom:**
- Demo script reports "UE failed to attach"
- But UE actually attached successfully
- Script checks for IP in namespace `ue1` which doesn't exist

**Cause:**
- Script assumes UE creates namespace
- UE config has netns commented out
- Script still checking `sudo ip netns exec ue1 ip addr show`

**Solution:**

Update demo script to check default namespace:

```bash
# OLD (wrong):
if sudo ip netns exec ue1 ip addr show tun_srsue 2>/dev/null | grep -q "inet 10.45"; then

# NEW (correct):
if ip addr show tun_srsue 2>/dev/null | grep -q "inet 10.45"; then
```

---

## Demo Script Issues

### Issue 17: Demo Script Cannot Find Config Files

**Symptom:**
```
ERROR: eNB config not found: /home/open5gs/srsran-config/enb.conf
```

**Cause:**
- Config files in different location
- Script has hardcoded paths

**Solution:**

Update paths in `volte-demo.sh`:

```bash
ENB_CONFIG="/home/open5gs/srsran-config/enb.conf"
UE_CONFIG="/home/open5gs/srsran-config/ue.conf"
```

Or use relative paths:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENB_CONFIG="${SCRIPT_DIR}/srsran-config/enb.conf"
```

### Issue 18: Demo Script Hangs During Attachment Check

**Symptom:**
- Script polls for 30 seconds
- Never detects UE attachment
- UE actually attached (can see in UE logs)

**Causes:**

1. **Checking wrong interface:**
   - Script checks namespace that doesn't exist
   
2. **Timing issue:**
   - UE not given enough time before polling starts

**Solution:**

Add delay before polling:
```bash
start_ue
sleep 3    # Give UE time to start

check_ue_attachment
```

Fix interface check:
```bash
if ip addr show tun_srsue 2>/dev/null | grep -q "inet 10.45"; then
    local ue_ip=$(ip addr show tun_srsue | grep "inet 10.45" | awk '{print $2}' | cut -d'/' -f1)
    log_success "UE attached successfully with IP: $ue_ip"
fi
```

### Issue 19: Multiple Demo Runs Conflict

**Symptom:**
- Second demo run fails
- Error: "Address already in use" (ZMQ ports)
- Or: Processes from previous run still active

**Cause:**
- Previous eNB/UE processes not cleaned up
- ZMQ ports (2000, 2001) still bound

**Solution:**

Add thorough cleanup at demo start:

```bash
# Kill existing processes
sudo pkill -9 srsenb srsue 2>/dev/null
sudo killall -9 srsenb srsue 2>/dev/null

# Kill processes holding ZMQ ports
sudo lsof -ti:2000 | xargs -r sudo kill -9
sudo lsof -ti:2001 | xargs -r sudo kill -9

# Wait for cleanup
sleep 2
```

---

## Diagnostic Commands

### Check All Services

```bash
# Open5GS
systemctl list-units "open5gs*" --all

# Kamailio
systemctl status kamailio

# Network
ip addr show ogstun
sysctl net.ipv4.ip_forward

# Processes
ps aux | grep -E "srsenb|srsue|kamailio"
```

### Monitor Logs in Real-Time

```bash
# MME logs
sudo journalctl -u open5gs-mmed -f

# Kamailio logs
sudo journalctl -u kamailio -f

# eNB logs
tail -f /tmp/enb.log

# UE logs
tail -f /tmp/ue.log
```

### Capture Traffic

```bash
# S1-AP (SCTP)
sudo tcpdump -i lo sctp -w /tmp/s1ap.pcap

# GTP-U
sudo tcpdump -i any port 2152 -w /tmp/gtp.pcap

# SIP
sudo tcpdump -i any port 5060 -w /tmp/sip.pcap -nn -A

# All on ogstun
sudo tcpdump -i ogstun -w /tmp/ogstun.pcap
```

### Test Connectivity

```bash
# From host to IMS
ping -c 2 10.46.0.1

# From UE namespace (if using netns)
sudo ip netns exec ue1 ping -c 2 10.46.0.1

# Check if UE has IP
ip addr show tun_srsue
```

### Database Queries

```bash
# HSS subscribers
mongo open5gs --eval "db.subscribers.find().pretty()"

# Kamailio subscribers
mysql -u kamailio -pkamailiorw kamailio -e "SELECT * FROM subscriber;"

# Kamailio location (registered users)
mysql -u kamailio -pkamailiorw kamailio -e "SELECT * FROM location;"
```

---

## Reset Procedures

### Full System Reset

```bash
# Stop all processes
sudo pkill -9 srsenb srsue
sudo systemctl stop kamailio
sudo systemctl stop open5gs-*

# Clear logs
sudo rm -f /tmp/*.log /tmp/*.pcap

# Restart services
sudo systemctl start open5gs-mmed open5gs-sgwcd open5gs-sgwud
sudo systemctl start open5gs-upfd open5gs-smfd open5gs-hssd
sudo systemctl start kamailio

# Wait for services
sleep 5

# Verify network
sudo ip addr add 10.46.0.1/16 dev ogstun 2>/dev/null
sudo sysctl -w net.ipv4.ip_forward=1

# Run demo
sudo ./volte-demo.sh
```

### Reset Databases

```bash
# MongoDB (HSS)
mongo open5gs
db.subscribers.deleteMany({})
# Re-add subscribers

# MySQL (Kamailio)
mysql -u root -p
DROP DATABASE kamailio;
sudo kamdbctl create
# Re-add subscribers with kamctl
```

---

## Getting Help

If you encounter issues not covered here:

1. **Check logs** - Most issues leave traces in logs
2. **Verify configuration** - Compare with working configs in docs
3. **Test components individually** - Isolate the problem
4. **Check versions** - Ensure compatible versions of all components
5. **Review documentation** - [TECHNICAL_DETAILS.md](TECHNICAL_DETAILS.md) has comprehensive config info

**Common Mistakes:**
- Forgetting to use sudo
- Not waiting for services to start (add `sleep` commands)
- Mixing relative and absolute paths in configs
- Typos in IMSI, K, or OPc values
- Not restarting services after config changes
- Skipping network configuration steps

**When All Else Fails:**
```bash
# Nuclear option: restart everything
sudo reboot

# After reboot:
sudo ./initialize-system.sh
sudo ./volte-demo.sh
```
