include weigelt-lab/Makefile.inc

LOGDIR ?= log/manta_tumor_normal.$(NOW)

vcf : $(foreach pair,$(SAMPLE_PAIRS),manta/$(pair)/runWorkflow.py)

PROJECT_DIR := $(notdir $(CURDIR))

define manta-tumor-normal
manta/$1_$2/runWorkflow.py : bam/$1.bam bam/$2.bam
	$$(call RUN,-c -n 1 -s 2G -m 4G -p $(PROJECT_DIR)/manta -N $1_$2/configure -v $(MANTA_ENV),"set -o pipefail && \
												    rm -rf $$(@D) && \
												    $$(CONFIGURE_MANTA) \
												    --tumorBam=$$(<) \
												    --normalBam=$$(<<) \
												    --referenceFasta=$$(REF_FASTA) \
												    --config= \
												    --runDir $$(@D)")

endef
$(foreach pair,$(SAMPLE_PAIRS), \
	$(eval $(call manta-tumor-normal,$(tumor.$(pair)),$(normal.$(pair)))))

..DUMMY := $(shell mkdir -p version; \
	python --version &> version/manta_tumor_normal.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY:
