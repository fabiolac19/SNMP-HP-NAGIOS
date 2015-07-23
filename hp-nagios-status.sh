#!/bin/bash

c1=0
i1=0
flag_statusman=0;
flag_statusstor=0;
flag_numman=0;
flag_numstor=0;
# Verifica status Manager. En caso de estado "down" guarda id del modulo y levanta bandera identificando problema.
while read -r line; do
	#num_mod=$(echo $line | cut -f1 -d' ')
	manager[c1]=$(echo $line | cut -f2 -d' ')
	#echo "manager:"${manager[$c1]}
	if [[ "${manager[$c1]}" != "up" ]]
	then
		flag_statusman=1;
		flag_numman[$i1]=$c1
		((i1=i1+1))
	fi
	((c1=c1+1))
done < managerstatus
flag_statusstor=0
# Verifica status Storage. En caso de estado "down" guarda id del modulo y levanta bandera identificando problema.
while read -r line; do
	#num_mod1=$(echo $line | cut -f1 -d' ')
	storage[c2]=$(echo $line | cut -f2 -d' ')
	if [[ "${storage[$c2]}" != "up" ]]
	then
		flag_statusstor=1;
		flag_statusnum[$i2]=$c2
		((i2=i2+1))
	fi
	((c2=c2+1))
done < storagestatus 

# Verifica state Storage. En caso distinto a "ok" guarda id del modulo y levanta bandera identificando problema.
while read -r line; do
	storagestates[c3]=$(echo $line | cut -f2 -d' ')
	if [[ "${storagestates[$c3]}" != "ok" ]]
	then
		flag_statestor=1;
		flag_statenum[$i3]=$c3
		((i3=i3+1))
	fi
	((c3=c3+1))
done < storagestate 

# Verifica condition Storage. En caso de: notReady levantamos flag_warning, inoperable overloaded levantamos flag_warning

while read -r line; do
	#num_mod1=$(echo $line | cut -f1 -d' ')
	condition[c4]=$(echo $line | cut -f2 -d' ')
	if [[ "${condition[$c4]}" == "notReady" ]]
	then
		flag_warning=1;
		flag_numwarn[$i4]=$c4
		((i4=i4+1))
	fi
	if [[ "${condition[$c4]}" == "inoperable" || "${condition[$c4]}" == "overloaded" ]]
	then
		flag_critical=1;
		flag_numcri[$i5]=$c4
		((i5=i5+1))
	fi	
	((c2=c4+1))
done < storagecondition 

if [[ -n $flag_statusman ]]
then
	c1=3
  echo ${flag_numman[*]}
  echo ${manager[$c1]}
  
fi

if [[ $flag_statusstor == "1" ]]
then
  echo "nop"${storage[$flag_numstor]}
fi
