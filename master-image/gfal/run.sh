#!/bin/bash

NUM_SERVER=$1

cd /home/gfal/

for i in 100 125 150 200 300 400 500 750 1000 1500; do
    date
    sh transfer-gfal.sh $i $((NUM_SERVER/2)) &
    sleep 300
    killall sh
    sleep 60
done

