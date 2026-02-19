include weigelt-lab/Makefile.inc

LOGDIR ?= log/scalpel_tumor_normal.$(NOW)

SCALPEL_NUM_CHUNKS = 100
SCALPEL_CHUNKS = $(shell seq -w 1 $(SCALPEL_NUM_CHUNKS))

vcf : scalpel/chunk_bed/taskcomplete.txt \
      $(foreach pair,$(SAMPLE_PAIRS),$(foreach n,$(SCALPEL_CHUNKS),scalpel/$(pair)/$(n)/main/somatic.indel.vcf)) \
      $(foreach pair,$(SAMPLE_PAIRS),scalpel/$(pair)/$(pair).vcf) \
      $(foreach pair,$(SAMPLE_PAIRS),scalpel/$(pair)/$(pair)_ft.vcf) \
      $(foreach pair,$(SAMPLE_PAIRS),scalpel/$(pair)/$(pair)_ft.uvcf) \
      $(foreach pair,$(SAMPLE_PAIRS),scalpel/$(pair)/$(pair)_ft.maf) \
      $(foreach pair,$(SAMPLE_PAIRS),scalpel/$(pair)/$(pair)_ft_ann.maf) \
      scalpel/mutation_summary.maf

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
											      mkdir -p scalpel/$1_$2/$3 && \
											      scalpel-discovery \
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

define aggregate-pair-vcf
scalpel/$1_$2/$1_$2.vcf : $(foreach pair,$(SAMPLE_PAIRS),$(foreach n,$(SCALPEL_CHUNKS),scalpel/$(pair)/$(n)/main/somatic.indel.vcf))
	$$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/scalpel -N $1_$2/aggregate-vcf,"set -o pipefail && \
											    $$(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/scalpel.R \
											    --option 2 \
											    --sample_name $1_$2 \
											    --chunks '$(SCALPEL_CHUNKS)' \
											    --file_out $$(@)")

scalpel/$1_$2/$1_$2_ft.vcf : scalpel/$1_$2/$1_$2.vcf
	$$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/scalpel -N $1_$2/filter-vcf,"set -o pipefail && \
											 $$(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/scalpel.R \
											 --option 3 \
											 --file_in $$(<) \
											 --file_out $$(@)")
											 
endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call aggregate-pair-vcf,$(tumor.$(pair)),$(normal.$(pair)))))
	
define annotate-pair-vcf
scalpel/$1_$2/$1_$2_ft.uvcf : scalpel/$1_$2/$1_$2_ft.vcf
	$$(call RUN,-c -n 1 -s 6G -m 12G -p $(PROJECT_DIR)/scalpel -N $1_$2/ups-indel -v $(UPSINDEL_ENV),"set -o pipefail && \
													  ups_indel $$(REF_FASTA) \
													  $$(<) \
													  scalpel/$1_$2/$1_$2_ft \
													  -hd=true")

scalpel/$1_$2/$1_$2_ft.maf : scalpel/$1_$2/$1_$2_ft.vcf
	$$(call RUN,-c -n 12 -s 2G -m 4G -v $(VCF2MAF_ENV) -p $(PROJECT_DIR)/scalpel -N $1_$2/vcf2maf ,"set -o pipefail && \
													$$(VCF2MAF) \
													--input-vcf $$(<) \
													--output-maf $$(@) \
													--tmp-dir $$(TMPDIR)/scalpel \
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
													rm -rf $$(TMPDIR)/scalpel/$1_$2_ft.vep.vcf")
														   
scalpel/$1_$2/$1_$2_ft_ann.maf : scalpel/$1_$2/$1_$2_ft.maf scalpel/$1_$2/$1_$2_ft.uvcf
	$$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/scalpel -N $1_$2/ann-maf,"set -o pipefail && \
										      $$(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/scalpel.R \
										      --option 4 \
										      --sample_name $1_$2 \
										      --file_out $$(@)")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call annotate-pair-vcf,$(tumor.$(pair)),$(normal.$(pair)))))

scalpel/mutation_summary.maf : $(foreach pair,$(SAMPLE_PAIRS),scalpel/$(pair)/$(pair)_ft_ann.maf)
	$(call RUN, -c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/scalpel -N summary,"set -o pipefail && \
										$(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/scalpel.R \
										--option 5 \
										--sample_name '$(SAMPLE_PAIRS)' \
										--file_out $(@)")

..DUMMY := $(shell mkdir -p version; \
	R --version >> version/scalpel_tumor_normal.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	rm -f scalpel/chunk_bed/* && \
	rm -rf scalpel/*/*/
	