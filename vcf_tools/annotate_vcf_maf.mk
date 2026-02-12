include weigelt-lab/Makefile.inc

LOGDIR ?= log/annotate_vcf_maf.$(NOW)

annotate : $(foreach sample,$(SAMPLES),maf/$(sample).maf)
      
PROJECT_DIR := $(notdir $(CURDIR))

define annotate-vcf-maf
maf/$1.maf : vcf/$1.vcf
	$$(call RUN,-c -n 12 -s 2G -m 4G -v $(VCF2MAF_ENV) -p $(PROJECT_DIR)/maf -N $1/vcf2maf,"set -o pipefail && \
												$$(VCF2MAF) \
												--input-vcf $$(<) \
												--output-maf $$(@) \
												--tmp-dir $$(TMPDIR) \
												--tumor-id $1 \
												--normal-id NA \
												--vep-path $$(VCF2MAF_ENV)/bin \
												--vep-data $$(HOME)/share/lib/resource_files/VEP/GRCh37/ \
												--vep-forks 12 \
												--ref-fasta $$(HOME)/share/lib/resource_files/VEP/GRCh37/homo_sapiens/99_GRCh37/Homo_sapiens.GRCh37.75.dna.primary_assembly.fa.gz \
												--filter-vcf $$(HOME)/share/lib/resource_files/VEP/GRCh37/homo_sapiens/99_GRCh37/ExAC_nonTCGA.r0.3.1.sites.vep.vcf.gz \
												--species homo_sapiens \
												--ncbi-build GRCh37 \
												--maf-center MSKCC && \
												rm -rf $$(TMPDIR)/$1.vep.vcf")
														   
endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call annotate-vcf-maf,$(sample))))

maf/summary.maf : $(foreach sample,$(SAMPLES),maf/$(sample).maf)
	$(call RUN, -c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/maf -N summary,"set -o pipefail && \
									    $(RSCRIPT) $(SCRIPTS_DIR)/vcf_tools/vcf2maf.R \
									    --option 1 \
									    --file_in $(^) \
									    --file_out $(@)")

..DUMMY := $(shell mkdir -p version; \
	$(VCF2MAF_ENV)/bin/vcf2maf.pl --help > version/annotate_vcf_maf.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY:
