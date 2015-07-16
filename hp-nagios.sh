#!/bin/bash

# Script para monitoreo de cluster storage HP StoreVirtual con SNMP.
# Monitorea capacidad ocupada/disponible/total - Muestra en GB y MB
# El usuario puede ingresar valores de umbral critico y de alerta para la evaluacion del estado del cluster

# Modo de uso: hp-nagios.sh <ip/hostname> <community> <umbral de alerta> <umbral critico> 

if [[ $# -ne 4 || $1 = "--help" || $1 = "-h" ]]; then
	echo "# Modo de uso: ./hp-nagios.sh <ip> <community> <umbral warning> <umbral critico>"
        exit 1
fi

# Define variables de retorno para el estado del cluster
STATE_OK=$(expr 0)
STATE_WARNING=$(expr 1)
STATE_CRITICAL=$(expr 2)
STATE_UNKNOWN=$(expr 3)
CLUSTERINSTANCE=1
# LIBEXEC= ruta de acceso a pluggins o addons de NAGIOS donde se encuentra check_snmp
LIBEXEC="/usr/lib/nagios/plugins/"

RET=$?
if [[ $RET -ne 0 ]]
then
echo "query problem - No data received from host"
exit $STATE_UNKNOWN
fi

# Usage:check_snmp [-P snmp version] -H <ip_address> [-C community] -o <OID>
# -P, --protocol=[1|2c|3], SNMP protocol version
# -H, --hostname=ADDRESS, Host name, IP Address, or unix socket (must be an absolute path)
# -C, --community=STRING, Optional community string for SNMP communication (default is "public")
# -o, --oid=OID(s), Object identifier(s) or SNMP variables whose value you wish to query

# the name of the cluster for instance supplied on command line CLUSTERINSTANCE=$5
clustername=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusClusterName.$CLUSTERINSTANCE|cut -d" " -f4)
echo "Clustername=$clustername"

# total number of modules in management group. network storage modules in this system
totalmodules=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleCount.0|cut -d" " -f4)
echo "totalmodules=$totalmodules"

# total number of modules in this particular cluster
clustermodules=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusClusterModuleCount.$CLUSTERINSTANCE|cut -d" " -f4)
echo "clustermodules=$clustermodules"

clusteravail=0
modavail=0
checkcount=0
while [ "$checkcount" -lt $totalmodules ]
do
	ck=$(echo $checkcount + 1 | bc) 
	# ModuleAvailableSpace: The current space available for data storage on the storage module
	modavail=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleAvailableSpace.$ck|cut -d" " -f4)
	clusteravail=$(echo "$clusteravail + $modavail" | bc)
	checkcount=$(($checkcount+1))
done
echo "clusteravail=$clusteravail"
clusteravail=$(echo "$clusteravail/1" | bc)
clusteravail=$(echo "$clusteravail / 1024" | bc)
echo "clusteravail in MB = $clusteravail"
clusteravail=$(echo "$clusteravail / 1024" | bc)
echo "clusteravail in GB = $clusteravail"

# Calcula la capacidad total del cluster multiplicando la cant. de modulos por checkmodtotal calculado prev.
# Todos los modulos tienen igual tamaño
# clusModuleUsableSpace: The total space available for data storage on the storage module
modtotal=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleUsableSpace.$ck|cut -d" " -f4)
clustertotal=$(echo "$checkmodtotal * $clustermodules" | bc)
echo "clustertotal=$clustertotal"

# There's some overhead to the cluster total due to formating etc etc. Dunno if this is scientific, but this number seemed
# to give me a relatively accurate clustersize across a few different builds, so I'm gonna run with .9845
clustertotal=$(echo "$clustertotal * .9845" | bc)
clustertotal=$(echo "$clustertotal/1" | bc) #redondea con /1
clustertotal=$(echo "$clustertotal / 1024" | bc)
clustertotal=$(echo "$clustertotal / 1024" | bc)
echo "clustertotal in GB = $clustertotal"

# calculate the current percentage free of the cluster
percentfree=$(echo "scale=2; $clusteravail/$clustertotal " |bc)
echo "percentfree=$percentfree"

# Toma umbrales introducidos como parametros de warning y critic
wp=$(echo "scale=2; .01*$3" | bc)
cp=$(echo "scale=2; .01*$4" | bc)

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
	echo "CRITICAL - *$clustername is $percentfree % free* | clustersize=$clustertotal available=$clusteravail warning=$wt critical=$ct provisioned=$totalused"
	exit $STATE_CRITICAL

# clusterOcupado <= clusterWarning
elif [ $cu -le $wt ] ; then
	echo "OK - $clustername is $percentfree % free | clustersize=$clustertotal available=$clusteravail warning=$wt critical=$ct provisioned=$totalused"
	exit $STATE_OK

# clusterOcupado > clusterWarning
elif [ $cu -gt $wt ] ; then
	echo "WARNING - *$clustername is $percentfree % free* | clustersize=$clustertotal available=$clusteravail warning=$wt critical=$ct provisioned=$totalused"
	exit $STATE_WARNING

else
	#echo "problem - No data received from host"
	exit $STATE_UNKNOWN
fi 
