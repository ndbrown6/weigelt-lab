include weigelt-lab/Makefile.inc

LOGDIR ?= log/mutect_tumor_normal.$(NOW)

MUTECT_NUM_CHUNKS = 100
MUTECT_CHUNKS = $(shell seq -w 1 $(MUTECT_NUM_CHUNKS))

vcf : mutect/chunk_bed/taskcomplete.txt

MUTECT_MAX_ALT_IN_NORMAL ?= 500
MUTECT_MAX_ALT_IN_NORMAL_FRACTION ?= 0.05
MUTECT_FILTERS = DuplicateRead FailsVendorQualityCheck NotPrimaryAlignment BadMate MappingQualityUnavailable UnmappedRead BadCigar
MUTECT_OPTS ?= --enable_extended_output --max_alt_alleles_in_normal_count $(MUTECT_MAX_ALT_IN_NORMAL) \
	       --max_alt_allele_in_normal_fraction $(MUTECT_MAX_ALT_IN_NORMAL_FRACTION) -R $(REF_FASTA) \
	       --dbsnp $(DBSNP) $(foreach ft,$(MUTECT_FILTERS),-rf $(ft))

PROJECT_DIR := $(notdir $(CURDIR))

ifdef TARGETS_FILE
mutect/bed_files/taskcomplete.txt : $(TARGETS_FILE)
	$(call RUN,-c -n 1 -s 4G -m 8G -p $(PROJECT_DIR) -N bed_files,"set -o pipefail && \
								       $(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/mutect.R \
								       --option 1 \
								       --input $(<) \
								       --out_prefix 'chunk' \
								       --num_chunks $(MUTECT_NUM_CHUNKS) \
								       --output_dir 'mutect/chunk_bed/'")

else

endif

..DUMMY := $(shell mkdir -p version; \
	$(MUTECT_ENV)/bin/mutect --version &> version/mutect.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	rm -rf mutect/chunk_bed/	