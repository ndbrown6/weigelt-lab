include weigelt-lab/Makefile.inc

LOGDIR ?= log/oxog_metrics.$(NOW)

metrics : $(foreach sample,$(SAMPLES),metrics/$(sample).oxog_metrics.txt) \
	  summary/oxog_metrics.txt
	 
TARGETS_LIST := $(TARGETS_FILE:.bed=.list)
BAITS_LIST := $(BAITS_FILE:.bed=.list)

PROJECT_DIR := $(notdir $(CURDIR))

define picard-metrics
metrics/$1.oxog_metrics.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/metrics -N $1/oxog_metrics,"set -o pipefail && \
										       $$(COLLECT_OXOG_METRICS) \
										       REFERENCE_SEQUENCE=$$(REF_FASTA) \
										       INPUT=$$(<) \
										       OUTPUT=$$(@)")
							
endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call picard-metrics,$(sample))))
	
summary/oxog_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).oxog_metrics.txt)
	$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/summary -N summary/oxog,"set -o pipefail && \
										   $(RSCRIPT) $(SCRIPTS_DIR)/summary/bam_metrics.R --option 4 --sample_names '$(SAMPLES)'")

..DUMMY := $(shell mkdir -p version; \
	     echo "picard" >> version/oxog_metrics.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: