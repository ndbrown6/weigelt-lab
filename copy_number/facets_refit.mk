include weigelt-lab/Makefile.inc

LOGDIR ?= log/facets_refit.$(NOW)

facets : $(foreach pair,$(SAMPLE_PAIRS),facets_refit/$(pair)/$(pair)_hisens.cncf.txt) \
		 $(foreach pair,$(SAMPLE_PAIRS),facets_refit/$(pair)/$(pair)_sunrise_matrix.txt) \
		 facets_refit/summary/aggregated-gene.txt \
		 facets_refit/summary/aggregated-log2.txt \
		 facets_refit/summary/aggregated-segmented.txt \
		 facets_refit/summary/aggregated-purity_ploidy.txt
    
FACETS_MAX_DEPTH ?= 15000
FACETS_CVAL ?= 50
FACETS_PURITY_CVAL ?= 250
FACETS_MIN_NHET ?= 15
FACETS_PURITY_MIN_NHET ?= 10
SNP_WINDOW_SIZE ?= 250
NORMAL_DEPTH ?= 25

PROJECT_DIR := $(notdir $(CURDIR))

define run-facets
facets_refit/$1_$2/$1_$2_hisens.cncf.txt : facets_suite/$1_$2/$1_$2.snp_pileup.gz
	$$(call RUN,-c -s 4G -m 6G -v $(FACETS_SUITE_ENV) -p $(PROJECT_DIR)/facets_refit -N $1_$2/run_facets,"set -o pipefail && \
																									      run-facets-wrapper.R --verbose \
																									      --counts-file $$(<) \
																									      --sample-id $1_$2 \
																									      --directory facets_refit/$1_$2/ \
																									      --everything \
																									      --genome hg19 \
																									      --cval $$(FACETS_CVAL) \
																									      --purity-cval $$(FACETS_PURITY_CVAL) \
																									      --min-nhet $$(FACETS_MIN_NHET) \
																									      --purity-min-nhet $$(FACETS_PURITY_MIN_NHET) \
																									      --snp-window-size $$(SNP_WINDOW_SIZE) \
																									      --normal-depth $$(NORMAL_DEPTH) \
																									      --dipLogR '$(dipLogR.$1_$2)' \
																									      --seed 0 \
																									      --legacy-output True \
																									      --facets-lib-path $(FACETS_SUITE_ENV)/lib/R/library/")
													      
facets_refit/$1_$2/$1_$2_sunrise_matrix.txt : facets_refit/$1_$2/$1_$2_hisens.cncf.txt
	$$(call RUN,-c -s 4G -m 6G -v $(WEIGELT_LAB_ENV) -p $(PROJECT_DIR)/facets_refit -N $1_$2/sunrise,"set -o pipefail && \
																									  $(RSCRIPT) $(SCRIPTS_DIR)/copy_number/facets_refit.R \
																									  --option 1 \
																									  --file_in $$(<) \
																									  --file_out $$(@)")
    
endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call run-facets,$(tumor.$(pair)),$(normal.$(pair)))))

facets_refit/summary/aggregated-gene.txt : $(foreach pair,$(SAMPLE_PAIRS),facets_refit/$(pair)/$(pair)_hisens.cncf.txt)
	$(call RUN, -c -n 1 -s 24G -m 48G -v $(WEIGELT_LAB_ENV) -p $(PROJECT_DIR)/facets_refit -N aggregate/gene,"set -o pipefail && \
																											  $(RSCRIPT) $(SCRIPTS_DIR)/copy_number/facets_refit.R \
																											  --option 2 \
																											  --sample_pairs '$(SAMPLE_PAIRS)' \
																											  --file_out $(@)")
														  
facets_refit/summary/aggregated-log2.txt : $(foreach pair,$(SAMPLE_PAIRS),facets_refit/$(pair)/$(pair)_hisens.cncf.txt)
	$(call RUN, -c -n 1 -s 24G -m 48G -v $(WEIGELT_LAB_ENV) -p $(PROJECT_DIR)/facets_refit -N aggregate/log2,"set -o pipefail && \
																											  $(RSCRIPT) $(SCRIPTS_DIR)/copy_number/facets_refit.R \
																											  --option 3 \
																											  --sample_pairs '$(SAMPLE_PAIRS)' \
																											  --file_out $(@)")
														  
facets_refit/summary/aggregated-segmented.txt : $(foreach pair,$(SAMPLE_PAIRS),facets_refit/$(pair)/$(pair)_hisens.cncf.txt)
	$(call RUN, -c -n 1 -s 12G -m 24G -v $(WEIGELT_LAB_ENV) -p $(PROJECT_DIR)/facets_refit -N aggregate/segments,"set -o pipefail && \
																											      $(RSCRIPT) $(SCRIPTS_DIR)/copy_number/facets_refit.R \
																											      --option 4 \
																											      --sample_pairs '$(SAMPLE_PAIRS)' \
																											      --file_out $(@)")

facets_refit/summary/aggregated-purity_ploidy.txt : $(foreach pair,$(SAMPLE_PAIRS),facets_refit/$(pair)/$(pair)_hisens.cncf.txt)
	$(call RUN, -c -n 1 -s 4G -m 8G -v $(WEIGELT_LAB_ENV) -p $(PROJECT_DIR)/facets_refit -N aggregate/purity,"set -o pipefail && \
																											  $(RSCRIPT) $(SCRIPTS_DIR)/copy_number/facets_refit.R \
																											  --option 5 \
																											  --sample_pairs '$(SAMPLE_PAIRS)' \
																											  --file_out $(@)")

..DUMMY := $(shell mkdir -p version; \
	$(FACETS_SUITE_ENV)/bin/R --version > version/facets_refit.txt; \
	R --version >> version/facets_refit.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
