#!/usr/bin/env python3
"""
Simple SIP REGISTER test with MD5 Digest Authentication
Measures registration delay from REGISTER to 200 OK
"""

import socket
import hashlib
import random
import re
from datetime import datetime
import time

# Configuration
PROXY_IP = "10.46.0.1"
PROXY_PORT = 5060
USERNAME = "001010000000001"
PASSWORD = "secret123"
DOMAIN = "ims.localdomain"
FROM_URI = f"sip:{USERNAME}@{DOMAIN}"
TO_URI = f"sip:{USERNAME}@{DOMAIN}"
CONTACT_URI = f"sip:{USERNAME}@{PROXY_IP}:5060"

def md5_hash(data):
    """Calculate MD5 hash"""
    return hashlib.md5(data.encode()).hexdigest()

def generate_tag():
    """Generate random tag"""
    return ''.join(random.choices('0123456789abcdef', k=10))

def generate_branch():
    """Generate branch parameter"""
    return 'z9hG4bK' + ''.join(random.choices('0123456789abcdef', k=10))

def generate_call_id():
    """Generate Call-ID"""
    return ''.join(random.choices('0123456789abcdef', k=16)) + '@' + PROXY_IP

def create_register_request(cseq, call_id, from_tag, branch):
    """Create initial REGISTER request"""
    msg = f"""REGISTER sip:{DOMAIN} SIP/2.0
Via: SIP/2.0/UDP {PROXY_IP}:{PROXY_PORT};branch={branch};rport
From: <{FROM_URI}>;tag={from_tag}
To: <{TO_URI}>
Call-ID: {call_id}
CSeq: {cseq} REGISTER
Contact: <{CONTACT_URI}>
Max-Forwards: 70
User-Agent: Python-SIP-Test/1.0
Expires: 3600
Content-Length: 0

"""
    return msg.replace('\n', '\r\n')

def create_register_with_auth(cseq, call_id, from_tag, branch, nonce, realm):
    """Create REGISTER with Authorization header"""
    # Calculate MD5 digest authentication response
    ha1 = md5_hash(f"{USERNAME}:{realm}:{PASSWORD}")
    ha2 = md5_hash(f"REGISTER:sip:{DOMAIN}")
    response = md5_hash(f"{ha1}:{nonce}:{ha2}")
    
    auth_header = f'Digest username="{USERNAME}", realm="{realm}", nonce="{nonce}", uri="sip:{DOMAIN}", response="{response}", algorithm=MD5'
    
    msg = f"""REGISTER sip:{DOMAIN} SIP/2.0
Via: SIP/2.0/UDP {PROXY_IP}:{PROXY_PORT};branch={branch};rport
From: <{FROM_URI}>;tag={from_tag}
To: <{TO_URI}>
Call-ID: {call_id}
CSeq: {cseq} REGISTER
Contact: <{CONTACT_URI}>
Authorization: {auth_header}
Max-Forwards: 70
User-Agent: Python-SIP-Test/1.0
Expires: 3600
Content-Length: 0

"""
    return msg.replace('\n', '\r\n')

def extract_nonce_realm(response):
    """Extract nonce and realm from 401 Unauthorized response"""
    nonce_match = re.search(r'nonce="([^"]+)"', response)
    realm_match = re.search(r'realm="([^"]+)"', response)
    
    nonce = nonce_match.group(1) if nonce_match else None
    realm = realm_match.group(1) if realm_match else None
    
    return nonce, realm

def main():
    """Main test function"""
    print("=" * 60)
    print("SIP REGISTER Authentication Test with Timing")
    print("=" * 60)
    print(f"Proxy: {PROXY_IP}:{PROXY_PORT}")
    print(f"User: {USERNAME}@{DOMAIN}")
    print(f"Password: {'*' * len(PASSWORD)}")
    print("=" * 60)
    
    # Create socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(5.0)
    sock.bind(('', 0))  # Bind to any available port
    local_port = sock.getsockname()[1]
    print(f"Local port: {local_port}")
    
    # Generate SIP identifiers
    call_id = generate_call_id()
    from_tag = generate_tag()
    cseq = 1
    
    try:
        # Step 1: Send initial REGISTER (without auth)
        print("\n[Step 1] Sending initial REGISTER (without authentication)...")
        branch1 = generate_branch()
        register1 = create_register_request(cseq, call_id, from_tag, branch1)
        
        t_start = datetime.now()
        print(f"Timestamp: {t_start.strftime('%H:%M:%S.%f')[:-3]}")
        
        sock.sendto(register1.encode(), (PROXY_IP, PROXY_PORT))
        print("REGISTER sent (expecting 401 Unauthorized)...")
        
        # Receive 401 Unauthorized
        response1, addr = sock.recvfrom(4096)
        t_401_received = datetime.now()
        response1_str = response1.decode('utf-8', errors='ignore')
        
        print(f"\n[Response 1] Received at {t_401_received.strftime('%H:%M:%S.%f')[:-3]}")
        
        if "401 Unauthorized" in response1_str:
            print("✓ Received 401 Unauthorized (challenge)")
            
            # Extract nonce and realm
            nonce, realm = extract_nonce_realm(response1_str)
            print(f"  Nonce: {nonce[:20]}...")
            print(f"  Realm: {realm}")
            
            if not nonce or not realm:
                print("✗ Failed to extract nonce or realm!")
                return
            
            # Step 2: Send REGISTER with Authorization
            print("\n[Step 2] Sending REGISTER with Authorization...")
            cseq += 1
            branch2 = generate_branch()
            register2 = create_register_with_auth(cseq, call_id, from_tag, branch2, nonce, realm)
            
            t_auth_register_sent = datetime.now()
            print(f"Timestamp: {t_auth_register_sent.strftime('%H:%M:%S.%f')[:-3]}")
            
            sock.sendto(register2.encode(), (PROXY_IP, PROXY_PORT))
            print("Authenticated REGISTER sent (expecting 200 OK)...")
            
            # Receive 200 OK
            response2, addr = sock.recvfrom(4096)
            t_200_received = datetime.now()
            response2_str = response2.decode('utf-8', errors='ignore')
            
            print(f"\n[Response 2] Received at {t_200_received.strftime('%H:%M:%S.%f')[:-3]}")
            
            if "200 OK" in response2_str:
                print("✓ Received 200 OK - REGISTRATION SUCCESSFUL!")
                
                # Calculate delays
                total_delay = (t_200_received - t_start).total_seconds() * 1000  # ms
                auth_delay = (t_200_received - t_auth_register_sent).total_seconds() * 1000  # ms
                challenge_roundtrip = (t_401_received - t_start).total_seconds() * 1000  # ms
                
                print("\n" + "=" * 60)
                print("TIMING RESULTS:")
                print("=" * 60)
                print(f"Initial REGISTER to 401:       {challenge_roundtrip:.3f} ms")
                print(f"Auth REGISTER to 200 OK:       {auth_delay:.3f} ms")
                print(f"Total Registration Delay:      {total_delay:.3f} ms")
                print("=" * 60)
                
                # Save results
                with open('/home/open5gs/sip_registration_results.txt', 'w') as f:
                    f.write("SIP REGISTRATION DELAY TEST RESULTS\n")
                    f.write("=" * 60 + "\n")
                    f.write(f"Test Time: {t_start.strftime('%Y-%m-%d %H:%M:%S')}\n")
                    f.write(f"User: {USERNAME}@{DOMAIN}\n")
                    f.write(f"Proxy: {PROXY_IP}:{PROXY_PORT}\n")
                    f.write("\nTiming Breakdown:\n")
                    f.write(f"  1. Initial REGISTER sent:        {t_start.strftime('%H:%M:%S.%f')[:-3]}\n")
                    f.write(f"  2. 401 Unauthorized received:    {t_401_received.strftime('%H:%M:%S.%f')[:-3]}\n")
                    f.write(f"  3. Auth REGISTER sent:           {t_auth_register_sent.strftime('%H:%M:%S.%f')[:-3]}\n")
                    f.write(f"  4. 200 OK received:              {t_200_received.strftime('%H:%M:%S.%f')[:-3]}\n")
                    f.write(f"\nDelay Measurements:\n")
                    f.write(f"  Initial REGISTER → 401:          {challenge_roundtrip:.3f} ms\n")
                    f.write(f"  Auth REGISTER → 200 OK:          {auth_delay:.3f} ms\n")
                    f.write(f"  Total Registration Delay:        {total_delay:.3f} ms\n")
                
                print("\n✓ Results saved to: /home/open5gs/sip_registration_results.txt")
                
            elif "401 Unauthorized" in response2_str:
                print("✗ Received 401 again - Authentication failed!")
                print("Check username/password in Kamailio database")
            else:
                print(f"✗ Unexpected response:")
                print(response2_str[:200])
        else:
            print(f"✗ Unexpected response (expected 401):")
            print(response1_str[:200])
            
    except socket.timeout:
        print("\n✗ Timeout waiting for response from server")
        print("Check if Kamailio is running and listening on 10.46.0.1:5060")
    except Exception as e:
        print(f"\n✗ Error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        sock.close()

if __name__ == "__main__":
    main()
