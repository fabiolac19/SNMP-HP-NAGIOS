#!/bin/sh

# Script para monitoreo de cluster storage HP StoreVirtual con SNMP.
# Monitorea capacidad ocupada/disponible/total - Muestra en BG y MG
# El usuario puede ingresar valores de umbral critico y de alerta para la evaluacion del estado del cluster

# Modo de uso: hp-nagios.sh <ip/hostname> <priv/publ> <umbral de alerta> <umbral critico> <instancia o cluster a consultar>

# Define variables de retorno para el estado del cluster
STATE_OK=$(expr 0)
STATE_WARNING=$(expr 1)
STATE_CRITICAL=$(expr 2)
STATE_UNKNOWN=$(expr 3)
CLUSTERINSTANCE=$5
# LIBEXEC= ruta de acceso a pluggins o addons de NAGIOS donde se encuentra check_snmp
LIBEXEC="/usr/local/icinga/libexec"

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

checkcount=0
# Toma modulo del total de modulos del sistema.
while [ "$checkcount" -lt $totalmodules ]
do
ck=$(echo $checkcount + 1 | bc) #suma 1
# toma el nombre del cluster al cual pertenece el modulo
ibelongto=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleClusterName.$ck|cut -d" " -f4)
# si es el cluster al que estamos consultando toma el tamaño del modulo
if [ "$ibelongto" = "$clustername" ] ; then
	modtotal=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleUsableSpace.$ck|cut -d" " -f4)
	modtotal=$(echo "$modtotal" | bc)
	# Busca el modulo mas pequeño para multiplicarlo con la cant. de modulos del cluster y obtener la capacidad total
	if [ checkmodtotal=0 ] ; then
		checkmodtotal=$(echo "$modtotal" | bc)
	fi
	if [ $modtotal -le $checkmodtotal ] ; then
		checkmodtotal=$(echo "$modtotal" | bc)
	fi
fi
#echo "checkmodtotal is $checkmodtotal"
checkcount=$(($checkcount+1))
done

# How many volumes are in this management group? Let's cycle through them all and count the used space of the volume, and its snapshots (but only
# if they belong to OUR cluster:
# Toma cantidad de volumenes total
numbervolumes=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusVolumeCount.0|cut -d" " -f4)
echo "Total Volumes in this Management Group is $numbervolumes"

addvolumes=1
totalused=0
while [ "$addvolumes" -le $numbervolumes ]
do
ibelongto=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusVolumeClusterName.$addvolumes|cut -d" " -f4)
if [ "$ibelongto" = "$clustername" ] ; then
	# si el volumen pertenece al cluster al que estamos consultando, ckequea si hay replicas, y si las hay revisa snapshots"
	repllevel=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusVolumeReplicaCount.$addvolumes|cut -d" " -f4)
	snapcount=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusVolumeSnapshotCount.$addvolumes|cut -d" " -f4)
	# echo "se encontraron $snapcount snapshots"
	snapcheck=1
	# Toma el espacio utilizado del volumen
	thisvolumeprov=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusVolumeProvisionedSpace.$addvolumes|cut -d" " -f4)

	# Recorre cada snapshot uniendolas en la variable: thisvolumeprov
	while [ "$snapcheck" -le $snapcount ]
	do
		thissnapprov=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusVolumeSnapshotProvisionedSpace.$addvolumes.$snapcheck|cut -d" " -f4)
		thisvolumeprov=$(echo "$thisvolumeprov + $thissnapprov" | bc)
		#echo "This volumes size so far is $thisvolumeprov"
		snapcheck=$(($snapcheck+1))
	done
	repllevel=$(echo "$repllevel / 1" | bc)
	#thisvolumeprov=$(echo "$repllevel * $thisvolumeprov" | bc)
	totalused=$(echo "$totalused + $thisvolumeprov" | bc)
	dispgb=$(echo "$thisvolumeprov/1024" | bc)
	dispgb=$(echo "$dispgb/1024" | bc)
	#echo "thisvolume=$dispgb ($repllevel way replication)"
fi
addvolumes=$(($addvolumes+1))
done

# Lefthand SNMP reports usage in KB, so divide by 1024
totalused=$(echo "$totalused / 1024" | bc)
echo "total MB $totalused"
# divide by 1024 to convert MB to GB
totalused=$(echo "$totalused / 1024" | bc)
echo "total GB $totalused"

# Calcula la capacidad total del cluster multiplicando la cant. de modulos por checkmodtotal calculado prev.
clustertotal=$(echo "$checkmodtotal * $clustermodules" | bc)
echo "clustertotal=$clustertotal"

# ???There's some overhead to the cluster total due to formating etc etc. Dunno if this is scientific, but this number seemed
# to give me a relatively accurate clustersize across a few different builds, so I'm gonna run with .9845
clustertotal=$(echo "$clustertotal * .9845" | bc)
clustertotal=$(echo "$clustertotal/1" | bc) #redondea con /1
#echo "newclustertotal=$clustertotal"
clustertotal=$(echo "$clustertotal / 1024" | bc)
clustertotal=$(echo "$clustertotal / 1024" | bc)
#echo "clustertotal in GB = $clustertotal"

clusteravail=$(echo $clustertotal - $totalused | bc)
#echo "clusteravail=$clusteravail"

# calculate the current percentage free of the cluster
percentfree=$(echo "scale=2; $clusteravail/$clustertotal " |bc)
#echo "percentfree=$percentfree"

wp=$(echo "scale=2; .01*$3" | bc)
cp=$(echo "scale=2; .01*$4" | bc)

# calculate the GB that equals the warning threshhold:
wt=$(echo "scale=10; $clustertotal * $wp" | bc)
# get rid of the decimal places that bash can't deal with
wt=$(echo "$wt /1" | bc)
#echo "the wt is $wt"

# calculate the GB that equals the critical threshhold:
ct=$(echo "scale=2; $clustertotal * $cp" | bc)
# get rid of the decimal places that bash can't deal with
ct=$(echo "$ct /1" | bc)
#echo "the ct is $ct"

#echo "wp=$wp"
#echo "ct=$ct"
#echo "wt=$wt"

cu=$(expr $clustertotal - $clusteravail)
percentfree=$(echo "$percentfree*100" | bc)

if [ $cu -ge $ct ] ; then
	echo "CRITICAL - *$clustername is $percentfree % free* | clustersize=$clustertotal available=$clusteravail warning=$wt critical=$ct provisioned=$totalused"
	exit $STATE_CRITICAL

elif [ $cu -le $wt ] ; then
	echo "OK - $clustername is $percentfree % free | clustersize=$clustertotal available=$clusteravail warning=$wt critical=$ct provisioned=$totalused"
	exit $STATE_OK

elif [ $cu -gt $wt ] ; then
	echo "WARNING - *$clustername is $percentfree % free* | clustersize=$clustertotal available=$clusteravail warning=$wt critical=$ct provisioned=$totalused"
	exit $STATE_WARNING

else
	#echo "problem - No data received from host"
	exit $STATE_UNKNOWN
fi 
