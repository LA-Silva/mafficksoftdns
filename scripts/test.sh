#!/bin/bash

# Configuration
DNS_SERVER="127.0.0.1"
DNS_PORT=15353
TSV_FILE="records.tsv"
PID=$(pgrep mfsdns)
LOG_FILE="TEST_REPORT.log"

# Clear the old log file at the start of the script
> "$LOG_FILE"

# Function to output to both stdout and log file
log_output() {
	echo "$@" | tee -a "$LOG_FILE"
}

OVERALL="YES"
TEST_DOMAIN="web.local." # Change this to a domain that exists in your records.tsv

if [ -z "$PID" ]; then
	
	cp ./etc/$TSV_FILE ./tmp/$TSV_FILE
	nohup ./bin/mfsdns -port 15353 -file ./tmp/$TSV_FILE > ./tmp/mfsdns.log &    
	sleep 1
	PID=$(pgrep mfsdns)
	if [ -z "$PID" ]; then
		log_output "couldnt daemon mode start tests -FAIL"
		exit 1
	fi
	log_output "Starting daemon (PID: $PID)"

else
	log_output "mfsdns shouldnt run already? Kill $PID."
	exit 1
fi

log_output ""

# Test 1: Standard A Record
TEST_NUM=1
TEST_NAME="Standard A Record"
RESULT=$(dig @$DNS_SERVER -p $DNS_PORT mafficksoft.com A +short)
EXPECTED="1.2.3.4"
if [ "$RESULT" == "$EXPECTED" ]; then 
	STATUS="PASS"
else 
	STATUS="FAIL"
	OVERALL="NO"
fi
log_output "Test $TEST_NUM. $TEST_NAME................. $STATUS"
log_output "expected: $EXPECTED"
log_output "result: $RESULT"
log_output ""

# Test 2: Case Insensitivity
TEST_NUM=2
TEST_NAME="Case Insensitivity (ExAmPlE.CoM)"
RESULT=$(dig @$DNS_SERVER -p $DNS_PORT MaFFiCksoft.CoM A +short)
EXPECTED="1.2.3.4"
if [ "$RESULT" == "$EXPECTED" ]; then 
	STATUS="PASS"
else 
	STATUS="FAIL"
	OVERALL="NO"
fi
log_output "Test $TEST_NUM. $TEST_NAME................. $STATUS"
log_output "expected: $EXPECTED"
log_output "result: $RESULT"
log_output ""

# Test 3: Internal Health Check
TEST_NUM=3
TEST_NAME="Internal Health Check"
RESULT=$(dig @$DNS_SERVER -p $DNS_PORT checkstatus.local TXT +short)
if [[ $RESULT == *"STATUS=OK"* ]]; then 
	STATUS="PASS"
	EXPECTED="STATUS=OK (in TXT response)"
else 
	STATUS="FAIL"
	EXPECTED="STATUS=OK (in TXT response)"
	OVERALL="NO"
fi
log_output "Test $TEST_NUM. $TEST_NAME................. $STATUS"
log_output "expected: $EXPECTED"
log_output "result: $RESULT"
log_output ""

# Test 4: Testing Atomic Reload via SIGHUP
TEST_NUM=4
TEST_NAME="Testing Atomic Reload via SIGHUP"
echo -e "reload.test.\tA\t9.9.9.9\t0" >> ./tmp/$TSV_FILE
kill -HUP $PID
sleep 1 # Give it a moment to swap buffers
RESULT=$(dig @$DNS_SERVER -p $DNS_PORT reload.test A +short)
EXPECTED="9.9.9.9"
if [ "$RESULT" == "$EXPECTED" ]; then 
	STATUS="PASS"
else 
	STATUS="FAIL"
	OVERALL="NO"
fi
log_output "Test $TEST_NUM. $TEST_NAME................. $STATUS"
log_output "expected: $EXPECTED"
log_output "result: $RESULT"
log_output ""

# Test 5: Round Robin Query
for i in {1..3}; do
    RESULT=$(dig "@${DNS_SERVER}" -p "${DNS_PORT}" "${TEST_DOMAIN}" A +short)
    case $i in 
        1)
			EXPECTED_RESULT="192.168.1.12 192.168.1.10 192.168.1.11"
            ;; 
        2) 
			EXPECTED_RESULT="192.168.1.10 192.168.1.11 192.168.1.12"
            ;; 
        3)
			EXPECTED_RESULT="192.168.1.11 192.168.1.12 192.168.1.10"
            ;;
    esac
	MEXPECTED_RESULT="${EXPECTED_RESULT//[$'\r\n ']}"
	MRESULT="${RESULT//[$'\r\n ']}"
	TEST_NUM="5.$i"
	TEST_NAME="Round Robin Query reload #${i}"
	if [ "$MRESULT" == "$MEXPECTED_RESULT" ]; then
		STATUS="PASS"
	else 
		STATUS="FAIL"
		OVERALL="NO"
	fi
	log_output "Test $TEST_NUM. $TEST_NAME................. $STATUS"
	log_output "expected: $EXPECTED_RESULT"
	log_output "result: $RESULT"
	log_output ""
    sleep 0.5
done

# Test 6: MX Record Query
TEST_NUM=6
TEST_NAME="MX Record Query"
RESULT=$(dig @$DNS_SERVER -p $DNS_PORT mafficksoft.com MX +short)
EXPECTED="10 mail.mafficksoft.com."
if [ "$RESULT" == "$EXPECTED" ]; then 
	STATUS="PASS"
else 
	STATUS="FAIL"
	OVERALL="NO"
fi
log_output "Test $TEST_NUM. $TEST_NAME................. $STATUS"
log_output "expected: $EXPECTED"
log_output "result: $RESULT"
log_output ""

# Test 7: AAAA (IPv6) Record Query
TEST_NUM=7
TEST_NAME="AAAA (IPv6) Record Query"
RESULT=$(dig @$DNS_SERVER -p $DNS_PORT mafficksoft.com AAAA +short)
EXPECTED="2001:db8::10"
if [ "$RESULT" == "$EXPECTED" ]; then 
	STATUS="PASS"
else 
	STATUS="FAIL"
	OVERALL="NO"
fi
log_output "Test $TEST_NUM. $TEST_NAME................. $STATUS"
log_output "expected: $EXPECTED"
log_output "result: $RESULT"
log_output ""

# Test 8: CNAME Record Query
TEST_NUM=8
TEST_NAME="CNAME Record Query"
RESULT=$(dig @$DNS_SERVER -p $DNS_PORT www.mafficksoft.com CNAME +short)
EXPECTED="mafficksoft.com."
if [ "$RESULT" == "$EXPECTED" ]; then 
	STATUS="PASS"
else 
	STATUS="FAIL"
	OVERALL="NO"
fi
log_output "Test $TEST_NUM. $TEST_NAME................. $STATUS"
log_output "expected: $EXPECTED"
log_output "result: $RESULT"
log_output ""

# Test 9: TXT Record Query
TEST_NUM=9
TEST_NAME="TXT Record Query"
RESULT=$(dig @$DNS_SERVER -p $DNS_PORT mafficksoft.com TXT +short)
EXPECTED="\"v=spf1 include:_spf.google.com ~all\""
if [ "$RESULT" == "$EXPECTED" ]; then 
	STATUS="PASS"
else 
	STATUS="FAIL"
	OVERALL="NO"
fi
log_output "Test $TEST_NUM. $TEST_NAME................. $STATUS"
log_output "expected: $EXPECTED"
log_output "result: $RESULT"
log_output ""

# Test 10: NS Record Query
TEST_NUM=10
TEST_NAME="NS Record Query"
RESULT=$(dig @$DNS_SERVER -p $DNS_PORT mafficksoft.com NS +short)
EXPECTED="ns1.mafficksoft.com."
if [ "$RESULT" == "$EXPECTED" ]; then 
	STATUS="PASS"
else 
	STATUS="FAIL"
	OVERALL="NO"
fi
log_output "Test $TEST_NUM. $TEST_NAME................. $STATUS"
log_output "expected: $EXPECTED"
log_output "result: $RESULT"
log_output ""

# Test 11: SRV Record Query (SIP)
TEST_NUM=11
TEST_NAME="SRV Record Query (SIP)"
RESULT=$(dig @$DNS_SERVER -p $DNS_PORT _sip._udp.mafficksoft.com SRV +short)
EXPECTED="10 50 5060 voice.mafficksoft.com."
if [ "$RESULT" == "$EXPECTED" ]; then 
	STATUS="PASS"
else 
	STATUS="FAIL"
	OVERALL="NO"
fi
log_output "Test $TEST_NUM. $TEST_NAME................. $STATUS"
log_output "expected: $EXPECTED"
log_output "result: $RESULT"
log_output ""

# Test 12: SRV Record Query (SSH)
TEST_NUM=12
TEST_NAME="SRV Record Query (SSH)"
RESULT=$(dig @$DNS_SERVER -p $DNS_PORT _ssh._tcp.infra.local SRV +short)
EXPECTED="0 0 22 bastion.infra.local."
if [ "$RESULT" == "$EXPECTED" ]; then 
	STATUS="PASS"
else 
	STATUS="FAIL"
	OVERALL="NO"
fi
log_output "Test $TEST_NUM. $TEST_NAME................. $STATUS"
log_output "expected: $EXPECTED"
log_output "result: $RESULT"
log_output ""

# Test 13: CNAME Alias Resolution
TEST_NUM=13
TEST_NAME="CNAME Alias Resolution"
RESULT=$(dig @$DNS_SERVER -p $DNS_PORT backup.local CNAME +short)
EXPECTED="nas.local."
if [ "$RESULT" == "$EXPECTED" ]; then 
	STATUS="PASS"
else 
	STATUS="FAIL"
	OVERALL="NO"
fi
log_output "Test $TEST_NUM. $TEST_NAME................. $STATUS"
log_output "expected: $EXPECTED"
log_output "result: $RESULT"
log_output ""

# Test 14: Multiple A Records (web.local)
TEST_NUM=14
TEST_NAME="Multiple A Records (web.local)"
RESULT=$(dig @$DNS_SERVER -p $DNS_PORT web.local A +short | sort)
EXPECTED=$(printf "192.168.1.10\n192.168.1.11\n192.168.1.12")
if [ "$RESULT" == "$EXPECTED" ]; then 
	STATUS="PASS"
else 
	STATUS="FAIL"
	OVERALL="NO"
fi
log_output "Test $TEST_NUM. $TEST_NAME................. $STATUS"
log_output "expected: $EXPECTED"
log_output "result: $RESULT"
log_output ""

# Cleanup
rm ./tmp/$TSV_FILE
# stop daemon
kill -9 $PID 

log_output "================================================================="
if [ "$OVERALL" == "YES" ]; then
	log_output "Overall Testing Results .............. PASS"
	exit 0
else
	log_output "Overall Testing Results .............. FAIL"
	exit 1
fi
