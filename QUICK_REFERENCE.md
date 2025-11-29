# Quick Reference Card

One-page reference for common operations and configurations.

---

## Essential Commands

### Starting the Testbed
```bash
sudo ./initialize-system.sh    # Run after reboot
sudo ./volte-demo.sh           # Automated demo
```

### Manual Control
```bash
# Start eNB
sudo srsenb srsran-config/enb.conf < /dev/null > /tmp/enb.log 2>&1 &

# Start UE (wait 5s after eNB)
sudo srsue srsran-config/ue.conf < /dev/null > /tmp/ue.log 2>&1 &

# Stop everything
sudo ./cleanup-demo.sh
```

### Testing
```bash
python3 sip_register_test.py   # Test SIP registration
python3 volte_call_test.py     # Test call setup
```

---

## Service Management

```bash
# Check all services
systemctl status open5gs-* kamailio

# Restart core network
sudo systemctl restart open5gs-mmed open5gs-sgwcd open5gs-sgwud
sudo systemctl restart open5gs-upfd open5gs-smfd open5gs-hssd
sudo systemctl restart kamailio
```

---

## Network Verification

```bash
# Check interfaces
ip addr show ogstun tun_srsue

# Verify IP forwarding
sysctl net.ipv4.ip_forward

# Test connectivity
ping 10.46.0.1                 # IMS from host
ip addr show tun_srsue         # Check UE IP
```

---

## Key Configuration Values

| Parameter | Value | File |
|-----------|-------|------|
| **PLMN** | 001-01 | enb.conf, mme.yaml, ue.conf |
| **TAC** | 7 | rr.conf (0x0007), mme.yaml |
| **IMSI** | 001010000000001 | ue.conf, HSS DB |
| **K** | 465B5CE8B199B49FAA5F0A2EE238A6BC | ue.conf, HSS DB |
| **OPc** | E8ED289DEBA952E4283B54E88E6183CA | ue.conf, HSS DB |
| **APN** | internet | ue.conf, HSS DB |
| **Data APN** | 10.45.0.0/16 | UPF, ogstun |
| **IMS APN** | 10.46.0.0/16 | ogstun, Kamailio |
| **EARFCN** | 3350 | enb.conf, ue.conf |
| **Bandwidth** | 10 MHz (50 PRBs) | enb.conf |

---

## Important Ports

| Port | Protocol | Service |
|------|----------|---------|
| 2000 | TCP | ZMQ eNB TX |
| 2001 | TCP | ZMQ UE TX |
| 5060 | UDP | SIP (Kamailio) |
| 36412 | SCTP | S1-AP (MME) |
| 2152 | UDP | GTP-U |
| 2123 | UDP | GTP-C |

---

## Log Locations

```bash
# System services
sudo journalctl -u open5gs-mmed -f
sudo journalctl -u kamailio -f

# RAN components
tail -f /tmp/enb.log
tail -f /tmp/ue.log

# Demo results
ls -lh demo/
cat demo/<timestamp>/summary.txt
```

---

## Packet Capture

```bash
# SIP only
sudo tcpdump -i any port 5060 -w sip.pcap -A

# All VoLTE traffic
sudo tcpdump -i ogstun -w volte.pcap

# Analyze
wireshark sip.pcap
```

---

## Database Access

```bash
# HSS (MongoDB)
mongo open5gs
db.subscribers.find({"imsi": "001010000000001"}).pretty()

# Kamailio (MySQL)
mysql -u kamailio -pkamailiorw kamailio
SELECT * FROM subscriber;
SELECT * FROM location;
```

---

## Common Issues

| Symptom | Likely Cause | Quick Fix |
|---------|--------------|-----------|
| eNB exits immediately | stdin closed | Use `< /dev/null` |
| S1 Setup failed | TAC mismatch | Check rr.conf and mme.yaml |
| UE can't find cell | eNB not running | Start eNB first, wait 5s |
| SIP 401 always | No subscriber | `sudo kamctl add USER@ims.localdomain PASS` |
| No ogstun interface | UPF not running | `sudo systemctl start open5gs-upfd` |
| Can't reach IMS | IP forwarding off | `sudo sysctl -w net.ipv4.ip_forward=1` |

---

## File Paths

```
/home/open5gs/
├── README.md                  # Start here
├── docs/QUICKSTART.md        # Setup guide
├── volte-demo.sh             # Main demo
├── sip_register_test.py      # Testing tool
└── srsran-config/
    ├── enb.conf              # eNB config
    ├── ue.conf               # UE config
    ├── rr.conf               # TAC here
    └── sib.conf              # SIB params

/etc/open5gs/
├── mme.yaml                  # TAC here
└── upf.yaml                  # APN subnet

/etc/kamailio/
└── kamailio.cfg              # SIP config
```

---

## Performance Targets

| Metric | Target | Typical |
|--------|--------|---------|
| SIP Registration | < 30 ms | 18-20 ms |
| UE Attachment | < 5 s | 2-4 s |
| S1 Setup | < 100 ms | 10-50 ms |

---

## Emergency Reset

```bash
# Nuclear option
sudo pkill -9 srsenb srsue
sudo systemctl restart open5gs-* kamailio
sudo reboot

# After reboot
sudo ./initialize-system.sh
sudo ./volte-demo.sh
```

---

## Documentation Index

- **README.md** - Overview and quick start
- **docs/QUICKSTART.md** - Complete setup from scratch
- **docs/ARCHITECTURE.md** - System design and flows
- **docs/TECHNICAL_DETAILS.md** - Every config explained
- **docs/TROUBLESHOOTING.md** - Problem solving
- **PROJECT_SUMMARY.md** - Academic summary

---

## Contact Points

**When debugging:**
1. Check logs first
2. Verify configs match this card
3. See docs/TROUBLESHOOTING.md
4. Check component individually
5. Review docs/TECHNICAL_DETAILS.md

**For setup:**
1. Follow docs/QUICKSTART.md
2. Use this card for reference
3. Run automated demo to verify
