include weigelt-lab/Makefile.inc

LOGDIR ?= log/annotate_maf_vcf.$(NOW)

annotate : $(foreach sample,$(SAMPLES),vcf/$(sample).vcf)

PROJECT_DIR := $(notdir $(CURDIR))

define annotate-maf-vcf
vcf/$1.vcf : maf/$1.maf
	$$(call RUN,-c -n 1 -s 4G -m 8G -v $(VCF2MAF_ENV) -p $(PROJECT_DIR)/vcf -N $1/maf2vcf,"set -o pipefail && \
																					       $$(MAF2VCF) \
																					       --input-maf $$(<) \
																					       --output-dir vcf \
																					       --output-vcf $1.vcf \
																					       --ref-fasta $$(HOME)/share/lib/resource_files/VEP/GRCh37/homo_sapiens/99_GRCh37/Homo_sapiens.GRCh37.75.dna.primary_assembly.fa.gz")

endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call annotate-maf-vcf,$(sample))))

							  
..DUMMY := $(shell mkdir -p version; \
	$(VCF2MAF_ENV)/bin/maf2vcf.pl --help > version/annotate_maf_vcf.txt; \
	R --version >> version/annotate_maf_vcf.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: annotate
