include weigelt-lab/Makefile.inc

LOGDIR = log/kallisto_quant.$(NOW)

kallisto : $(foreach sample,$(SAMPLES),kallisto/$(sample)/$(sample)_R1.fastq) \
		   $(foreach sample,$(SAMPLES),kallisto/$(sample)/$(sample)_R2.fastq) \
		   $(foreach sample,$(SAMPLES),kallisto/$(sample)/abundance.tsv) \
		   kallisto/tpm_bygene.txt

SLEUTH_ANNOT ?= $(HOME)/share/lib/resource_files/Hugo_ENST_ensembl75_fixed.txt

PROJECT_DIR := $(notdir $(CURDIR))

define merge-fastq
kallisto/$1/$1_R1.fastq : $$(foreach split,$2,$$(word 1, $$(fq.$$(split))))
	$$(call RUN,-c -n 1 -s 0.5G -m 1G -w 2:00:00 -p $(PROJECT_DIR)/star -N $1/merge_R1,"set -o pipefail && \
																					    zcat $$(^) > $$(@)")
    
kallisto/$1/$1_R2.fastq : $$(foreach split,$2,$$(word 2, $$(fq.$$(split))))
	$$(call RUN,-c -n 1 -s 0.5G -m 1G -w 2:00:00 -p $(PROJECT_DIR)/star -N $1/merge_R2,"set -o pipefail && \
																					    zcat $$(^) > $$(@)")

endef
$(foreach sample,$(SAMPLES),\
        $(eval $(call merge-fastq,$(sample),$(split.$(sample)))))

define fastq-to-kallisto
kallisto/$1/abundance.tsv : kallisto/$1/$1_R1.fastq kallisto/$1/$1_R2.fastq
	$$(call RUN,-c -n 12 -s 2G -m 3G -v $(KALLISTO_ENV) -p $(PROJECT_DIR)/kallisto -N $1/quant,"set -o pipefail && \
																							    kallisto quant \
																							    -i $$(KALLISTO_INDEX) \
																							    -o kallisto/$1 \
																							    --bias \
																							    -b 100 \
																							    -t 12 \
																							    --fusion \
																							    $$(<) \
																							    $$(<<)")

endef
$(foreach sample,$(SAMPLES),\
		$(eval $(call fastq-to-kallisto,$(sample))))
		
kallisto/tpm_bygene.txt : $(foreach sample,$(SAMPLES),kallisto/$(sample)/abundance.tsv)
	$(call RUN, -c -n 24 -s 1G -m 2G -v $(KALLISTO_ENV) -p $(PROJECT_DIR)/kallisto -N summarize,"set -o pipefail && \
																							     $(RSCRIPT) $(SCRIPTS_DIR)/rna_seq/summarize_sleuth.R \
																							     --annotation $(SLEUTH_ANNOT) \
																							     --samples '$(SAMPLES)'")

..DUMMY := $(shell mkdir -p version; \
	$(SAMTOOLS) --version > version/kallisto_quant.txt; \
	~/share/env/kallisto-0.46.2/bin/kallisto version >> version/kallisto_quant.txt; \
	~/share/env/kallisto-0.46.2/bin/R --version >> version/kallisto_quant.txt;)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean:
	rm -f kallisto/*/*_R1.fastq
	rm -f kallisto/*/*_R2.fastq
	rm -f kallisto/*/abundance.tsv
	rm -f kallisto/*/abundance.h5
	rm -f kallisto/*/fusion.txt
	rm -f kallisto/*/run_info.json