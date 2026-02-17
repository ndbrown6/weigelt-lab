include weigelt-lab/Makefile.inc

LOGDIR ?= log/strelka_tumor_normal.$(NOW)

vcf : strelka/chunk_bed/target.bed.gz \
      $(foreach pair,$(SAMPLE_PAIRS),strelka/$(pair)/runWorkflow.py) \
      $(foreach pair,$(SAMPLE_PAIRS),strelka/$(pair)/$(pair).vcf) \
      $(foreach pair,$(SAMPLE_PAIRS),strelka/$(pair)/$(pair)_ft.vcf) \
      $(foreach pair,$(SAMPLE_PAIRS),strelka/$(pair)/$(pair)_ft.uvcf) \
      $(foreach pair,$(SAMPLE_PAIRS),strelka/$(pair)/$(pair)_ft.maf) \
      $(foreach pair,$(SAMPLE_PAIRS),strelka/$(pair)/$(pair)_ft_ann.maf) \
      strelka/mutation_summary.maf

PROJECT_DIR := $(notdir $(CURDIR))

strelka/chunk_bed/target.bed.gz : $(TARGETS_FILE)
	$(call RUN,-c -n 1 -s 2G -m 4G -p $(PROJECT_DIR) -N bed_file,"set -o pipefail && \
								      bgzip -c $(<) > $(@) && \
								      tabix $(@)")

define strelka-tumor-normal
strelka/$1_$2/runWorkflow.py : bam/$1.bam bam/$2.bam strelka/chunk_bed/target.bed.gz
	$$(call RUN,-c -n 1 -s 2G -m 4G -p $(PROJECT_DIR)/strelka -N $1_$2/configure -v $(STRELKA_ENV),"set -o pipefail && \
													rm -rf $$(@D) && \
													$$(CONFIGURE_STRELKA) \
													--tumorBam=$$(<) \
													--normalBam=$$(<<) \
													--referenceFasta=$$(REF_FASTA) \
													--callMemMb=1024 \
													--exome \
													--callRegions=$$(<<<) \
													--runDir=$$(@D)")

strelka/$1_$2/$1_$2.vcf : strelka/$1_$2/runWorkflow.py
	$$(call RUN,-c -n 10 -s 2G -m 4G -p $(PROJECT_DIR)/strelka -N $1_$2/run -v $(STRELKA_ENV),"set -o pipefail && \
												     strelka/$1_$2/runWorkflow.py \
												     -m local \
												     -j 10 \
												     -g 4 && \
												     gzip -dc strelka/$1_$2/results/variants/somatic.indels.vcf.gz > $$(@)")

strelka/$1_$2/$1_$2_ft.vcf : strelka/$1_$2/$1_$2.vcf
	$$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/strelka -N $1_$2/filter-vcf,"set -o pipefail && \
											 $$(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/strelka.R \
											 --option 1 \
											 --file_in $$(<) \
											 --file_out $$(@)")
											 
endef
$(foreach pair,$(SAMPLE_PAIRS),\
    $(eval $(call strelka-tumor-normal,$(tumor.$(pair)),$(normal.$(pair)))))
    
define annotate-pair-vcf
strelka/$1_$2/$1_$2_ft.uvcf : strelka/$1_$2/$1_$2_ft.vcf
	$$(call RUN,-c -n 1 -s 6G -m 12G -p $(PROJECT_DIR)/strelka -N $1_$2/ups-indel -v $(UPSINDEL_ENV),"set -o pipefail && \
													  ups_indel $$(REF_FASTA) \
													  $$(<) \
													  strelka/$1_$2/$1_$2_ft \
													  -hd=true")

strelka/$1_$2/$1_$2_ft.maf : strelka/$1_$2/$1_$2_ft.vcf
	$$(call RUN,-c -n 12 -s 2G -m 4G -v $(VCF2MAF_ENV) -p $(PROJECT_DIR)/strelka -N $1_$2/vcf2maf ,"set -o pipefail && \
													$$(VCF2MAF) \
													--input-vcf $$(<) \
													--output-maf $$(@) \
													--tmp-dir $$(TMPDIR) \
													--tumor-id $1 \
													--normal-id $2 \
													--vcf-tumor-id TUMOR \
													--vcf-normal-id NORMAL \
													--vep-path $$(VCF2MAF_ENV)/bin \
													--vep-data $$(HOME)/share/lib/resource_files/VEP/GRCh37/ \
													--vep-forks 12 \
													--ref-fasta $$(HOME)/share/lib/resource_files/VEP/GRCh37/homo_sapiens/99_GRCh37/Homo_sapiens.GRCh37.75.dna.primary_assembly.fa.gz \
													--filter-vcf $$(HOME)/share/lib/resource_files/VEP/GRCh37/homo_sapiens/99_GRCh37/ExAC_nonTCGA.r0.3.1.sites.vep.vcf.gz \
													--species homo_sapiens \
													--ncbi-build GRCh37 \
													--maf-center MSKCC && \
													rm -rf $$(TMPDIR)/$1_$2_ft.vep.vcf")
														   
strelka/$1_$2/$1_$2_ft_ann.maf : strelka/$1_$2/$1_$2_ft.maf strelka/$1_$2/$1_$2_ft.uvcf
	$$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/strelka -N $1_$2/ann-maf,"set -o pipefail && \
										      $$(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/strelka.R \
										      --option 2 \
										      --sample_name $1_$2 \
										      --file_out $$(@)")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call annotate-pair-vcf,$(tumor.$(pair)),$(normal.$(pair)))))
	

strelka/mutation_summary.maf : $(foreach pair,$(SAMPLE_PAIRS),strelka/$(pair)/$(pair)_ft_ann.maf)
	$(call RUN, -c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/strelka -N summary,"set -o pipefail && \
										$(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/strelka.R \
										--option 3 \
										--sample_name '$(SAMPLE_PAIRS)' \
										--file_out $(@)")


..DUMMY := $(shell mkdir -p version; \
	~/share/env/strelka-2.9.10/opt/strelka-2.9.10.centos6_x86_64/bin/configureStrelkaSomaticWorkflow.py --version > version/strelka_tumor_normal.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	rm -f strelka/chunk_bed/* && \
	rm -f strelka/*/*.py && \
	rm -f strelka/*/*.pickle && \
	rm -f strelka/*/*.txt && \
	rm -rf strelka/*/results && \
	rm -rf strelka/*/workspace
    