#!/bin/bash

# Configuration
DNS_SERVER="127.0.0.1"
DNS_PORT=15353
TSV_FILE="records.tsv"
PID=$(pgrep mfsdns)

if [ -z "$PID" ]; then
	echo "Starting daemon (PID: $PID) test mode...(PID: $PID)"
	
	cp ./etc/$TSV_FILE ./tmp/$TSV_FILE
	nohup ./bin/mfsdns -port 15353 -file ./tmp/$TSV_FILE > ./tmp/mfsdns.log &    
	sleep 1
	PID=$(pgrep mfsdns)
	if [ -z "$PID" ]; then
		echo "couldnt daemon mode start tests -FAIL"
		exit 1
	fi
else
	echo "mfsdns shouldnt run already? Kill $PID."
	exit 1
fi

echo "--- Starting Tests  ---"

# Test 1: Standard A Record Lookup
echo -n "Test 1: Standard A Record... "
RESULT=$(dig @$DNS_SERVER -p $DNS_PORT mafficksoft.com A +short)
if [ "$RESULT" == "1.2.3.4" ]; then echo "PASS"; else echo "FAIL (Got: $RESULT)"; fi

# Test 2: Case Insensitivity
echo -n "Test 2: Case Insensitivity (ExAmPlE.CoM)... "
RESULT=$(dig @$DNS_SERVER -p $DNS_PORT MaFFiCksoft.CoM A +short)
if [ "$RESULT" == "1.2.3.4" ]; then echo "PASS"; else echo "FAIL"; fi

# Test 3: Health Check Domain
echo -n "Test 3: Internal Health Check... "
RESULT=$(dig @$DNS_SERVER -p $DNS_PORT checkstatus.local TXT +short)
if [[ $RESULT == *"STATUS=OK"* ]]; then echo "PASS"; else echo "FAIL"; fi

# Test 4: Atomic Reload (SIGHUP)
echo "Test 4: Testing Atomic Reload via SIGHUP..."
echo -e "reload.test.\tA\t9.9.9.9\t0" >> ./tmp/$TSV_FILE

echo "Sending SIGHUP to $PID..."
kill -HUP $PID
sleep 1 # Give it a moment to swap buffers

RESULT=$(dig @$DNS_SERVER -p $DNS_PORT reload.test A +short)
echo result= "$RESULT"
if [ "$RESULT" == "9.9.9.9" ]; then 
    echo "PASS: New record found after reload."
else 
    echo "FAIL: Record not found after reload."
fi

# Cleanup
rm ./tmp/$TSV_FILE
# stop daemon
kill -9 $PID 

echo "--- Tests Complete ---"
exit 0
