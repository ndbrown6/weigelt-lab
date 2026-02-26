include weigelt-lab/Makefile.inc

LOGDIR ?= log/facets_suite.$(NOW)

facets : facets_suite/targets_dbsnp.vcf \
	 $(foreach pair,$(SAMPLE_PAIRS),facets_suite/$(pair)/$(pair).snp_pileup.gz) \
	 $(foreach pair,$(SAMPLE_PAIRS),facets_suite/$(pair)/taskcomplete) \
	 facets_suite/summary/aggregated-gene.txt \
	 facets_suite/summary/aggregated-log2.txt \
	 facets_suite/summary/aggregated-segmented.txt \
	 facets_suite/summary/aggregated-purity_ploidy.txt
    
FACETS_MAX_DEPTH ?= 15000
FACETS_CVAL ?= 50
FACETS_PURITY_CVAL ?= 30
FACETS_MIN_NHET ?= 15
FACETS_PURITY_MIN_NHET ?= 10
SNP_WINDOW_SIZE ?= 250
NORMAL_DEPTH ?= 25

PROJECT_DIR := $(notdir $(CURDIR))

BAM_SOURCE ?= local

facets_suite/targets_dbsnp.vcf : $(TARGETS_FILE)
	$(call RUN,-c -n 1 -s 6G -m 8G -p $(PROJECT_DIR) -N dbsnp_intersect,"set -o pipefail && \
									     $(BEDTOOLS) intersect -header -u -a $(DBSNP_137) -b $(<) > $(@)")

ifeq ($(BAM_SOURCE),irb)
define snp-pileup
facets_suite/$1_$2/$1_$2.snp_pileup.gz : facets_suite/targets_dbsnp.vcf
	$$(call RUN,-c -s 2G -m 4G -v $(FACETS_SUITE_ENV) -p $(PROJECT_DIR)/facets_suite -N $1_$2/snp_pileup,"set -o pipefail && \
													      mkdir -p facets_suite/$1_$2 && \
													      snp-pileup-wrapper.R --verbose \
													      -sp $(FACETS_SUITE_ENV)/bin/snp-pileup \
													      --vcf-file $$(<) \
													      --tumor-bam /data1/share001/share/impact_12_245/`echo $2 | cut -c 1-1`/`echo $2 | cut -c 2-2`/$1.bam \
													      --normal-bam /data1/share001/share/impact_12_245/`echo $1 | cut -c 1-1`/`echo $1 | cut -c 2-2`/$2.bam \
													      --output-prefix facets_suite/$1_$2/$1_$2 \
													      --pseudo-snps 50 \
													      --max-depth $$(FACETS_MAX_DEPTH)")
endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call snp-pileup,$(tumor.$(pair)),$(normal.$(pair)))))
else
define snp-pileup
facets_suite/$1_$2/$1_$2.snp_pileup.gz : facets_suite/targets_dbsnp.vcf bam/$1.bam bam/$2.bam
	$$(call RUN,-c -s 2G -m 4G -v $(FACETS_SUITE_ENV) -p $(PROJECT_DIR)/facets_suite -N $1_$2/snp_pileup,"set -o pipefail && \
													      mkdir -p facets_suite/$1_$2 && \
													      snp-pileup-wrapper.R --verbose \
													      -sp $(FACETS_SUITE_ENV)/bin/snp-pileup \
													      --vcf-file $$(<) \
													      --tumor-bam $$(<<) \
													      --normal-bam $$(<<<) \
													      --output-prefix facets_suite/$1_$2/$1_$2 \
													      --pseudo-snps 50 \
													      --max-depth $$(FACETS_MAX_DEPTH)")
endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call snp-pileup,$(tumor.$(pair)),$(normal.$(pair)))))
endif

define run-facets
facets_suite/$1_$2/taskcomplete : facets_suite/$1_$2/$1_$2.snp_pileup.gz
	$$(call RUN,-c -s 4G -m 6G -v $(FACETS_SUITE_ENV) -p $(PROJECT_DIR)/facets_suite -N $1_$2/run_facets,"set -o pipefail && \
													      run-facets-wrapper.R --verbose \
													      --counts-file $$(<) \
													      --sample-id $1_$2 \
													      --directory facets_suite/$1_$2/ \
													      --everything \
													      --genome hg19 \
													      --cval $$(FACETS_CVAL) \
													      --purity-cval $$(FACETS_PURITY_CVAL) \
													      --min-nhet $$(FACETS_MIN_NHET) \
													      --purity-min-nhet $$(FACETS_PURITY_MIN_NHET) \
													      --snp-window-size $$(SNP_WINDOW_SIZE) \
													      --normal-depth $$(NORMAL_DEPTH) \
													      --seed 0 \
													      --legacy-output True \
													      --facets-lib-path $(FACETS_SUITE_ENV)/lib/R/library/ && \
													      echo 'finished!' > $$(@)")
    
endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call run-facets,$(tumor.$(pair)),$(normal.$(pair)))))

facets_suite/summary/aggregated-gene.txt : $(foreach pair,$(SAMPLE_PAIRS),facets_suite/$(pair)/taskcomplete)
	$(call RUN, -c -n 1 -s 24G -m 48G -v $(WEIGELT_LAB_ENV) -p $(PROJECT_DIR)/facets_suite -N aggregate/gene,"set -o pipefail && \
														  $(RSCRIPT) $(SCRIPTS_DIR)/copy_number/facets_suite.R \
														  --option 1 \
														  --sample_pairs '$(SAMPLE_PAIRS)' \
														  --file_out $(@)")
														  
facets_suite/summary/aggregated-log2.txt : $(foreach pair,$(SAMPLE_PAIRS),facets_suite/$(pair)/taskcomplete)
	$(call RUN, -c -n 1 -s 24G -m 48G -v $(WEIGELT_LAB_ENV) -p $(PROJECT_DIR)/facets_suite -N aggregate/log2,"set -o pipefail && \
														  $(RSCRIPT) $(SCRIPTS_DIR)/copy_number/facets_suite.R \
														  --option 2 \
														  --sample_pairs '$(SAMPLE_PAIRS)' \
														  --file_out $(@)")
														  
facets_suite/summary/aggregated-segmented.txt : $(foreach pair,$(SAMPLE_PAIRS),facets_suite/$(pair)/taskcomplete)
	$(call RUN, -c -n 1 -s 12G -m 24G -v $(WEIGELT_LAB_ENV) -p $(PROJECT_DIR)/facets_suite -N aggregate/segments,"set -o pipefail && \
														      $(RSCRIPT) $(SCRIPTS_DIR)/copy_number/facets_suite.R \
														      --option 3 \
														      --sample_pairs '$(SAMPLE_PAIRS)' \
														      --file_out $(@)")

facets_suite/summary/aggregated-purity_ploidy.txt : $(foreach pair,$(SAMPLE_PAIRS),facets_suite/$(pair)/taskcomplete)
	$(call RUN, -c -n 1 -s 4G -m 8G -v $(WEIGELT_LAB_ENV) -p $(PROJECT_DIR)/facets_suite -N aggregate/purity,"set -o pipefail && \
														  $(RSCRIPT) $(SCRIPTS_DIR)/copy_number/facets_suite.R \
														  --option 4 \
														  --sample_pairs '$(SAMPLE_PAIRS)' \
														  --file_out $(@)")

..DUMMY := $(shell mkdir -p version; \
         $(FACETS_SUITE_ENV)/bin/R --version > version/facets_suite.txt; \
	 R --version >> version/facets_suite.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	rm -f facets_suite/targets_dbsnp.vcf && \
	rm -f facets_suite/*/*snp_pileup.gz && \
	rm -f facets_suite/*/*taskcomplete