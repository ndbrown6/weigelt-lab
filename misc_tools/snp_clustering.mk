include weigelt-lab/Makefile.inc
include weigelt-lab/config/gatk.inc

LOGDIR ?= log/snp_clustering.$(NOW)

ifneq ($(findstring IMPACT,$(TARGETS_FILE)),)
DBSNP_SUBSET = $(HOME)/share/lib/bed_files/dbsnp_137.b37_impact.bed
else
DBSNP_SUBSET ?= $(HOME)/share/lib/bed_files/dbsnp_137.b37_exome.bed
endif

clustering : $(foreach sample,$(SAMPLES),sample_vcf/$(sample).vcf)
#			 sample_vcf/summary.vcf \
#			 sample_vcf/summary_ft.vcf \
#			 sample_vcf/sample_clustering.pdf
				 
PROJECT_DIR := $(notdir $(CURDIR))

define genotype-snps
sample_vcf/$1.vcf : bam/$1.bam
	$$(call RUN, -c -n 4 -s 2.5G -m 3G -p $(PROJECT_DIR)/sample_vcf -N $1/GATK,"set -o pipefail && \
																				$$(call GATK_MEM,8G) \
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


..DUMMY := $(shell mkdir -p version; \
	echo "GATK" > version/snp_clustering.txt; \
	R --version >> version/snp_clustering.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clustering