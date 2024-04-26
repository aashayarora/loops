RANUID=`cat /proc/sys/kernel/random/uuid | sed 's/[-]//g' | head -c 20; echo;`

ID=$1
SRC=$2
DEST=$3
echo "$ID" "$RANUID"
FROM="davs://xrd-$SRC.rucio.sense.org:1098//testSourceFile$ID"
TO="davs://xrd-$DEST.rucio.sense.org:1098//testDestFile$ID"
count=0
while [ $count -ne 1000 ]
do
  gfal-copy --just-copy --copy-mode pull -p -f $FROM $TO
  count=`expr $count + 1`
  echo $count
done
