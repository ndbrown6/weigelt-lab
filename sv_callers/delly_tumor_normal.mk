include weigelt-lab/Makefile.inc

LOGDIR = log/delly_tumor_normal.$(NOW)

vcf : $(foreach pair,$(SAMPLE_PAIRS),delly/$(pair)/$(pair).bcf)

DELLY_CORES ?= 8
DELLY_MEM_CORE ?= 8G
DELLY_WALL_TIME ?= 48:00:00
DELLY_EXCLUDE ?= $(DELLY_ENV)/opt/delly/excludeTemplates/human.hg19.excl.tsv

PROJECT_DIR := $(notdir $(CURDIR))

define delly-tumor-normal
delly/$1_$2/$1_$2.bcf : bam/$1.bam bam/$2.bam
	$$(call RUN,-c -n $(DELLY_CORES) -s 4G -m $(DELLY_MEM_CORE) -p $(PROJECT_DIR)/delly -N $1_$2/call -v $(DELLY_ENV) -w $(DELLY_WALL_TIME),"set -o pipefail && \
																		 mkdir -p delly/$1_$2 && \
																		 delly call \
																		 -x $$(DELLY_EXCLUDE) \
																		 -o $$(@) \
																		 -g $$(REF_FASTA) \
																		 $$(<) \
																		 $$(<<)")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
		$(eval $(call delly-tumor-normal,$(tumor.$(pair)),$(normal.$(pair)))))


..DUMMY := $(shell mkdir -p version; \
	$(DELLY_ENV)/bin/delly &> version/delly_tumor_normal.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
