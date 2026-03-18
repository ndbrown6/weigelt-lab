include weigelt-lab/Makefile.inc

LOGDIR ?= log/mi_msi.$(NOW)

smry : $(foreach pair,$(SAMPLE_PAIRS),mimsi/$(pair)/$(pair).txt) \
	   mimsi/msi_summary.txt

PROJECT_DIR := $(notdir $(CURDIR))

MICROSATELLITES_LIST = $(HOME)/share/lib/resource_files/mimsi/microsatellites_impact_only.list
MODEL = $(HOME)/share/lib/resource_files/mimsi/mi_msi_v0_4_0_200x.model

define mimsi-tumor-normal
mimsi/$1_$2/$1_$2.txt : bam/$1.bam bam/$2.bam
	$$(call RUN,-c -n 8 -s 1G -m 2G -v $(MIMSI_ENV) -p $(PROJECT_DIR)/mimsi -N $1/$2,"set -o pipefail && \
																					  mkdir -p mimsi/$1_$2/ && \
																					  analyze \
																					  --tumor-bam $$(<) \
																					  --normal-bam $$(<<) \
																					  --case-id $1 \
																					  --norm-case-id $2 \
																					  --microsatellites-list $$(MICROSATELLITES_LIST) \
																					  --save-location mimsi/$1_$2/ \
																					  --model $$(MODEL) \
																					  --save && \
																					  mv mimsi/$1_$2/BATCH_results.txt $$(@)")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
	$(eval $(call mimsi-tumor-normal,$(tumor.$(pair)),$(normal.$(pair)))))
	
mimsi/msi_summary.txt : $(foreach pair,$(SAMPLE_PAIRS),mimsi/$(pair)/$(pair).txt)
	$(call RUN, -c -n 1 -s 8G -m 12G -p $(PROJECT_DIR)/mimsi -N summary,"set -o pipefail && \
																		 $(RSCRIPT) $(SCRIPTS_DIR)/summary/mimsi_summary.R \
																		 --option 1 \
																		 --sample_names '$(SAMPLE_PAIRS)'")

..DUMMY := $(shell mkdir -p version; \
	     $(POLYSOLVER_ENV)/bin/shell_call_hla_type --help &> version/hla_polysolver.txt; \
	     $(POLYSOLVER_ENV)/bin/shell_call_hla_mutations_from_type --help &>> version/hla_polysolver.txt; \
	     $(POLYSOLVER_ENV)/bin/shell_annotate_hla_mutations --help &>> version/hla_polysolver.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
#	rm -f mimsi/*/*.log && \
#	rm -f mimsi/*/*.so