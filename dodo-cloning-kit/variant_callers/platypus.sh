#!/usr/bin/env bash

input_vcf="$1"
output_vcf="$2"

awk '
BEGIN { OFS="\t" }

# Pass through all header lines unchanged
/^#/ {
    print
    next
}

# Process variant lines
{
    # Find FORMAT column structure
    n_fields = split($9, fmt, ":")
    nr_idx = 0
    nv_idx = 0
    
    for (i=1; i<=n_fields; i++) {
        if (fmt[i] == "NR") nr_idx = i
        if (fmt[i] == "NV") nv_idx = i
    }
    
    # Add AD and DP to FORMAT
    $9 = $9 ":AD:DP"
    
    # Process each sample column (columns 10 and 11 for tumor and normal)
    for (col=10; col<=NF; col++) {
        split($col, sample, ":")
        
        # Handle missing/no-call data
        if (sample[1] == "./." || nr_idx == 0 || nv_idx == 0 || 
            sample[nr_idx] == "" || sample[nr_idx] == "." || 
            sample[nv_idx] == "" || sample[nv_idx] == ".") {
            $col = $col ":.:."
        } else {
            nr = sample[nr_idx]  # Total reads covering position
            nv = sample[nv_idx]  # Variant reads
            
            # Calculate reference reads
            ref_depth = nr - nv
            
            # Create AD (ref,alt) and DP
            ad = ref_depth "," nv
            dp = nr
            
            $col = $col ":" ad ":" dp
        }
    }
    
    print
}
' "$input_vcf" > "$output_vcf"