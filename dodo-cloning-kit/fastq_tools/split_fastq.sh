#!/usr/bin/env bash

num_splits=$1
input_file=$2
is_path=$3
is_pair=$4
output_files=""
for i in $(seq 1 $num_splits); do
	output_files=$output_files" -o ${is_path}--${i}_${is_pair}.fastq.gz";
done
fastqsplitter -i $input_file $output_files
