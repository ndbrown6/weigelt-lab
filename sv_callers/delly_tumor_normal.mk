include weigelt-lab/Makefile.inc

LOGDIR = log/delly_tumor_normal.$(NOW)

vcf : $(foreach pair,$(SAMPLE_PAIRS),delly/$(pair)/$(pair).vcf) \
      $(foreach pair,$(SAMPLE_PAIRS),delly/$(pair)/$(pair).txt)

DELLY_CORES ?= 8
DELLY_MEM_CORE ?= 2G
DELLY_WALL_TIME ?= 2:00:00
DELLY_EXCLUDE ?= $(DELLY_ENV)/opt/delly/excludeTemplates/human.hg19.excl.tsv

PROJECT_DIR := $(notdir $(CURDIR))

define delly-tumor-normal
delly/$1_$2/samples.tsv :
	$$(call RUN,-c -n 1 -s 1G -m 2G -p $(PROJECT_DIR)/delly -N $1_$2/samples,"set -o pipefail && \
										  mkdir -p delly/$1_$2 && \
										  echo -e '$1\ttumor' > $$(@) && \
										  echo -e '$2\tcontrol' >> $$(@)")

delly/$1_$2/$1_$2.bcf : bam/$1.bam bam/$2.bam
	$$(call RUN,-c -n $(DELLY_CORES) -s 1G -m $(DELLY_MEM_CORE) -p $(PROJECT_DIR)/delly -N $1_$2/call -v $(DELLY_ENV) -w $(DELLY_WALL_TIME),"set -o pipefail && \
																		 delly call \
																		 -x $$(DELLY_EXCLUDE) \
																		 -o $$(@) \
																		 -g $$(REF_FASTA) \
																		 $$(<) \
																		 $$(<<)")

delly/$1_$2/$1_$2_ft.bcf : delly/$1_$2/$1_$2.bcf delly/$1_$2/samples.tsv
	$$(call RUN,-c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/delly -N $1_$2/filter -v $(DELLY_ENV),"set -o pipefail && \
												 delly filter \
												 -f somatic \
												 -s $$(<<) \
												 -o $$(@) \
												 $$(<)")

delly/$1_$2/$1_$2.vcf : delly/$1_$2/$1_$2_ft.bcf
	$$(call RUN,-c -n 1 -s 2G -m 4G -p $(PROJECT_DIR)/delly -N $1_$2/bcftools,"set -o pipefail && \
										   bcftools view -O v $$(<) > $$(@)")

delly/$1_$2/$1_$2.txt : delly/$1_$2/$1_$2.vcf
	$$(call RUN,-c -n 1 -s 4G -m 8G -p $(PROJECT_DIR) -N $1_$2/AnnotSV -v $(ANNOTATESV_ENV),"set -o pipefail && \
												 rm -f delly/$1_$2/$1_$2.tsv && \
												 if grep -v '^#' $$(<) | grep -q .; then \
												 	$$(ANNOTATE_SV) \
													-SVinputFile $$(<) \
													-outputFile ./delly/$1_$2/$1_$2.tsv \
													-genomeBuild GRCh37 && \
													mv ./delly/$1_$2/$1_$2.tsv $$(@); \
												else \
													echo 'No variants found in VCF, skipping annotation' && \
													touch $$(@); \
												fi")
												 
endef
$(foreach pair,$(SAMPLE_PAIRS),\
        $(eval $(call delly-tumor-normal,$(tumor.$(pair)),$(normal.$(pair)))))


.DUMMY := $(shell mkdir -p version; \
    $(DELLY_ENV)/bin/delly &> version/delly_tumor_normal.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :