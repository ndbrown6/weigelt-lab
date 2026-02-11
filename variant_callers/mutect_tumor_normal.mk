include weigelt-lab/Makefile.inc

LOGDIR ?= log/mutect_tumor_normal.$(NOW)

MUTECT_NUM_CHUNKS = 100
MUTECT_CHUNKS = $(shell seq -w 1 $(MUTECT_NUM_CHUNKS))

vcf : mutect/chunk_bed/taskcomplete.txt \
      $(foreach pair,$(SAMPLE_PAIRS),$(foreach n,$(MUTECT_CHUNKS),mutect/$(pair)/$(pair)--$(n).vcf)) \
      $(foreach pair,$(SAMPLE_PAIRS),mutect/$(pair)/$(pair).vcf) \
      $(foreach pair,$(SAMPLE_PAIRS),mutect/$(pair)/$(pair).txt) \
      $(foreach pair,$(SAMPLE_PAIRS),mutect/$(pair)/$(pair)_ft.vcf) \
      $(foreach pair,$(SAMPLE_PAIRS),mutect/$(pair)/$(pair)_ft.maf)
      

MUTECT_MAX_ALT_IN_NORMAL ?= 500
MUTECT_MAX_ALT_IN_NORMAL_FRACTION ?= 0.05
MUTECT_FILTERS = DuplicateRead \
		 FailsVendorQualityCheck \
		 NotPrimaryAlignment \
		 BadMate \
		 MappingQualityUnavailable \
		 UnmappedRead BadCigar
MUTECT_OPTS ?= --enable_extended_output \
	       --max_alt_alleles_in_normal_count $(MUTECT_MAX_ALT_IN_NORMAL) \
	       --max_alt_allele_in_normal_fraction $(MUTECT_MAX_ALT_IN_NORMAL_FRACTION) \
	       -R $(REF_FASTA) \
	       --dbsnp $(DBSNP_GMAF) \
	       $(foreach ft,$(MUTECT_FILTERS),-rf $(ft))

PROJECT_DIR := $(notdir $(CURDIR))

mutect/chunk_bed/taskcomplete.txt : $(TARGETS_FILE)
	$(call RUN,-c -n 1 -s 4G -m 8G -p $(PROJECT_DIR) -N bed_file,"set -o pipefail && \
								      $(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/mutect.R \
								      --option 1 \
								      --input $(<) \
								      --out_prefix chunk \
								      --num_chunks $(MUTECT_NUM_CHUNKS) \
								      --output_dir mutect/chunk_bed/ && \
								      echo 'completed!' > $(@)")
								      
define mutect-tumor-normal-chunk
mutect/$1_$2/$1_$2--$3.vcf : bam/$1.bam bam/$2.bam mutect/chunk_bed/taskcomplete.txt
	$$(call RUN,-c -n 1 -s 6G -m 8G -v $(MUTECT_ENV) -p $(PROJECT_DIR)/mutect -N $1/$3,"set -o pipefail && \
											    $$(MUTECT) \
											    --analysis_type MuTect \
											    $(MUTECT_OPTS) \
											    --tumor_sample_name $1 \
											    --normal_sample_name $2 \
											    --intervals mutect/chunk_bed/chunk$3.bed \
											    -I:tumor $$(<) \
											    -I:normal $$(<<) \
											    -vcf $$(@) \
											    --out mutect/$1_$2/$1_$2--$3.txt \
											    --coverage_file mutect/$1_$2/$1_$2--$3.wig")
endef
$(foreach pair,$(SAMPLE_PAIRS), \
	$(foreach n,$(MUTECT_CHUNKS), \
			$(eval $(call mutect-tumor-normal-chunk,$(tumor.$(pair)),$(normal.$(pair)),$(n)))))

define aggregate-pair-vcf
mutect/$1_$2/$1_$2.vcf : $(foreach pair,$(SAMPLE_PAIRS),$(foreach n,$(MUTECT_CHUNKS),mutect/$(pair)/$(pair)--$(n).vcf))
	$$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/mutect -N $1_$2/aggregate-vcf,"set -o pipefail && \
											   $$(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/mutect.R \
											   --option 2 \
											   --sample_name $1_$2 \
											   --chunks '$(MUTECT_CHUNKS)' \
											   --file_out $$(@)")

mutect/$1_$2/$1_$2.txt : $(foreach pair,$(SAMPLE_PAIRS),$(foreach n,$(MUTECT_CHUNKS),mutect/$(pair)/$(pair)--$(n).vcf))
	$$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/mutect -N $1_$2/aggregate-txt,"set -o pipefail && \
											   $$(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/mutect.R \
											   --option 3 \
											   --sample_name $1_$2 \
											   --chunks '$(MUTECT_CHUNKS)' \
											   --file_out $$(@)")

mutect/$1_$2/$1_$2_ft.vcf : mutect/$1_$2/$1_$2.vcf
	$$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/mutect -N $1_$2/filter-vcf,"set -o pipefail && \
											$$(RSCRIPT) $(SCRIPTS_DIR)/variant_callers/mutect.R \
											--option 4 \
											--file_in $$(<) \
											--file_out $$(@)")


    
endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call aggregate-pair-vcf,$(tumor.$(pair)),$(normal.$(pair)))))
	
define annotate-pair-vcf
mutect/$1_$2/$1_$2_ft.maf : mutect/$1_$2/$1_$2_ft.vcf
	$$(call RUN,-c -n 12 -s 2G -m 4G -v $(VCF2MAF_ENV) -w 24:00:00 -p $(PROJECT_DIR)/mutect -N $1_$2/vcf2maf ,"set -o pipefail && \
														   $$(VCF2MAF) \
														   --input-vcf $$(<) \
														   --output-maf $$(@) \
														   --tmp-dir $$(TMPDIR) \
														   --tumor-id $1 \
														   --normal-id $2 \
														   --vep-path $$(VCF2MAF_ENV)/bin \
														   --vep-data $$(HOME)/share/lib/resource_files/VEP/GRCh37/ \
														   --vep-forks 12 \
														   --ref-fasta $$(HOME)/share/lib/resource_files/VEP/GRCh37/homo_sapiens/99_GRCh37/Homo_sapiens.GRCh37.75.dna.primary_assembly.fa.gz \
														   --filter-vcf $$(HOME)/share/lib/resource_files/VEP/GRCh37/homo_sapiens/99_GRCh37/ExAC_nonTCGA.r0.3.1.sites.vep.vcf.gz \
														   --species homo_sapiens \
														   --ncbi-build GRCh37 \
														   --maf-center MSKCC")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call annotate-pair-vcf,$(tumor.$(pair)),$(normal.$(pair)))))

..DUMMY := $(shell mkdir -p version; \
	$(MUTECT_ENV)/bin/mutect --version &> version/mutect_tumor_normal.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	rm -f mutect/chunk_bed/*