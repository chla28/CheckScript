#!/bin/bash
# InitSecuFolder.sh /data/AuditFolder ProjetTest1
TARGETFOLDER=$1
PROJECT=$2

if [ ! -d ${TARGETFOLDER} ]; then
    mkdir "${TARGETFOLDER}"
fi
cd "${TARGETFOLDER}"

if [ ! -d "AuditData_${PROJECT}" ]; then
    mkdir "AuditData_${PROJECT}"
fi
cd "AuditData_${PROJECT}"

for i in AuditResultsCron RhsaChecker SbomGenerator ToolsUpdates Synthesis
do
    mkdir $i $i/DR2 $i/DR4 $i/Latest
done
