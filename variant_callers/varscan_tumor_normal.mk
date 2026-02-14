include weigelt-lab/Makefile.inc

LOGDIR ?= log/varscan_tumor_normal.$(NOW)

VARSCAN_NUM_CHUNKS = 100
VARSCAN_CHUNKS = $(shell seq -w 1 $(VARSCAN_NUM_CHUNKS))

vcf : varscan/chunk_bed/taskcomplete.txt \
      $(foreach pair,$(SAMPLE_PAIRS),$(foreach n,$(VARSCAN_CHUNKS),varscan/$(pair)/$(pair)--$(n).indel.vcf))
	  
FP_FILTER = $(PERL) $(HOME)/share/usr/bin/fpfilter.pl
BAM_READCOUNT = $(HOME)/share/usr/bin/bam-readcount
VARSCAN_TO_VCF = $(PERL) modules/variant_callers/somatic/varscanTNtoVcf.pl

MIN_MAP_QUAL ?= 1
IGNORE_FP_FILTER ?= true
VALIDATION ?= false
MIN_VAR_FREQ ?= $(if $(findstring false,$(VALIDATION)),0.05,0.000001)
VARSCAN_OPTS = $(if $(findstring true,$(VALIDATION)),--validation 1 --strand-filter 0) --min-var-freq $(MIN_VAR_FREQ)

PROJECT_DIR := $(notdir $(CURDIR))

varscan/chunk_bed/taskcomplete.txt : $(TARGETS_FILE)
	$(call RUN,-c -n 1 -s 4G -m 8G -p $(PROJECT_DIR) -N bed_file,"set -o pipefail && \
								      $(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/varscan.R \
								      --option 1 \
								      --input $(<) \
								      --out_prefix chunk \
								      --num_chunks $(VARSCAN_NUM_CHUNKS) \
								      --output_dir varscan/chunk_bed/ && \
								      echo 'completed!' > $(@)")


define varscan-tumor-normal-chunk
varscan/$1_$2/$1_$2--$3.indel.vcf : bam/$1.bam bam/$2.bam varscan/chunk_bed/taskcomplete.txt
	$$(call RUN,-c -n 1 -s 9G -m 12G -v $(VARSCAN_ENV) -p $(PROJECT_DIR)/varscan -N $1/$3,"set -o pipefail && \
											       tmp1=$$$$(mktemp) && \
											       tmp2=$$$$(mktemp) && \
											       $$(SAMTOOLS) mpileup -A -l varscan/chunk_bed/chunk$3.bed -q $$(MIN_MAP_QUAL) -f $$(REF_FASTA) $$(<)  > $$$$tmp1 && \
											       $$(SAMTOOLS) mpileup -A -l varscan/chunk_bed/chunk$3.bed -q $$(MIN_MAP_QUAL) -f $$(REF_FASTA) $$(<<)  > $$$$tmp2 && \
											       $$(VARSCAN) somatic \
											       $$$$tmp2 \
											       $$$$tmp1 \
											       $$(VARSCAN_OPTS) \
											       --output-snp varscan/$1_$2/$1_$2--$3.snp.vcf \
											       --output-indel varscan/$1_$2/$1_$2--$3.indel.vcf \
											       --output-vcf 1 && \
											       rm -f $$$$tmp1 $$$$tmp2")
											       
endef
$(foreach pair,$(SAMPLE_PAIRS), \
	$(foreach n,$(VARSCAN_CHUNKS), \
			$(eval $(call varscan-tumor-normal-chunk,$(tumor.$(pair)),$(normal.$(pair)),$(n)))))


..DUMMY := $(shell mkdir -p version; \
	$(VARSCAN_ENV)/bin/varscan --version &> version/varscan_tumor_normal.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	rm -f varscan/chunk_bed/*
