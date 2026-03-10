include weigelt-lab/Makefile.inc

LOGDIR ?= log/rnaseq_metrics.$(NOW)

metrics : $(foreach sample,$(SAMPLES),metrics/$(sample)_rnaseq_metrics.txt) \
		  summary/rnaseq_metrics.txt
       
REF_FLAT ?= $(HOME)/share/lib/resource_files/refFlat_ensembl.v75.txt
RIBOSOMAL_INTERVALS ?= $(HOME)/share/lib/resource_files/Homo_sapiens.GRCh37.75.rRNA.interval_list
STRAND_SPECIFICITY ?= NONE

PROJECT_DIR := $(notdir $(CURDIR))

define picard-metrics
metrics/$1_rnaseq_metrics.txt : bam/$1.bam
	$$(call RUN,-c -n 1 -s 6G -m 12G -p $(PROJECT_DIR)/metrics -N $1/rnaseq_metrics,"set -o pipefail && \
																					 $$(COLLECT_RNASEQ_METRICS) \
																					 INPUT=$$(<) \
																					 OUTPUT=$$(@) \
																					 REF_FLAT=$$(REF_FLAT) \
																					 RIBOSOMAL_INTERVALS=$$(RIBOSOMAL_INTERVALS) \
																					 CHART_OUTPUT=metrics/$1_rnaseq_metrics.pdf \
																					 STRAND_SPECIFICITY=$$(STRAND_SPECIFICITY)")

endef
$(foreach sample,$(SAMPLES),\
		$(eval $(call picard-metrics,$(sample))))
		
summary/rnaseq_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample)_rnaseq_metrics.txt)
	$(call RUN, -c -n 1 -s 4G -m 6G -p $(PROJECT_DIR)/summary -N metrics/rnaseq,"set -o pipefail && \
																			     $(RSCRIPT) $(SCRIPTS_DIR)/summary/rnaseq_metrics.R \
																			     --option 1 \
																			     --sample_names '$(SAMPLES)'")

..DUMMY := $(shell mkdir -p version; \
	echo "picard" >> version/rnaseq_metrics.txt; \
	R --version >> version/rnaseq_metrics.txt)	     
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: metrics