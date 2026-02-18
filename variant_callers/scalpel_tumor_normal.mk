include weigelt-lab/Makefile.inc

LOGDIR ?= log/scalpel_tumor_normal.$(NOW)

SCALPEL_NUM_CHUNKS = 100
SCALPEL_CHUNKS = $(shell seq -w 1 $(SCALPEL_NUM_CHUNKS))

vcf : scalpel/chunk_bed/taskcomplete.txt \
      $(foreach pair,$(SAMPLE_PAIRS),$(foreach n,$(SCALPEL_CHUNKS),scalpel/$(pair)/$(n)/main/somatic.indel.vcf))
      
PROJECT_DIR := $(notdir $(CURDIR))

scalpel/chunk_bed/taskcomplete.txt : $(TARGETS_FILE)
	$(call RUN,-c -n 1 -s 4G -m 8G -p $(PROJECT_DIR) -N bed_file,"set -o pipefail && \
								      $(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/scalpel.R \
								      --option 1 \
								      --input $(<) \
								      --out_prefix chunk \
								      --num_chunks $(SCALPEL_NUM_CHUNKS) \
								      --output_dir scalpel/chunk_bed/ && \
								      echo 'completed!' > $(@)")

define scalpel-tumor-normal-chunk
scalpel/$1_$2/$3/main/somatic.indel.vcf : bam/$1.bam bam/$2.bam scalpel/chunk_bed/taskcomplete.txt
	$$(call RUN,-c -n 4 -s 2G -m 3G -v $(SCALPEL_ENV) -p $(PROJECT_DIR)/scalpel -N $1/$3,"set -o pipefail && \
											      scalpel-dsicovery \
											      --somatic \
											      --tumor $$(<) \
											      --normal $$(<<) \
											      --bed scalpel/chunk_bed/chunk$3.bed \
											      --ref $$(REF_FASTA) \
											      --format vcf \
											      --intarget \
											      --numprocs 4  \
											      --dir scalpel/$1_$2/$3/")
endef
$(foreach pair,$(SAMPLE_PAIRS), \
	$(foreach n,$(SCALPEL_CHUNKS), \
			$(eval $(call scalpel-tumor-normal-chunk,$(tumor.$(pair)),$(normal.$(pair)),$(n)))))

..DUMMY := $(shell mkdir -p version)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean
