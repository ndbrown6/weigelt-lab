include weigelt-lab/Makefile.inc

LOGDIR = log/gridss_tumor_normal.$(NOW)

vcf : $(foreach pair,$(SAMPLE_PAIRS),gridss/$(pair)/$(pair).gridss_sv.vcf) \
      $(foreach pair,$(SAMPLE_PAIRS),gridss/$(pair)/$(pair).gridss_sv_ft.vcf.bgz) \
      $(foreach pair,$(SAMPLE_PAIRS),gridss/$(pair)/$(pair).vcf)
      
GRIDSS_CORES ?= 8
GRIDSS_MEM_CORE ?= 6G
GRIDSS_WALL_TIME ?= 48:00:00
GRIDSS_BLACKLIST ?= $(HOME)/share/lib/resource_files/gridss/example/ENCFF001TDO.bed
GRIDSS_PON_DIR ?= $(HOME)/share/lib/resource_files/gridss/pon/

PROJECT_DIR := $(notdir $(CURDIR))

define gridss-tumor-normal
gridss/$1_$2/$1_$2.gridss_sv.vcf : bam/$1.bam bam/$2.bam
	$$(call RUN,-c -n $(GRIDSS_CORES) -s 4G -m $(GRIDSS_MEM_CORE) -p $(PROJECT_DIR)/gridss -N $1_$2/run -v $(GRIDSS_ENV) -w $(GRIDSS_WALL_TIME),"set -o pipefail && \
																		     mkdir -p gridss/$1_$2 && \
																		     cd gridss/$1_$2 && \
																		     gridss \
																		     -t $$(GRIDSS_CORES) \
																		     -r $$(REF_FASTA) \
																		     -o $1_$2.gridss_sv.vcf \
																		     -b $$(GRIDSS_BLACKLIST) \
																		     ../../bam/$2.bam \
																		     ../../bam/$1.bam")
												    
gridss/$1_$2/$1_$2.gridss_sv_ft.vcf.bgz : gridss/$1_$2/$1_$2.gridss_sv.vcf
	$$(call RUN,-c -n 1 -s 12G -m 18G -p $(PROJECT_DIR)/gridss -N $1_$2/filter -v $(GRIDSS_ENV),"set -o pipefail && \
												     cd gridss/$1_$2 && \
												     gridss_somatic_filter \
												     --pondir $$(GRIDSS_PON_DIR) \
												     --input $1_$2.gridss_sv.vcf \
												     --output $1_$2.gridss_sv_ft.vcf \
												     --fulloutput $1_$2.gridss_sv_high_and_low_confidence_somatic.vcf \
												     -n 1 \
												     -t 2")

gridss/$1_$2/$1_$2.vcf : gridss/$1_$2/$1_$2.gridss_sv_ft.vcf.bgz
	$$(call RUN, -c -n 1 -s 2G -m 4G -p $(PROJECT_DIR)/gridss -N $1_$2/unzip -v $(GRIDSS_ENV),"set -o pipefail && \
												   zcat $$(<) > $$(@)")
	
endef
$(foreach pair,$(SAMPLE_PAIRS),\
		$(eval $(call gridss-tumor-normal,$(tumor.$(pair)),$(normal.$(pair)))))


..DUMMY := $(shell mkdir -p version; \
	     echo 'gridss' > version/gridss_tumor_normal.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	rm -f gridss/*/*/*.bam && \
	rm -f gridss/*/*/*.bai
