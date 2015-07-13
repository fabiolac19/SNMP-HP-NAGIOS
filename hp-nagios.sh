#!/bin/sh

# Modo de uso: hp-nagios.sh <ip addr or hostname> <private or public>

STATE_OK=$(expr 0)
STATE_WARNING=$(expr 1)
STATE_CRITICAL=$(expr 2)
STATE_UNKNOWN=$(expr 3)
CLUSTERINSTANCE=$5


LIBEXEC="/usr/local/icinga/libexec"

RET=$?
if [[ $RET -ne 0 ]]
then
echo "query problem - No data received from host"
exit $STATE_UNKNOWN
fi

# figure out the name of the cluster for instance supplied on command line
clustername=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusClusterName.$CLUSTERINSTANCE|cut -d" " -f4)
#echo "Clustername=$clustername"

# total number of modules in management group
totalmodules=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleCount.0|cut -d" " -f4)
#echo "totalmodules=$totalmodules"

# total number of modules in this particular cluster
clustermodules=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusClusterModuleCount.$CLUSTERINSTANCE|cut -d" " -f4)
#echo "clustermodules=$clustermodules"

checkcount=0

#cycle through each module. Get the totalsize, check only those who match our clustername, then find the smallest sized module in our cluster, multiply it by
# the number of modules in our cluster - that should give us our total cluster capacity.
while [ "$checkcount" -lt $totalmodules ]
do
ck=$(echo $checkcount + 1 | bc)

ibelongto=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleClusterName.$ck|cut -d" " -f4)

#echo "does $ibelongto equal $clustername?"
if [ "$ibelongto" = "$clustername" ] ; then

modtotal=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusModuleUsableSpace.$ck|cut -d" " -f4)

modtotal=$(echo "$modtotal" | bc)
#echo "stdin errors above...."

if [ checkmodtotal=0 ] ; then
checkmodtotal=$(echo "$modtotal" | bc)
fi
#echo "Check to see if $modtotal is -le $checkmodtotal"
if [ $modtotal -le $checkmodtotal ] ; then
checkmodtotal=$(echo "$modtotal" | bc)
#echo "setting total to $checkmodtotal"
fi
fi

#echo "checkmodtotal is $checkmodtotal"
checkcount=$(($checkcount+1))
done

# How many volumes are in this management group? Let's cycle through them all and count the used space of the volume, and its snapshots (but only
# if they belong to OUR cluster:
numbervolumes=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusVolumeCount.0|cut -d" " -f4)
#echo "Total Volumes in this Management Group is $numbervolumes"

addvolumes=1
totalused=0
while [ "$addvolumes" -le $numbervolumes ]
do
ibelongto=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusVolumeClusterName.$addvolumes|cut -d" " -f4)
if [ "$ibelongto" = "$clustername" ] ; then
#echo "Sure does... check replication level, then look to see if there are snapshots"
repllevel=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusVolumeReplicaCount.$addvolumes|cut -d" " -f4)
#echo "Got a rep level of $repllevel"
snapcount=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusVolumeSnapshotCount.$addvolumes|cut -d" " -f4)
#echo "found $snapcount snapshots"
snapcheck=1
# get the used space of the volume for now.
thisvolumeprov=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusVolumeProvisionedSpace.$addvolumes|cut -d" " -f4)
#echo "non snap size is $thisvolumeprov"
# now cycle through all the snapshots, and add their used space together
while [ "$snapcheck" -le $snapcount ]
do
thissnapprov=$($LIBEXEC/check_snmp -P 2c -H $1 -C $2 -o LEFTHAND-NETWORKS-NSM-CLUSTERING-MIB::clusVolumeSnapshotProvisionedSpace.$addvolumes.$snapcheck|cut -d" " -f4)
#echo "bare snap is $thissnapprov - now add volume plus snapshot"
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

#echo "done checking volumes - let's total it up!"
# Lefthand SNMP reports usage in KB, so divide by 1024
totalused=$(echo "$totalused / 1024" | bc)
#echo "total MB $totalused"

# now divide by 1024 to convert MB to GB
totalused=$(echo "$totalused / 1024" | bc)
#echo "total GB $totalused"


clustertotal=$(echo "$checkmodtotal * $clustermodules" | bc)
#echo "clustertotal=$clustertotal"

# There's some overhead to the cluster total due to formating etc etc. Dunno if this is scientific, but this number seemed
# to give me a relatively accurate clustersize across a few different builds, so I'm gonna run with .9845
clustertotal=$(echo "$clustertotal * .9845" | bc)
clustertotal=$(echo "$clustertotal/1" | bc)
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
#echo "wt= $wt"


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

