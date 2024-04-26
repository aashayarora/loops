END=$1
NUM_SERVER=$2

cd /home/gfal

if [ $NUM_SERVER -gt 0 ]; then
  segment_size=$(( $END / $NUM_SERVER ))  # Calculate the size of each segment

  for (( server_id = 0; server_id < $NUM_SERVER; server_id++ )); do
    start_index=$(( $server_id * $segment_size + 1 ))
    end_index=$(( ($server_id + 1) * $segment_size ))

    if [ $server_id -eq $(($NUM_SERVER - 1)) ]; then
      end_index=$END  # Adjust the last segment to cover the full range
    fi

    for index in $(seq $start_index $end_index); do
      echo $index
      sh run-rucio.sh $index $(( $server_id * 2 + 1 )) $(( $server_id * 2 + 2 )) &> log-$dest-$index-$END &
    done
  done
fi
