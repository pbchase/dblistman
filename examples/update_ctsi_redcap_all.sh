#!/bin/bash

cd /home/redcap/dblistman
./dblistman.pl -c -u -l CTSI-REDCAP-ALL-L
sleep 5
./dblistman.pl -c -d ctsi_redcap -q update_ctsi_redcap_all.sql -s -l CTSI-REDCAP-ALL-L
