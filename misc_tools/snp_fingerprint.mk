include weigelt-lab/Makefile.inc
include weigelt-lab/config/gatk.inc

LOGDIR ?= log/snp_fingeprint.$(NOW)

snp_fingeprint : $(foreach sample,$(SAMPLES),snp_fingeprint/$(sample).vcf) \
				 snp_fingeprint/summary.vcf \
				 snp_fingeprint/summary_ft.vcf \
				 snp_fingeprint/sample_clustering.pdf

ifneq ($(findstring IMPACT,$(TARGETS_FILE)),)
DBSNP_SUBSET = $(HOME)/share/lib/bed_files/dbsnp_137.b37.IMPACT.bed
else
DBSNP_SUBSET ?= $(HOME)/share/lib/bed_files/dbsnp_137.b37.EXOME.bed
endif
				 
PROJECT_DIR := $(notdir $(CURDIR))

define genotype-snps
snp_fingeprint/$1.vcf : bam/$1.bam
	$$(call RUN, -c -n 4 -s 2G -m 3G -p $(PROJECT_DIR)/snp_fingeprint -N $1/UnifiedGenotyper -w 24:00:00,"set -o pipefail && \
																										  $$(call GATK_CMD,8G) \
																										  -T UnifiedGenotyper \
																										  -rf BadCigar \
																										  -nt 4 \
																										  -R $(REF_FASTA) \
																										  --dbsnp $(DBSNP) \
																										  -I $$(<) \
																										  -L $(DBSNP_SUBSET) \
																										  -o $$(@) \
																										  --output_mode EMIT_ALL_SITES")

endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call genotype-snps,$(sample))))
	
snp_fingeprint/summary.vcf : $(foreach sample,$(SAMPLES),snp_fingeprint/$(sample).vcf)
	$(call RUN, -c -s 16G -m 20G -p $(PROJECT_DIR)/snp_fingeprint -N CombineVariants,"set -o pipefail && \
																					  $(call GATK_MEM,14G) \
																					  -T CombineVariants \
																					  $(foreach vcf,$^,--variant $(vcf) ) \
																					  -o $@ \
																					  --genotypemergeoption UNSORTED \
																					  -R $(REF_FASTA)")

snp_fingeprint/summary_ft.vcf : snp_fingeprint/summary.vcf
	$(INIT) grep '^#' $< > $@ && grep -e '0/1' -e '1/1' $< >> $@


..DUMMY := $(shell mkdir -p version; \
	echo "GATK" > version/snp_fingeprint.txt; \
	R --version >> version/snp_fingeprint.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: snp_fingeprint