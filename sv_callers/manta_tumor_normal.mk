include weigelt-lab/Makefile.inc

LOGDIR ?= log/manta_tumor_normal.$(NOW)

vcf : $(foreach pair,$(SAMPLE_PAIRS),manta/$(pair)/$(pair).vcf)

MANTA_CORES ?= 10
MANTA_MEM_CORE ?= 4G
MANTA_WALL_TIME ?= 24:00:00

PROJECT_DIR := $(notdir $(CURDIR))

define manta-tumor-normal
manta/$1_$2/runWorkflow.py : bam/$1.bam bam/$2.bam
	$$(call RUN,-c -n 1 -s 2G -m 4G -p $(PROJECT_DIR)/manta -N $1_$2/configure -v $(MANTA_ENV),"set -o pipefail && \
																							    rm -rf $$(@D) && \
																							    $$(CONFIGURE_MANTA) \
																							    --tumorBam=$$(<) \
																							    --normalBam=$$(<<) \
																							    --referenceFasta=$$(REF_FASTA) \
																							    --config=$(MANTA_ENV)/opt/manta-0.29.6.centos5_x86_64/bin/configManta.py.ini \
																							    --runDir $$(@D)")

manta/$1_$2/results/variants/somaticSV.vcf.gz : manta/$1_$2/runWorkflow.py
	$$(call RUN,-c -n $(MANTA_CORES) -s 2G -m $(MANTA_MEM_CORE) -p $(PROJECT_DIR)/manta -N $1_$2/run -v $(MANTA_ENV) -w $(MANTA_WALL_TIME),"set -o pipefail && \
																																			manta/$1_$2/runWorkflow.py \
																																			-m local \
																																			-j 10 \
																																			-g 4")
																		
manta/$1_$2/$1_$2.vcf : manta/$1_$2/results/variants/somaticSV.vcf.gz
	$$(call RUN,-c -n 1 -s 2G -m 4G -p $(PROJECT_DIR)/manta -N $1_$2/gzip -v $(MANTA_ENV),"set -o pipefail && \
																					       gzip -dc $$(<) > $$(@)"

endef
$(foreach pair,$(SAMPLE_PAIRS), \
	$(eval $(call manta-tumor-normal,$(tumor.$(pair)),$(normal.$(pair)))))


..DUMMY := $(shell mkdir -p version; \
	python --version &> version/manta_tumor_normal.txt; \
	$(MANTA_ENV)/opt/manta-0.29.6.centos5_x86_64/bin/configManta.py --version >> version/manta_tumor_normal.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	rm -rf manta/*/results && \
	rm -rf manta/*/workspace && \
	rm -f manta/*/workflow.*.txt && \
	rm -f manta/*/runWorkflow.py && \
	rm -f manta/*/runWorkflow.py.config.pickle