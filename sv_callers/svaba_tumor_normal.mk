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
svaba/$1_$2/$1_$2.svaba.somatic.sv.vcf : bam/$1.bam bam/$2.bam
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

svaba/$1_$2/$1_$2.vcf : svaba/$1_$2/$1_$2.svaba.somatic.sv.vcf
	$$(call RUN,-c -n 1 -s 2G -m 4G -p $(PROJECT_DIR)/svaba -N $1_$2/copy -v $(SVABA_ENV),"set -o pipefail && \
											       cat $$(<) > $$(@)")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
		$(eval $(call svaba-tumor-normal,$(tumor.$(pair)),$(normal.$(pair)))))


..DUMMY := $(shell mkdir -p version; \
	$(SVABA_ENV)/bin/svaba --help &> version/svaba_tumor_normal.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	rm -f svaba/*/*.txt.gz && \
	rm -f svaba/*/*.bam && \
	rm -f svaba/*/*.log && \
	rm -f svaba/*/*.unfiltered.* && \
	rm -f svaba/*/*.germline.* && \
	rm -f svaba/*/*.svaba.somatic.indel.*
