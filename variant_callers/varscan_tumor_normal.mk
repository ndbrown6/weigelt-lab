include weigelt-lab/Makefile.inc

LOGDIR ?= log/varscan_tumor_normal.$(NOW)

VARSCAN_NUM_CHUNKS = 100
VARSCAN_CHUNKS = $(shell seq -w 1 $(VARSCAN_NUM_CHUNKS))

vcf : varscan/chunk_bed/taskcomplete.txt \
      $(foreach pair,$(SAMPLE_PAIRS),$(foreach n,$(VARSCAN_CHUNKS),varscan/$(pair)/$(pair)--$(n).indel.vcf)) \
      $(foreach pair,$(SAMPLE_PAIRS),varscan/$(pair)/$(pair).vcf) \
      $(foreach pair,$(SAMPLE_PAIRS),varscan/$(pair)/$(pair)_ft.vcf) \
      $(foreach pair,$(SAMPLE_PAIRS),varscan/$(pair)/$(pair)_ft.uvcf) \
      $(foreach pair,$(SAMPLE_PAIRS),varscan/$(pair)/$(pair)_ft.maf)
#      $(foreach pair,$(SAMPLE_PAIRS),varscan/$(pair)/$(pair)_ft_vt_ann.maf) \
#      varscan/mutation_summary.maf
	  
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
	$$(call RUN,-c -n 1 -s 9G -m 12G -v $(VARSCAN_ENV) -p $(PROJECT_DIR)/varscan -N $1/$3,"(set -o pipefail && \
											       tmp1=$$$$(mktemp) && \
											       tmp2=$$$$(mktemp) && \
											       $$(SAMTOOLS) mpileup -A -l varscan/chunk_bed/chunk$3.bed -q $$(MIN_MAP_QUAL) -f $$(REF_FASTA) $$(<)  > \$$$$tmp1 && \
											       $$(SAMTOOLS) mpileup -A -l varscan/chunk_bed/chunk$3.bed -q $$(MIN_MAP_QUAL) -f $$(REF_FASTA) $$(<<)  > \$$$$tmp2 && \
											       $$(VARSCAN) somatic \
											       \$$$$tmp2 \
											       \$$$$tmp1 \
											       $$(VARSCAN_OPTS) \
											       --output-snp varscan/$1_$2/$1_$2--$3.snp.vcf \
											       --output-indel varscan/$1_$2/$1_$2--$3.indel.vcf \
											       --output-vcf 1 && \
											       rm -f \$$$$tmp1 \$$$$tmp2)")
											       
endef
$(foreach pair,$(SAMPLE_PAIRS), \
	$(foreach n,$(VARSCAN_CHUNKS), \
			$(eval $(call varscan-tumor-normal-chunk,$(tumor.$(pair)),$(normal.$(pair)),$(n)))))
			
define aggregate-pair-vcf
varscan/$1_$2/$1_$2.vcf : $(foreach pair,$(SAMPLE_PAIRS),$(foreach n,$(VARSCAN_CHUNKS),varscan/$(pair)/$(pair)--$(n).indel.vcf))
	$$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/varscan -N $1_$2/aggregate-vcf,"set -o pipefail && \
											    $$(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/varscan.R \
											    --option 2 \
											    --sample_name $1_$2 \
											    --chunks '$(VARSCAN_CHUNKS)' \
											    --file_out $$(@)")

varscan/$1_$2/$1_$2_ft.vcf : varscan/$1_$2/$1_$2.vcf
	$$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/varscan -N $1_$2/filter-vcf,"set -o pipefail && \
											 $$(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/varscan.R \
											 --option 3 \
											 --file_in $$(<) \
											 --file_out $$(@)")
											 
endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call aggregate-pair-vcf,$(tumor.$(pair)),$(normal.$(pair)))))

define annotate-pair-vcf
varscan/$1_$2/$1_$2_ft.uvcf : varscan/$1_$2/$1_$2_ft.vcf
	$$(call RUN,-c -n 1 -s 6G -m 12G -p $(PROJECT_DIR)/varscan -N $1_$2/ups-indel -v $(UPSINDEL_ENV),"set -o pipefail && \
													  ups_indel $$(REF_FASTA) \
													  $$(<) \
													  varscan/$1_$2/$1_$2_ft \
													  -hd=true")

varscan/$1_$2/$1_$2_ft.maf : varscan/$1_$2/$1_$2_ft.vcf
	$$(call RUN,-c -n 12 -s 2G -m 4G -v $(VCF2MAF_ENV) -p $(PROJECT_DIR)/varscan -N $1_$2/vcf2maf ,"set -o pipefail && \
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
														   
varscan/$1_$2/$1_$2_ft_ann.maf : varscan/$1_$2/$1_$2_ft.maf
	$$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/varscan -N $1_$2/ann-maf,"set -o pipefail && \
										      $$(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/varscan.R \
										      --option 4 \
										      --file_in $$(<) \
										      --file_out $$(@)")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call annotate-pair-vcf,$(tumor.$(pair)),$(normal.$(pair)))))

varscan/mutation_summary.maf : $(foreach pair,$(SAMPLE_PAIRS),varscan/$(pair)/$(pair)_ft_ann.maf)
	$(call RUN, -c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/varscan -N summary,"set -o pipefail && \
										$(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/varscan.R \
										--option 5 \
										--sample_name '$(SAMPLE_PAIRS)' \
										--file_out $(@)")

..DUMMY := $(shell mkdir -p version; \
	$(VARSCAN_ENV)/bin/varscan --version &> version/varscan_tumor_normal.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	rm -f varscan/chunk_bed/* && \
	rm -f varscan/*/*--*.vcf
