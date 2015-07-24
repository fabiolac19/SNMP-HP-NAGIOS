#!/bin/bash

# Script para monitoreo de cluster storage HP StoreVirtual con SNMP.
# Opcion "space_usage": Monitorea capacidad ocupada/disponible/total - Muestra capacidad en GB y MB
# El usuario puede ingresar valores de umbral critico y de alerta para la evaluacion del estado del cluster
# Opcion "cluster_status": Monitoreo de estado de Storage.
# El usuario debe ingresar numero identificador de modulo Storage.
# Num storage Nombre
# 	1 		rogelio-a
# 	2 		rogelio-c
# 	3		rogelio-e
# 	4		rogelio-d
# 	5		rogelio-b

# Modo de uso:
# ./check_hp_storevirtual.sh space_usage <ip> <community> <umbral warning> <umbral critico>
# ./check_hp_storevirtual.sh cluster_status <ip> <community> <num storage>


STATE_OK=$(expr 0)
STATE_WARNING=$(expr 1)
STATE_CRITICAL=$(expr 2)
STATE_UNKNOWN=$(expr 3)
# Instancia cluster: 1
CLUSTERINSTANCE=1
# LIBEXEC= ruta de acceso a pluggins o addons de NAGIOS donde se encuentra check_snmp
LIBEXEC="/usr/lib/nagios/plugins/"

flag_storageko=0
flag_managerdown=0
flag_storagedown=0
flag_warning=0
flag_critical=0

RET=$?
if [[ $RET -ne 0 ]]
then
echo "query problem - No data received from host"
exit $STATE_UNKNOWN
fi

#if [[ $# -ne 4 || $1 = "--help" || $1 = "-h" ]]; then
if [[ $1 = "--help" || $1 = "-h" ]]; then # agregar nulo segundo parametro
	echo "Modo de uso:"
	echo "./check_hp_storevirtual.sh space_usage <ip> <community> <umbral warning> <umbral critico>"
	echo "./check_hp_storevirtual.sh cluster_status <ip> <community> <num storage>"
    exit 1
elif [[ $1 = "cluster_status" ]]; then
	#nombre=$(echo "LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusClusterModuleName.1.1 = STRING: rogelio-a" | sed 's/^.*\: //g;s/=.*\://g;s/(.*//g')
	#The manager status: up(1), down(2) 
	managerstatus=$($LIBEXEC/check_snmp -P 2c -H $2 -C $3 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusManagerStatus.$4 | sed 's/^.*\- //g;s/(.*//g')
	if [[ "$managerstatus" != "up" ]]
		then
			flag_managerdown=1;
	fi
	# The State of the storage system storage server in the cluster: "ok"
	storagestate=$($LIBEXEC/check_snmp -P 2c -H $2 -C $3 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleStorageState.$4 | sed 's/^.*\- //g;s/ .*//g')
	if [[ "$storagestate" != "ok" ]]
		then
			flag_storageko=1;			
	fi
	# The storage system storage server Status: up(1), down(2) 
	storagestatus=$($LIBEXEC/check_snmp -P 2c -H $2 -C $3 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleStorageStatus.$4 | sed 's/^.*\- //g;s/(.*//g')
	if [[ "$storagestatus" != "up" ]]
		then
			flag_storagedown=1;
	fi
	# The condition/state of the storage on the storage module: notReady(1), inoperable(2), overloaded(3), ready(4)
	storagecondition=$($LIBEXEC/check_snmp -P 2c -H $2 -C $3 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleStorageCondition.$4 | sed 's/^.*\- //g;s/(.*//g')
	if [[ "$storagecondition" == "notReady" ]]
	then
		flag_warning=1;
	fi
	if [[ "$storagecondition" == "inoperable" || "$storagecondition" == "overloaded" ]]
	then
		flag_critical=1;
	fi	

	if [[ $flag_managerdown == "1" || $flag_storagedown == "1" || $flag_storageko == "1" || $flag_critical == "1" ]]
	then
		echo "CRITICAL - ManagerStatus: $managerstatus StorageState: $storagestate StorageStatus: $storagestatus StorageCondition: $storagecondition "
		exit $STATE_CRITICAL
	elif [[ $flag_warning == "1" ]]
	then
		echo "WARNING - ManagerStatus: $managerstatus StorageState: $storagestate StorageStatus: $storagestatus StorageCondition: $storagecondition "
		exit $STATE_WARNING
	elif [[ $flag_managerdown == "0" || $flag_storagedown == "0" || $flag_storageko == "0" || $flag_critical == "0" ]]
	then
		echo "OK - ManagerStatus: $managerstatus StorageState: $storagestate StorageStatus: $storagestatus StorageCondition: $storagecondition "
		exit $STATE_OK
	else
		#echo "problem - No data received from host"
		exit $STATE_UNKNOWN
	fi


    exit 1
elif [[ $1 = "space_usage" ]]; then	
	# the name of the cluster for instance supplied on command line CLUSTERINSTANCE=$5
	clustername=$($LIBEXEC/check_snmp -P 2c -H $2 -C $3 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusClusterName.$CLUSTERINSTANCE|cut -d" " -f4)
	#echo "Clustername=$clustername"

	# total number of modules in management group. network storage modules in this system
	totalmodules=$($LIBEXEC/check_snmp -P 2c -H $2 -C $3 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleCount.0|cut -d" " -f4)
	#echo "totalmodules=$totalmodules"

	# total number of modules in this particular cluster
	clustermodules=$($LIBEXEC/check_snmp -P 2c -H $2 -C $3 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusClusterModuleCount.$CLUSTERINSTANCE|cut -d" " -f4)
	#echo "clustermodules=$clustermodules"

	clusteravail=0
	clustertotal=0
	modavail=0
	checkcount=0
	while [ "$checkcount" -lt $totalmodules ]
	do
		ck=$(echo $checkcount + 1 | bc) 
		# clusModuleUsableSpace: The total space available for data storage on the storage module
		modtotal=$($LIBEXEC/check_snmp -P 2c -H $2 -C $3 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleUsableSpace.$ck|cut -d" " -f4)
		clustertotal=$(echo "$clustertotal + $modtotal" | bc)
		# ModuleAvailableSpace: The current space available for data storage on the storage module
		modavail=$($LIBEXEC/check_snmp -P 2c -H $2 -C $3 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleAvailableSpace.$ck|cut -d" " -f4)
		clusteravail=$(echo "$clusteravail + $modavail" | bc)
		checkcount=$(($checkcount+1))
	done
	#echo "clusteravail=$clusteravail"
	clusteravail=$(echo "$clusteravail/1" | bc)
	clusteravail=$(echo "$clusteravail / 1024" | bc)
	#echo "clusteravail in MB = $clusteravail"
	clusteravail=$(echo "$clusteravail / 1024" | bc)
	#echo "clusteravail in GB = $clusteravail"

	#echo "clustertotal=$clustertotal"
	# There's some overhead to the cluster total due to formating etc etc. Dunno if this is scientific, but this number seemed
	# to give me a relatively accurate clustersize across a few different builds, so I'm gonna run with .9845
	clustertotal=$(echo "$clustertotal * .9845" | bc)
	clustertotal=$(echo "$clustertotal/1" | bc) #redondea con /1
	clustertotal=$(echo "$clustertotal / 1024" | bc)
	clustertotal=$(echo "$clustertotal / 1024" | bc)
	#echo "clustertotal in GB = $clustertotal"

	# calculate the current percentage free of the cluster
	percentfree=$(echo "scale=2; $clusteravail/$clustertotal " |bc)
	#echo "percentfree=$percentfree"

	# Toma umbrales introducidos como parametros de warning y critic
	wp=$(echo "scale=2; .01*$4" | bc)
	cp=$(echo "scale=2; .01*$5" | bc)

	# calculate the GB that equals the warning threshhold of the cluster total:
	wt=$(echo "scale=3; $clustertotal * $wp" | bc)
	# get rid of the decimal places that bash can't deal with
	wt=$(echo "$wt /1" | bc)
	#echo "the wt is $wt"

	# calculate the GB that equals the critical threshhold of the cluster total:
	ct=$(echo "scale=3; $clustertotal * $cp" | bc)
	# get rid of the decimal places that bash can't deal with
	ct=$(echo "$ct /1" | bc)
	#echo "the ct is $ct"

	cu=$(expr $clustertotal - $clusteravail)
	percentfree=$(echo "$percentfree*100" | bc)

	# clusterOcupado >= clusterCritico
	if [ $cu -ge $ct ] ; then
		echo "CRITICAL - *$clustername is $percentfree % free* | clustersize=$clustertotal GB available=$clusteravail GB warning=$wt GB critical=$ct GB"
		exit $STATE_CRITICAL

	# clusterOcupado <= clusterWarning
	elif [ $cu -le $wt ] ; then
		echo "OK - $clustername is $percentfree % free | clustersize=$clustertotal GB available=$clusteravail GB warning=$wt GB critical=$ct GB"
		exit $STATE_OK

	# clusterOcupado > clusterWarning
	elif [ $cu -gt $wt ] ; then
		echo "WARNING - *$clustername is $percentfree % free* | clustersize=$clustertotal GB available=$clusteravail GB warning=$wt GB critical=$ct GB"
		exit $STATE_WARNING

	else
		#echo "problem - No data received from host"
		exit $STATE_UNKNOWN
	fi 


	exit 1
else
	echo "Modo de uso:"
	echo "./check_hp_storevirtual.sh space_usage <ip> <community> <umbral warning> <umbral critico>"
	echo "./check_hp_storevirtual.sh cluster_status <ip> <community> <num storage>"
    exit 1
fi
