#!/bin/bash
# Copyright 2018 WSO2 Inc. (http://wso2.org)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ----------------------------------------------------------------------------
# Create a summary report from JMeter results
# ----------------------------------------------------------------------------

gcviewer_path=$1
#true or false argument
include_all=$2

if [[ ! -f $gcviewer_path ]]; then
    echo "Please specify the path to GCViewer JAR file. Example: $0 gcviewer_jar_file include_all->(true/false)"
    exit 1
fi

get_gc_headers() {
    echo -ne ",$1 GC Throughput (%),$1 Footprint (M),$1 Average of Footprint After Full GC (M)"
    echo -ne ",$1 Standard Deviation of Footprint After Full GC (M)"
}

get_loadavg_headers() {
    echo -ne ",$1 Load Average - Last 1 minute,$1 Load Average - Last 5 minutes,$1 Load Average - Last 15 minutes"
}

filename="summary.csv"
if [[ ! -f $filename ]]; then
    # Create File and save headers
    echo -n "Heap Size","Ballerina File","Observability","Concurrent Users","Message Size (Bytes)","Sleep Time (ms)", > $filename
    echo -n "# Samples","Error Count","Error %","Average (ms)","Min (ms)","Max (ms)", >> $filename
    echo -n "90th Percentile (ms)","95th Percentile (ms)","99th Percentile (ms)","Throughput", >> $filename
    echo -n "Received (KB/sec)","Sent (KB/sec)" >> $filename
    echo -n $(get_gc_headers "Ballerina") >> $filename
    if [ "$include_all" = true ] ; then
        echo -n $(get_gc_headers "Netty Service") >> $filename
        echo -n $(get_gc_headers "JMeter Client") >> $filename
        echo -n $(get_gc_headers "JMeter Server 01") >> $filename
        echo -n $(get_gc_headers "JMeter Server 02") >> $filename
    fi
    echo -n $(get_loadavg_headers "Ballerina") >> $filename
    if [ "$include_all" = true ] ; then
        echo -n $(get_loadavg_headers "Netty Service") >> $filename
        echo -n $(get_loadavg_headers "JMeter Client") >> $filename
        echo -n $(get_loadavg_headers "JMeter Server 01") >> $filename
        echo -n $(get_loadavg_headers "JMeter Server 02") >> $filename
    fi
    echo -ne "\r\n" >> $filename
else
    echo "$filename already exists"
    exit 1
fi

write_column() {
    statisticsTableData=$1
    index=$2
    echo -n "," >> $filename
    echo -n "$(echo $statisticsTableData | jq -r ".overall | .data[$index]")" >> $filename
}

get_value_from_gc_summary() {
    echo $(grep -m 1 $2\; $1 | sed -r 's/.*\;(.*)\;.*/\1/' | sed 's/,//g')
}

write_gc_summary_details() {
    gc_log_file=$message_size_dir/$1_gc.log
    gc_summary_file=/tmp/gc.txt
    echo "Reading $gc_log_file"
    java -Xms128m -Xmx128m -jar $gcviewer_path $gc_log_file $gc_summary_file -t SUMMARY &> /dev/null
    echo -n ",$(get_value_from_gc_summary $gc_summary_file throughput)" >> $filename
    echo -n ",$(get_value_from_gc_summary $gc_summary_file footprint)" >> $filename
    echo -n ",$(get_value_from_gc_summary $gc_summary_file avgfootprintAfterFullGC)" >> $filename
    echo -n ",$(get_value_from_gc_summary $gc_summary_file avgfootprintAfterFullGCσ)" >> $filename
}

write_loadavg_details() {
    loadavg_file=$message_size_dir/$1_loadavg.txt
    if [[ -f $loadavg_file ]]; then
        echo "Reading $loadavg_file"
        loadavg_values=$(tail -2 $loadavg_file | head -1)
        loadavg_array=($loadavg_values)
        echo -n ",${loadavg_array[3]}" >> $filename
        echo -n ",${loadavg_array[4]}" >> $filename
        echo -n ",${loadavg_array[5]}" >> $filename
    else
        echo -n ",N/A,N/A,N/A" >> $filename
    fi
}

for heap_size_dir in $(find . -maxdepth 1 -name '*_heap' | sort -V)
do
    echo "Heap Size Dir " + $heap_size_dir
    for bal_file_dir in $(find $heap_size_dir -maxdepth 1 -name '*_bal' | sort -V)
    do
        echo "bal_file_dir" + $bal_file_dir
        for flags_dir in $(find $bal_file_dir -maxdepth 1 -name '*_flags' | sort -V)
        do
            echo "flags_dir" + $flags_dir
            for user_dir in $(find $flags_dir -maxdepth 1 -name '*_users' | sort -V)
            do
                echo "user_dir" + $user_dir
                for message_size_dir in $(find $user_dir -maxdepth 1 -name '*B' | sort -V)
                do

		echo "message_size_dir" + $message_size_dir
                for sleep_time_dir in $(find $message_size_dir -maxdepth 1 -name '*ms_sleep' | sort -V)
                do

                    echo "sleep_time_dir" + $sleep_time_dir
                    dashboard_data_file=$sleep_time_dir/dashboard-measurement/content/js/dashboard.js
                    if [[ ! -f $dashboard_data_file ]]; then
                        echo "WARN: Dashboard data file not found: $dashboard_data_file"
                        continue
                    fi
                    statisticsTableData=$(grep '#statisticsTable' $dashboard_data_file | sed  's/^.*"#statisticsTable"), \({.*}\).*$/\1/')

                    echo "Getting data from $dashboard_data_file"
                    heap_size=$(echo $heap_size_dir | sed -r 's/.\/([0-9]+[a-zA-Z])_heap.*/\1/')
                    bal_file=$(echo $bal_file_dir | sed -nE 's/.*\/([[:alnum:]]+.bal)_bal.*/\1/p')
                    flags=$(echo $flags_dir | sed -nE 's/.*\/([[:alnum:]]+)_flags.*/\1/p')
                    concurrent_users=$(echo $user_dir | sed -r 's/.*\/([0-9]+)_users.*/\1/')
                    message_size=$(echo $message_size_dir | sed -r 's/.*\/([0-9]+)B.*/\1/')
		    sleep_time=$(echo $sleep_time_dir | sed -r 's/.*\/([0-9]+)ms_sleep.*/\1/')

                    echo -n "$heap_size,$bal_file,$flags,$concurrent_users,$message_size,$sleep_time" >> $filename
                    write_column "$statisticsTableData" 1
                    write_column "$statisticsTableData" 2
                    write_column "$statisticsTableData" 3
                    write_column "$statisticsTableData" 4
                    write_column "$statisticsTableData" 5
                    write_column "$statisticsTableData" 6
                    write_column "$statisticsTableData" 7
                    write_column "$statisticsTableData" 8
                    write_column "$statisticsTableData" 9
                    write_column "$statisticsTableData" 10
                    write_column "$statisticsTableData" 11
                    write_column "$statisticsTableData" 12

                    write_gc_summary_details ballerina
                    if [ "$include_all" = true ] ; then
                        write_gc_summary_details netty
                        write_gc_summary_details jmeter
                        write_gc_summary_details jmeter1
                        write_gc_summary_details jmeter2
                    fi

                    write_loadavg_details ballerina
                    if [ "$include_all" = true ] ; then
                        write_loadavg_details netty
                        write_loadavg_details jmeter
                        write_loadavg_details jmeter1
                        write_loadavg_details jmeter2
                    fi

                    echo -ne "\r\n" >> $filename
                   done
		done
            done
        done
    done
done
echo "Completed. Open $filename."
