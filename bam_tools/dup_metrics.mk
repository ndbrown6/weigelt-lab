include weigelt-lab/Makefile.inc

LOGDIR ?= log/dup_metrics.$(NOW)

metrics : $(foreach sample,$(SAMPLES),metrics/$(sample).duplicate_metrics.txt) \
		  summary/duplicate_metrics.txt
	 
TARGETS_LIST := $(TARGETS_FILE:.bed=.list)
BAITS_LIST := $(BAITS_FILE:.bed=.list)

PROJECT_DIR := $(notdir $(CURDIR))

define picard-metrics
metrics/$1.duplicate_metrics.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/metrics -N $1/dup_metrics,"set -o pipefail && \
																			      $$(COLLECT_DUP_METRICS) \
																			      INPUT=$$(<) \
																			      METRICS_FILE=$$(@)")
							
endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call picard-metrics,$(sample))))
	
summary/duplicate_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).duplicate_metrics.txt)
	$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/summary -N metrics/dup,"set -o pipefail && \
																			  $(RSCRIPT) $(SCRIPTS_DIR)/summary/bam_metrics.R \
																			  --option 7 \
																			  --sample_names '$(SAMPLES)'")

..DUMMY := $(shell mkdir -p version; \
	echo "picard" >> version/dup_metrics.txt; \
	R --version >> version/dup_metrics.txt)	
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: metrics