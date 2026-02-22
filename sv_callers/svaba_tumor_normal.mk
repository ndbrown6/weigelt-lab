include weigelt-lab/Makefile.inc

LOGDIR = log/svaba_tumor_normal.$(NOW)

vcf : $(foreach pair,$(SAMPLE_PAIRS),svaba/$(pair)/$(pair).vcf)

SVABA_CORES ?= 8
SVABA_MEM_CORE ?= 8G
SVABA_WALL_TIME ?= 48:00:00
SVABA_DBSNP ?= $(HOME)/share/lib/resource_files/svaba/dbsnp_indel.vcf
SVABA_BLACKLIST ?= $(HOME)/share/lib/resource_files/svaba/wgs_blacklist_meres.bed

PROJECT_DIR := $(notdir $(CURDIR))

define svaba-tumor-normal
svaba/$1_$2/$1_$2.vcf : bam/$1.bam bam/$2.bam
	$$(call RUN,-c -n $(SVABA_CORES) -s 4G -m $(SVABA_MEM_CORE) -p $(PROJECT_DIR)/svaba -N $1_$2/run -v $(SVABA_ENV) -w $(SVABA_WALL_TIME),"set -o pipefail && \
																		mkdir -p svaba/$1_$2 && \
																		cd svaba/$1_$2 && \
																		svaba run \
																		-t ../../bam/$1.bam \
																		-n ../../bam/$2.bam \
																		-p $$(SVABA_CORES) \
																		-D $$(SVABA_DBSNP) \
																		-L 100000 \
																		-x 25000 \
																		-k $$(SVABA_BLACKLIST) \
																		-a $1_$2 \
																		-G $$(REF_FASTA)")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
		$(eval $(call svaba-tumor-normal,$(tumor.$(pair)),$(normal.$(pair)))))


..DUMMY := $(shell mkdir -p version; \
	$(SVABA_ENV)/bin/svaba --help &> version/svaba_tumor_normal.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
