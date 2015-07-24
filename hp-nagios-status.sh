#!/bin/bash
if [[ $1 = "--help" || $1 = "-h" ]]; then
	echo "# Modo de uso: ./hp-nagios.sh <ip> <community> <umbral warning> <umbral critico>"
    exit 1

elif [[ $1 = "check_status" ]]; then
	echo "# check_status"
	echo "segundo parametro:"$2
    exit 1
elif [[ $1 = "check_space" || $1 = "-h" ]]; then
	echo "# check_space" 
	echo "segundo parametro:"$2
    exit 1
else
	echo "# Modo de uso: ./hp-nagios.sh <ip> <community> <umbral warning> <umbral critico>"
	exit 1
fi
# Define variables de retorno para el estado del cluster
echo "" > ok_status
echo "" > warning_status
echo "" > critical_status
STATE_OK=$(expr 0)
STATE_WARNING=$(expr 1)
STATE_CRITICAL=$(expr 2)
STATE_UNKNOWN=$(expr 3)
# Instancia cluster: 1
CLUSTERINSTANCE=1
# LIBEXEC= ruta de acceso a pluggins o addons de NAGIOS donde se encuentra check_snmp
LIBEXEC="/usr/lib/nagios/plugins/"

RET=$?
if [[ $RET -ne 0 ]]
then
echo "query problem - No data received from host"
exit $STATE_UNKNOWN
fi
# $3 parametro: numero de modulo storage
nombre=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleName.$3 | cut -f4 -d' ')
#The manager status: up(1), down(2) 
managerstatus=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusManagerStatus.$3 | cut -f4 -d' ')
if [[ "$managerstatus" != "up" ]]
	then
		flag_managerdown=1;
		mancritical="ManagerStatus: $managerstatus. "
		#sed "s|$| ManagerStatus ${managerstatus}|" critical_status > aux_critical
fi
# The State of the storage system storage server in the cluster: "ok"
storagestate=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleStorageState.$3 | cut -f4 -d' ')
if [[ "$storagestate" != "ok" ]]
	then
		flag_storageko=1;
		storcritical="StorageState: $storagestate. "
fi
# The storage system storage server Status: up(1), down(2) 
storagestatus=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleStorageStatus.$3 |  cut -f4 -d' ')
if [[ "$storagestatus" != "up" ]]
	then
		flag_storagedown=1;
		storcritical1="StorageStatus: $storagestatus "
fi
# The condition/state of the storage on the storage module: notReady(1), inoperable(2), overloaded(3), ready(4)
storagecondition=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleStorageCondition.$3 |  cut -f4 -d' ')
if [[ "$storagecondition" == "notReady" ]]
then
	flag_warning=1;
	storwarning="StorageCondition: $storagecondition "
fi
if [[ "$storagecondition" == "inoperable" || "$storagecondition" == "overloaded" ]]
then
	flag_critical=1;
	storcritical2="StorageCondition: $storagecondition "
fi	

if [[ $flag_managerdown == "1" || $flag_storagedown == "1" || $flag_storageko == "1" || $flag_critical == "1" ]]
then
	echo "CRITICAL $mancritical$storcritical$storcritical1$storcritical2"
	exit $STATE_CRITICAL
elif [[ $flag_warning == "1" ]]
then
	echo "WARNING - $storwarning"
	exit $STATE_WARNING
elif [[ $flag_managerdown == "0" || $flag_storagedown == "0" || $flag_storageko == "0" || $flag_critical == "0" ]]
then
	echo "OK - ManagerStatus: $managerstatus. StorageState: $storagestate. StorageStatus: $storagestatus. StorageCondition: $storagecondition. "
	exit $STATE_OK
else
	#echo "problem - No data received from host"
	exit $STATE_UNKNOWN
fi
