include weigelt-lab/Makefile.inc

LOGDIR ?= log/strelka_tumor_normal.$(NOW)

vcf : strelka/chunk_bed/target.bed.gz

PROJECT_DIR := $(notdir $(CURDIR))

strelka/chunk_bed/target.bed.gz : $(TARGETS_FILE)
	$(call RUN,-c -n 1 -s 4G -m 8G -p $(PROJECT_DIR) -N bed_file,"set -o pipefail && \
								      bgzip -c $(<) > $(@) && \
								      tabix $(@)")

define strelka-tumor-normal
strelka/$1_$2/runWorkflow.py : bam/$1.bam bam/$2.bam strelka/chunk_bed/target.bed.gz
	$$(call RUN,-c -n 1 -s 2G -m 4G -p $(PROJECT_DIR)/strelka -N $1_$2/configure -v $(STRELKA_ENV),"set -o pipefail && \
													rm -rf $$(@D) && \
													$$(CONFIGURE_STRELKA) \
													--callRegions $$(<<<) \
													--normalBam $$(<<) \
													--tumorBam $$(<) \
													--referenceFasta $$(REF_FASTA) \
													--runDir $$(@D)")

strelka/$1_$2/task.complete : strelka/$1_$2/Makefile
	$$(call RUN,-c -n 10 -s 1G -m 1.5G -p $(PROJECT_DIR)/strelka -N $1_$2/run,"set -o pipefail && \
										   strelka/$1_$2/runWorkflow.py -m local -j 10 && \
										   touch $$(@)")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
    $(eval $(call strelka-tumor-normal,$(tumor.$(pair)),$(normal.$(pair)))))


..DUMMY := $(shell mkdir -p version; \
	$(CONFIGURE_STRELKA) --version > version/strelka_tumor_normal.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	rm -rf strelka/*/Makefile
    