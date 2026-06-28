#!/bin/bash

# Configuration
DNS_SERVER="127.0.0.1"
DNS_PORT=15353
TSV_FILE="records.tsv"
PID=$(pgrep mfsdns)

# Clear the old report file at the start of the script

OVERALL="YES"
TEST_DOMAIN="web.local." # Change this to a domain that exists in your records.tsv

if [ -z "$PID" ]; then
	
	cp ./etc/$TSV_FILE ./tmp/$TSV_FILE
	nohup ./bin/mfsdns -port 15353 -file ./tmp/$TSV_FILE > ./tmp/mfsdns.log &    
	sleep 1
	PID=$(pgrep mfsdns)
	if [ -z "$PID" ]; then
		echo "couldnt daemon mode start tests -FAIL"
		exit 1
	fi
	echo "Starting daemon (PID: $PID) "

else
	echo "mfsdns shouldnt run already? Kill $PID."
	exit 1
fi

echo "================================================================="
echo -n " 1. Standard A Record.................. "

RESULT=$(dig @$DNS_SERVER -p $DNS_PORT mafficksoft.com A +short)
EXPECTED="1.2.3.4"
if [ "$RESULT" == "$EXPECTED" ]; then echo "PASS"; else echo "FAIL (Got: $RESULT Expected: $EXPECTED)"; OVERALL="NO"; fi

echo "================================================================="
echo -n " 2. Case Insensitivity (ExAmPlE.CoM)... "

RESULT=$(dig @$DNS_SERVER -p $DNS_PORT MaFFiCksoft.CoM A +short)
EXPECTED="1.2.3.4"
if [ "$RESULT" == "$EXPECTED" ]; then echo "PASS"; else echo "FAIL (Got: $RESULT Expected: $EXPECTED )"; OVERALL="NO"; fi

echo "================================================================="
echo -n " 3. Internal Health Check.............. "

RESULT=$(dig @$DNS_SERVER -p $DNS_PORT checkstatus.local TXT +short)

if [[ $RESULT == *"STATUS=OK"* ]]; then echo "PASS"; else echo "FAIL (Got: $RESULT Expected: STATUS=OK )"; OVERALL="NO"; fi

echo "================================================================="
echo -n " 4. Testing Atomic Reload via SIGHUP... "

echo -e "reload.test.\tA\t9.9.9.9\t0" >> ./tmp/$TSV_FILE
kill -HUP $PID
sleep 1 # Give it a moment to swap buffers

RESULT=$(dig @$DNS_SERVER -p $DNS_PORT reload.test A +short)
if [ "$RESULT" == "9.9.9.9" ]; then 
    echo "PASS"
else 
    echo "FAIL: New Record not found."
	OVERALL="NO"
fi
echo "================================================================="
for i in {1..3}; do
    # Runs dig, extracts just the IP addresses/values from the answer section
    RESULT=$(dig "@${DNS_SERVER}" -p "${DNS_PORT}" "${TEST_DOMAIN}" A +short)
    case $i in 
        1)
			EXPECTED_RESULT="192.168.1.12 192.168.1.10 192.168.1.11"
            ;; # <-- Required to close the case item
        2) 
			EXPECTED_RESULT="192.168.1.10 192.168.1.11 192.168.1.12"
            ;; 
        3)
			EXPECTED_RESULT="192.168.1.11 192.168.1.12 192.168.1.10"
            ;;
        *)
            echo "Invalid selection. Please choose 1, 2, or 3."
            ;;
    esac
	MEXPECTED_RESULT="${EXPECTED_RESULT//[$'\r\n ']}"
	MRESULT="${RESULT//[$'\r\n ']}"
	echo -n " 5.${i} Round Robin Query reload #${i} ...... " 
	if [ "$MRESULT" == "$MEXPECTED_RESULT" ]; then
		echo "PASS"
	else 
		echo "FAIL"
		OVERALL="NO"
	fi
    echo "Result:" $RESULT
	echo "expected: ($EXPECTED_RESULT)"

	echo "================================================================="
    sleep 0.5
done

# Cleanup
rm ./tmp/$TSV_FILE
# stop daemon
kill -9 $PID 

echo -n " Overall Testing Results .............. "
if [ "$OVERALL" == "YES" ]; then
	echo "PASS"
	exit 0
else
	echo "FAIL! "
	exit 1
fi
