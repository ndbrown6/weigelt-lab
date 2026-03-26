include weigelt-lab/Makefile.inc

LOGDIR ?= log/platypus_tumor_normal.$(NOW)

PLATYPUS_CHUNKS := $(shell seq 1 22) X Y

vcf : $(foreach pair,$(SAMPLE_PAIRS),$(foreach n,$(PLATYPUS_CHUNKS),platypus/$(pair)/$(pair)--$(n).vcf)) \
      $(foreach pair,$(SAMPLE_PAIRS),platypus/$(pair)/$(pair).vcf) \
      $(foreach pair,$(SAMPLE_PAIRS),platypus/$(pair)/$(pair)_ft.vcf) \
      $(foreach pair,$(SAMPLE_PAIRS),platypus/$(pair)/$(pair)_ft.uvcf) \
      $(foreach pair,$(SAMPLE_PAIRS),platypus/$(pair)/$(pair)_ft.maf) \
      $(foreach pair,$(SAMPLE_PAIRS),platypus/$(pair)/$(pair)_ft_ann.maf) \
      platypus/mutation_summary.maf

PROJECT_DIR := $(notdir $(CURDIR))

define platypus-tumor-normal-chunk
platypus/$1_$2/$1_$2--$3.vcf : bam/$1.bam bam/$2.bam
	$$(call RUN,-c -n 4 -s 2G -m 3G -v $(PLATYPUS_ENV) -p $(PROJECT_DIR)/platypus -N $1/$3,"set -o pipefail && \
																							platypus callVariants \
																							--refFile=$$(REF_FASTA) \
																							--regions=$3 \
																							--bamFiles=$$(<)$$(,)$$(<<) \
																							--logFileName=platypus/$1_$2/$1_$2--$3.log \
																							--nCPU=4 \
																							--skipDifficultWindows=1 \
																							--genSNPs=0 \
																							--genIndels=1 \
																							--mergeClusteredVariants=1 \
																							--trimOverlapping=1 \
																							--trimAdapter=1 \
																							--trimSoftClipped=1 \
																							--output=$$(@)")

endef
$(foreach pair,$(SAMPLE_PAIRS), \
	$(foreach n,$(PLATYPUS_CHUNKS), \
			$(eval $(call platypus-tumor-normal-chunk,$(tumor.$(pair)),$(normal.$(pair)),$(n)))))

define aggregate-pair-vcf
platypus/$1_$2/$1_$2.vcf : $(foreach pair,$(SAMPLE_PAIRS),$(foreach n,$(PLATYPUS_CHUNKS),platypus/$(pair)/$(pair)--$(n).vcf))
	$$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/platypus -N $1_$2/aggregate-vcf,"set -o pipefail && \
																					     $$(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/platypus.R \
																					     --option 1 \
																					     --sample_name $1_$2 \
																					     --chunks '$(PLATYPUS_CHUNKS)' \
																					     --file_out $$(@)")

platypus/$1_$2/$1_$2_ft.vcf : platypus/$1_$2/$1_$2.vcf $(TARGETS_FILE)
	$$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/platypus -N $1_$2/filter-vcf,"set -o pipefail && \
																					  $$(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/platypus.R \
																					  --option 2 \
																					  --input $$(<<) \
																					  --file_in $$(<) \
																					  --file_out platypus/$1_$2/$1_$2_fx.vcf && \
																					  bash weigelt-lab/dodo-cloning-kit/variant_callers/platypus.sh platypus/$1_$2/$1_$2_fx.vcf $$(@)")
											 
endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call aggregate-pair-vcf,$(tumor.$(pair)),$(normal.$(pair)))))

define annotate-pair-vcf
platypus/$1_$2/$1_$2_ft.uvcf : platypus/$1_$2/$1_$2_ft.vcf
	$$(call RUN,-c -n 1 -s 4G -m 8G -v $(UPSINDEL_ENV) -p $(PROJECT_DIR)/platypus -N $1_$2/ups-indel,"set -o pipefail && \
																									  $$(call CHECK_UVCF,ups_indel $$(REF_FASTA) $$(<) platypus/$1_$2/$1_$2_ft -hd=true)")
																									   
platypus/$1_$2/$1_$2_ft.maf : platypus/$1_$2/$1_$2_ft.vcf
	$$(call RUN,-c -n 12 -s 1G -m 2G -v $(VCF2MAF_ENV) -p $(PROJECT_DIR)/platypus -N $1_$2/vcf2maf ,"set -o pipefail && \
																									 $$(VCF2MAF) \
																									 --input-vcf $$(<) \
																									 --output-maf $$(@) \
																									 --tmp-dir $$(TMPDIR)/platypus \
																									 --tumor-id $1 \
																									 --normal-id $2 \
																									 --vcf-tumor-id $1 \
																									 --vcf-normal-id $2 \
																									 --vep-path $$(VCF2MAF_ENV)/bin \
																									 --vep-data $$(HOME)/share/lib/resource_files/VEP/GRCh37/ \
																									 --vep-forks 12 \
																									 --ref-fasta $$(HOME)/share/lib/resource_files/VEP/GRCh37/homo_sapiens/99_GRCh37/Homo_sapiens.GRCh37.75.dna.primary_assembly.fa.gz \
																									 --filter-vcf $$(HOME)/share/lib/resource_files/VEP/GRCh37/homo_sapiens/99_GRCh37/ExAC_nonTCGA.r0.3.1.sites.vep.vcf.gz \
																									 --species homo_sapiens \
																									 --ncbi-build GRCh37 \
																									 --maf-center MSKCC && \
																									 rm -rf $$(TMPDIR)/platypus/$1_$2_ft.vep.vcf")
														   
platypus/$1_$2/$1_$2_ft_ann.maf : platypus/$1_$2/$1_$2_ft.maf platypus/$1_$2/$1_$2_ft.uvcf
	$$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/platypus -N $1_$2/ann-maf,"set -o pipefail && \
																			       $$(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/platypus.R \
																			       --option 3 \
																			       --sample_name $1_$2 \
																			       --file_out $$(@)")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call annotate-pair-vcf,$(tumor.$(pair)),$(normal.$(pair)))))

platypus/mutation_summary.maf : $(foreach pair,$(SAMPLE_PAIRS),platypus/$(pair)/$(pair)_ft_ann.maf)
	$(call RUN, -c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/platypus -N summary,"set -o pipefail && \
																			 $(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/platypus.R \
																			 --option 4 \
																			 --sample_name '$(SAMPLE_PAIRS)' \
																			 --file_out $(@)")

..DUMMY := $(shell mkdir -p version; \
	R --version >> version/platypus_tumor_normal.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: vcf clean

clean :
	rm -f platypus/*/*--*.log && \
	rm -f platypus/*/*--*.vcf && \
	rm -f platypus/*/*_fx.vcf