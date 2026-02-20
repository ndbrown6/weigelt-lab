include weigelt-lab/Makefile.inc

LOGDIR = log/kallisto.$(NOW)

kallisto : $(foreach sample,$(SAMPLES),kallisto/$(sample)/$(sample).1.fastq) \
	   $(foreach sample,$(SAMPLES),kallisto/$(sample)/abundance.tsv) \
	   kallisto/tpm_bygene.txt

SLEUTH_ANNOT ?= $(HOME)/share/lib/resource_files/Hugo_ENST_ensembl75_fixed.txt

define bam-to-fastq
kallisto/$1/$1.1.fastq : bam/$1.bam
	$$(call RUN,-n 4 -s 4G -m 9G,"set -o pipefail && \
				      mkdir -p kallisto/$1 && \
				      $$(SAMTOOLS) sort -T kallisto/$1/$1 -O bam -n -@ 4 -m 6G $$(<) | \
				      bedtools bamtofastq -i - -fq kallisto/$1/$1.1.fastq -fq2 kallisto/$1/$1.2.fastq")

endef
$(foreach sample,$(SAMPLES),\
		$(eval $(call bam-to-fastq,$(sample))))

define fastq-to-kallisto
kallisto/$1/abundance.tsv : kallisto/$1/$1.1.fastq
	$$(call RUN,-c -n 12 -s 2G -m 3G -v $(KALLISTO_ENV),"set -o pipefail && \
							     kallisto quant \
							     -i $$(KALLISTO_INDEX) \
							     -o kallisto/$1 \
							     --bias -b 100 -t 12\
							     --fusion kallisto/$1/$1.1.fastq kallisto/$1/$1.2.fastq")

endef
$(foreach sample,$(SAMPLES),\
		$(eval $(call fastq-to-kallisto,$(sample))))
		
kallisto/tpm_bygene.txt : $(foreach sample,$(SAMPLES),kallisto/$(sample)/abundance.tsv)
	$(call RUN, -c -n 24 -s 1G -m 2G -v $(KALLISTO_ENV),"set -o pipefail && \
							     $(RSCRIPT) $(SCRIPTS_DIR)/rna_seq/summarize_sleuth.R --annotation $(SLEUTH_ANNOT) --samples '$(SAMPLES)'")

..DUMMY := $(shell mkdir -p version; \
	$(SAMTOOLS) --version > version/kallisto.txt; \
	~/share/usr/env/kallisto-0.46.2/bin/kallisto version >> version/kallisto.txt; \
	~/share/usr/env/kallisto-0.46.2/bin/R --version >> version/kallisto.txt;)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY:
